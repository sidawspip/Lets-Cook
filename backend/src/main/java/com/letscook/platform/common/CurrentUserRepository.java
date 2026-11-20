package com.letscook.platform.common;

import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Persistence for mapping Keycloak identity subjects to {@code app_users} and refreshing claims.
 */
@Repository
public class CurrentUserRepository {
    private final JdbcClient jdbc;

    public CurrentUserRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public CurrentUser upsert(
            UUID proposedId,
            String subject,
            String username,
            String displayName,
            String email,
            String avatarUrl) {
        return jdbc.sql("""
                        INSERT INTO app_users (id, identity_subject, username, display_name, email, avatar_url)
                        VALUES (:id, :subject,
                            CASE WHEN EXISTS (
                                SELECT 1 FROM app_users
                                WHERE username = :username AND identity_subject <> :subject
                            ) THEN LEFT(:username, 63) || '-' || LEFT(:subject, 12)
                            ELSE :username END,
                            :displayName, :email, :avatarUrl)
                        ON CONFLICT (identity_subject) DO UPDATE SET
                            email = COALESCE(EXCLUDED.email, app_users.email),
                            avatar_url = COALESCE(app_users.avatar_url, EXCLUDED.avatar_url),
                            status = 'ONLINE',
                            updated_at = now(),
                            last_seen_at = now()
                        RETURNING id, username, display_name, email
                        """)
                .param("id", proposedId)
                .param("subject", subject)
                .param("username", username)
                .param("displayName", displayName)
                .param("email", email)
                .param("avatarUrl", avatarUrl)
                .query((rs, rowNum) -> new CurrentUser(
                        rs.getObject("id", UUID.class),
                        rs.getString("username"),
                        rs.getString("display_name"),
                        rs.getString("email")))
                .single();
    }
}
