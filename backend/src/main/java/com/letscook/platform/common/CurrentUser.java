package com.letscook.platform.common;

import java.util.UUID;

public record CurrentUser(UUID id, String username, String displayName, String email) {
}

