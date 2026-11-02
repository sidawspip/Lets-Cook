package com.letscook.platform.common;

import java.util.UUID;

/** Prevents an email-shaped account username from leaking through public APIs. */
public final class PublicIdentity {
    private PublicIdentity() {}

    public static String handle(String username, UUID userId) {
        String value = username == null ? "" : username.strip();
        if (!value.isEmpty() && !value.contains("@")) return value;
        String suffix = userId == null ? "" : userId.toString().substring(0, 8);
        return suffix.isEmpty() ? "member" : "member-" + suffix;
    }

    public static String displayName(String displayName, String username, UUID userId) {
        String value = displayName == null ? "" : displayName.strip();
        if (!value.isEmpty() && !value.contains("@")) return value;
        String handle = handle(username, userId);
        return handle.equals("member") ? "Member" : handle;
    }
}
