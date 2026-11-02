package com.letscook.platform.common;

import org.springframework.security.oauth2.jwt.Jwt;

/**
 * Maps a verified Keycloak JWT to the application's current user.
 * Implementations synchronize identity claims and last-seen information before returning.
 */
public interface CurrentUserService {
    /** Synchronizes JWT identity claims into {@code app_users} and returns the application user. */
    CurrentUser synchronize(Jwt jwt);
}

