package com.letscook.platform.common;

import java.net.URI;
import java.util.Optional;
import java.util.UUID;

import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;

/**
 * Business logic for application-user synchronization.
 *
 * <p>Requires a JWT subject, derives safe username/display-name defaults, and delegates the
 * idempotent insert/update to {@link CurrentUserRepository}.</p>
 */
@Service
public class CurrentUserServiceImpl implements CurrentUserService {
    private final CurrentUserRepository repository;

    public CurrentUserServiceImpl(CurrentUserRepository repository) {
        this.repository = repository;
    }

    @Override
    public CurrentUser synchronize(Jwt jwt) {
        String fallback = "user-" + jwt.getSubject().substring(0, Math.min(8, jwt.getSubject().length()));
        String username = claim(jwt, "preferred_username").orElse(fallback);
        String displayName = claim(jwt, "name").orElse(username);
        String email = claim(jwt, "email").orElse(null);
        String avatarUrl = firstClaim(jwt, "picture", "avatar_url", "profile_image_url")
                .filter(this::isSafeProviderImage)
                .orElse(null);
        return repository.upsert(
                UUID.randomUUID(), jwt.getSubject(), username, displayName, email, avatarUrl);
    }

    private Optional<String> claim(Jwt jwt, String name) {
        return Optional.ofNullable(jwt.getClaimAsString(name)).filter(value -> !value.isBlank());
    }

    private Optional<String> firstClaim(Jwt jwt, String... names) {
        for (String name : names) {
            Optional<String> value = claim(jwt, name);
            if (value.isPresent()) return value;
        }
        return Optional.empty();
    }

    private boolean isSafeProviderImage(String value) {
        if (value.length() > 2048) return false;
        try {
            URI uri = URI.create(value);
            return uri.isAbsolute()
                    && uri.getHost() != null
                    && ("https".equalsIgnoreCase(uri.getScheme())
                    || "http".equalsIgnoreCase(uri.getScheme()));
        } catch (IllegalArgumentException ignored) {
            return false;
        }
    }
}
