package com.letscook.platform.auth;

import tools.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.springframework.http.HttpStatus.*;

/**
 * Verifies Google ID tokens locally, provisions new verified-email users or links an existing
 * verified-email account, and performs the confidential RFC 7523 grant server-side.
 */
@Service
public class NativeGoogleAuthService {
    private static final String REALM = "xynk";
    private static final String GOOGLE = "google";
    private static final String JWT_BEARER = "urn:ietf:params:oauth:grant-type:jwt-bearer";

    private final RestClient http;
    private final JwtDecoder googleTokens;
    private final String keycloakUrl;
    private final String clientId;
    private final String clientSecret;

    NativeGoogleAuthService(
            @Value("${app.auth.keycloak-url}") String keycloakUrl,
            @Value("${app.auth.keycloak-client-id}") String clientId,
            @Value("${app.auth.keycloak-client-secret}") String clientSecret,
            @Value("${app.auth.google-web-client-id}") String googleWebClientId) {
        this.http = RestClient.create();
        this.keycloakUrl = keycloakUrl.replaceAll("/+$", "");
        this.clientId = clientId;
        this.clientSecret = clientSecret;

        NimbusJwtDecoder decoder = NimbusJwtDecoder
                .withJwkSetUri("https://www.googleapis.com/oauth2/v3/certs")
                .build();
        OAuth2TokenValidator<Jwt> audience = jwt -> jwt.getAudience().contains(googleWebClientId)
                ? OAuth2TokenValidatorResult.success()
                : OAuth2TokenValidatorResult.failure(new OAuth2Error(
                        "invalid_token", "Google token audience does not match Xynk.", null));
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefault(),
                new JwtIssuerValidator("https://accounts.google.com"),
                audience));
        this.googleTokens = decoder;
    }

    Map<String, Object> authenticate(String idToken) {
        requireConfigured();
        Jwt google = verify(idToken);
        String email = google.getClaimAsString("email");
        if (email == null || email.isBlank() || !Boolean.TRUE.equals(google.getClaim("email_verified"))) {
            throw new ResponseStatusException(UNAUTHORIZED, "Google did not provide a verified email address.");
        }

        String adminToken = serviceAccountToken();
        ensureFederatedUser(adminToken, google, email);
        return exchangeAssertion(idToken);
    }

    private Jwt verify(String idToken) {
        try {
            return googleTokens.decode(idToken);
        } catch (JwtException exception) {
            throw new ResponseStatusException(UNAUTHORIZED, "Google sign-in token is invalid or expired.");
        }
    }

    private void ensureFederatedUser(String adminToken, Jwt google, String email) {
        JsonNode matches = getAdmin("/users", adminToken, Map.of("email", email, "exact", "true"));
        JsonNode user;
        boolean created = matches.isEmpty();
        if (created) {
            user = createUser(adminToken, google, email);
        } else {
            user = matches.get(0);
        }

        String userId = user.path("id").asText();
        JsonNode links = getAdmin("/users/" + userId + "/federated-identity", adminToken, Map.of());
        for (JsonNode link : links) {
            if (GOOGLE.equals(link.path("identityProvider").asText())) {
                if (!google.getSubject().equals(link.path("userId").asText())) {
                    throw new ResponseStatusException(CONFLICT, "This account is linked to a different Google identity.");
                }
                return;
            }
        }

        if (!created && !user.path("emailVerified").asBoolean(false)) {
            throw new ResponseStatusException(CONFLICT,
                    "An unverified account with this email already exists. Verify it before linking Google.");
        }

        Map<String, Object> link = Map.of(
                "identityProvider", GOOGLE,
                "userId", google.getSubject(),
                "userName", email);
        http.post()
                .uri(adminBase() + "/users/" + userId + "/federated-identity/" + GOOGLE)
                .header("Authorization", "Bearer " + adminToken)
                .contentType(MediaType.APPLICATION_JSON)
                .body(link)
                .retrieve()
                .toBodilessEntity();
    }

    private JsonNode createUser(String adminToken, Jwt google, String email) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("username", "google_" + google.getSubject());
        body.put("email", email);
        body.put("emailVerified", true);
        body.put("enabled", true);
        putIfPresent(body, "firstName", google.getClaimAsString("given_name"));
        putIfPresent(body, "lastName", google.getClaimAsString("family_name"));
        String picture = google.getClaimAsString("picture");
        if (picture != null && !picture.isBlank()) {
            body.put("attributes", Map.of("picture", List.of(picture)));
        }

        URI location;
        try {
            location = http.post()
                    .uri(adminBase() + "/users")
                    .header("Authorization", "Bearer " + adminToken)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .toBodilessEntity()
                    .getHeaders()
                    .getLocation();
        } catch (RestClientResponseException exception) {
            throw keycloakFailure(exception, "Could not create the Google user.");
        }
        if (location == null) {
            throw new ResponseStatusException(BAD_GATEWAY, "Keycloak did not return the new user identifier.");
        }
        String id = location.getPath().substring(location.getPath().lastIndexOf('/') + 1);
        return getAdmin("/users/" + id, adminToken, Map.of());
    }

    private String serviceAccountToken() {
        var form = new LinkedMultiValueMap<String, String>();
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        form.add("grant_type", "client_credentials");
        JsonNode response = postToken(form);
        String token = response.path("access_token").asText();
        if (token.isBlank()) throw new ResponseStatusException(BAD_GATEWAY, "Keycloak service authentication failed.");
        return token;
    }

    private Map<String, Object> exchangeAssertion(String assertion) {
        var form = new LinkedMultiValueMap<String, String>();
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);
        form.add("grant_type", JWT_BEARER);
        form.add("assertion", assertion);
        form.add("scope", "openid profile email");
        JsonNode response = postToken(form);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("access_token", response.path("access_token").asText());
        result.put("expires_in", response.path("expires_in").asInt(300));
        result.put("token_type", response.path("token_type").asText("Bearer"));
        result.put("refresh_token", "native-google");
        return result;
    }

    private JsonNode postToken(LinkedMultiValueMap<String, String> form) {
        try {
            return http.post()
                    .uri(keycloakUrl + "/realms/" + REALM + "/protocol/openid-connect/token")
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(form)
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RestClientResponseException exception) {
            throw keycloakFailure(exception, "Keycloak rejected native Google sign-in.");
        }
    }

    private JsonNode getAdmin(String path, String token, Map<String, String> query) {
        var uri = UriComponentsBuilder.fromUriString(adminBase() + path);
        query.forEach(uri::queryParam);
        try {
            return http.get()
                    .uri(uri.build(true).toUri())
                    .header("Authorization", "Bearer " + token)
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RestClientResponseException exception) {
            throw keycloakFailure(exception, "Keycloak user lookup failed.");
        }
    }

    private String adminBase() {
        return keycloakUrl + "/admin/realms/" + REALM;
    }

    private void requireConfigured() {
        if (clientId.isBlank() || clientSecret.isBlank()) {
            throw new ResponseStatusException(SERVICE_UNAVAILABLE, "Native Google sign-in is not configured.");
        }
    }

    private static void putIfPresent(Map<String, Object> values, String key, String value) {
        if (value != null && !value.isBlank()) values.put(key, value);
    }

    private static ResponseStatusException keycloakFailure(RestClientResponseException error, String fallback) {
        String detail = fallback;
        try {
            JsonNode json = new tools.jackson.databind.ObjectMapper().readTree(error.getResponseBodyAsString());
            String supplied = json.path("error_description").asText(json.path("errorMessage").asText());
            if (!supplied.isBlank()) detail = supplied;
        } catch (Exception ignored) {
            // Keep the safe fallback; never echo client secrets or raw upstream bodies.
        }
        return new ResponseStatusException(BAD_GATEWAY, detail);
    }
}
