package com.letscook.platform.room;

public enum AccessPolicy {
    OPEN,
    INVITE_ONLY,
    KEY_ONLY,
    INVITE_OR_KEY,
    INVITE_AND_KEY;

    public boolean usesKey() {
        return this == KEY_ONLY || this == INVITE_OR_KEY || this == INVITE_AND_KEY;
    }
}

