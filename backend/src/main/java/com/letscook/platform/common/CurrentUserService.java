package com.letscook.platform.common;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;

import java.util.Optional;
import java.util.UUID;

@Service
public class CurrentUserService {
    private final JdbcClient jdbc;

    public CurrentUserService(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public CurrentUser synchronize(Jwt jwt) {
        String username = claim(jwt, "preferred_username").orElse("user-" + jwt.getSubject().substring(0, 8));
        String displayName = claim(jwt, "name").orElse(username);
        String email = claim(jwt, "email").orElse(null);
        UUID proposedId = UUID.randomUUID();

        return jdbc.sql("""
                        INSERT INTO app_users (id, identity_subject, username, display_name, email)
                        VALUES (:id, :subject, :username, :displayName, :email)
                        ON CONFLICT (identity_subject) DO UPDATE SET
                            username = EXCLUDED.username,
                            display_name = EXCLUDED.display_name,
                            email = EXCLUDED.email,
                            status = 'ONLINE',
                            updated_at = now(),
                            last_seen_at = now()
                        RETURNING id, username, display_name, email
                        """)
                .param("id", proposedId)
                .param("subject", jwt.getSubject())
                .param("username", username)
                .param("displayName", displayName)
                .param("email", email)
                .query((rs, rowNum) -> new CurrentUser(
                        rs.getObject("id", UUID.class),
                        rs.getString("username"),
                        rs.getString("display_name"),
                        rs.getString("email")))
                .single();
    }

    private Optional<String> claim(Jwt jwt, String name) {
        return Optional.ofNullable(jwt.getClaimAsString(name)).filter(value -> !value.isBlank());
    }
}

