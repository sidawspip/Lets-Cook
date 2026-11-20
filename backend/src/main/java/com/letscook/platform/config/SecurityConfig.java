package com.letscook.platform.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.http.HttpMethod;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

/**
 * HTTP API security contract.
 *
 * <p>Validates Keycloak JWTs, permits only health/public-file/WebSocket bootstrap routes without
 * a bearer token, configures trusted issuers and CORS, and provides password hashing for room keys.</p>
 */
@Configuration
public class SecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http
                .cors(Customizer.withDefaults())
                .csrf(csrf -> csrf.disable())
                .authorizeHttpRequests(auth -> auth
                        // The WebSocket upgrade request targets exactly /ws; /ws/**
                        // only covers child paths and caused native clients to receive
                        // an HTTP 401 before their authenticated STOMP CONNECT frame.
                        .requestMatchers("/actuator/health", "/actuator/info", "/ws", "/ws/**").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/auth/google/native").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/me/avatar/**").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/social/attachments/**").permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(oauth -> oauth.jwt(Customizer.withDefaults()))
                .build();
    }

    @Bean
    JwtDecoder jwtDecoder(
            @org.springframework.beans.factory.annotation.Value("${spring.security.oauth2.resourceserver.jwt.jwk-set-uri}") String jwkSetUri) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
        var allowedIssuers = java.util.Set.of(
                "http://localhost:8180/realms/xynk",
                // Android Emulator routes the development host through this
                // fixed alias, so Keycloak-issued mobile tokens use it as iss.
                "http://10.0.2.2:8180/realms/xynk",
                "http://192.168.0.3:8180/realms/xynk",
                "http://192.168.0.5:8180/realms/xynk",
                "http://keycloak:8080/realms/xynk",
                "https://xynk.in/realms/xynk",
                "https://auth.xynk.in/realms/xynk",
                "https://www.xynk.in/realms/xynk");
        var acceptedIssuer = new JwtClaimValidator<String>("iss", issuer -> issuer != null && (
                allowedIssuers.contains(issuer)
                        || issuer.matches("https://[a-z0-9-]+\\.trycloudflare\\.com/realms/xynk")));
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefault(),
                acceptedIssuer));
        return decoder;
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }

    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOrigins(List.of(
                "https://xynk.in",
                "https://www.xynk.in",
                "http://localhost:4200",
                "http://192.168.0.3:4200",
                "http://192.168.0.5:4200"));
        configuration.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }
}
