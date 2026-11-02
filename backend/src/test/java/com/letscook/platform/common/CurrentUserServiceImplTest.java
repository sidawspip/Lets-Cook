package com.letscook.platform.common;

import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.Instant;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CurrentUserServiceImplTest {
    @Test
    void initializesProfileFromProviderClaims() {
        CurrentUserRepository repository = mock(CurrentUserRepository.class);
        CurrentUser expected = new CurrentUser(UUID.randomUUID(), "chef", "Chef Name", "chef@example.com");
        when(repository.upsert(any(), any(), any(), any(), any(), any())).thenReturn(expected);

        Jwt jwt = token("https://images.example.com/avatar.jpg");
        new CurrentUserServiceImpl(repository).synchronize(jwt);

        verify(repository).upsert(
                any(UUID.class),
                eq("provider-subject"),
                eq("chef"),
                eq("Chef Name"),
                eq("chef@example.com"),
                eq("https://images.example.com/avatar.jpg"));
    }

    @Test
    void rejectsUnsafeProviderAvatarUrls() {
        CurrentUserRepository repository = mock(CurrentUserRepository.class);
        CurrentUser expected = new CurrentUser(UUID.randomUUID(), "chef", "Chef Name", "chef@example.com");
        when(repository.upsert(any(), any(), any(), any(), any(), any())).thenReturn(expected);

        new CurrentUserServiceImpl(repository).synchronize(token("javascript:alert(1)"));

        verify(repository).upsert(
                any(UUID.class),
                eq("provider-subject"),
                eq("chef"),
                eq("Chef Name"),
                eq("chef@example.com"),
                eq(null));
    }

    private Jwt token(String picture) {
        Instant now = Instant.now();
        return Jwt.withTokenValue("test-token")
                .header("alg", "none")
                .subject("provider-subject")
                .claim("preferred_username", "chef")
                .claim("name", "Chef Name")
                .claim("email", "chef@example.com")
                .claim("picture", picture)
                .issuedAt(now)
                .expiresAt(now.plusSeconds(300))
                .build();
    }
}
