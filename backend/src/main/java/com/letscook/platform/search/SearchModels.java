package com.letscook.platform.search;

import com.letscook.platform.room.AccessPolicy;
import java.util.List;
import java.util.UUID;

public final class SearchModels {
    private SearchModels() {}

    public record SearchResult(List<UserResult> users, List<RoomResult> rooms, List<Object> messages) {}

    public record UserResult(UUID id, String username, String displayName, String avatarUrl) {}

    public record RoomResult(
            UUID id,
            String name,
            String description,
            AccessPolicy accessPolicy,
            boolean locked,
            int memberCount,
            String visibility) {}
}
