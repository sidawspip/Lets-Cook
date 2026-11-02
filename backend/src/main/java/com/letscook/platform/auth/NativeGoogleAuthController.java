package com.letscook.platform.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/** Exchanges an Android Credential Manager Google ID token for a scoped Keycloak access token. */
@RestController
@RequestMapping("/api/auth/google")
public class NativeGoogleAuthController {
    private final NativeGoogleAuthService auth;

    public NativeGoogleAuthController(NativeGoogleAuthService auth) {
        this.auth = auth;
    }

    @PostMapping("/native")
    Map<String, Object> nativeLogin(@Valid @RequestBody NativeGoogleRequest request) {
        return auth.authenticate(request.idToken());
    }

    record NativeGoogleRequest(@NotBlank @Size(max = 8192) String idToken) {}
}
