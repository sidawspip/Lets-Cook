package com.letscook.platform.room;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class LiveRoomModels {
    private LiveRoomModels() {}

    public record Participant(
            UUID userId,
            String username,
            String displayName,
            String avatarUrl,
            RoomRole role,
            boolean canShareScreen,
            boolean canAddVideos,
            boolean canViewVideo,
            boolean videoAccessRequested) {}

    public record ChatMessage(
            UUID id,
            UUID senderId,
            String senderName,
            String senderUsername,
            String avatarUrl,
            String body,
            String type,
            ReplyPreview replyTo,
            List<ChatReaction> reactions,
            String mediaProvider,
            String mediaId,
            String mediaTitle,
            Instant createdAt) {}

    public record ReplyPreview(
            UUID id,
            UUID senderId,
            String senderName,
            String senderUsername,
            String body,
            String type) {}

    public record ChatReaction(String reaction, int count, boolean reactedByMe) {}

    public record RecentPerson(
            UUID userId,
            String username,
            String displayName,
            String avatarUrl,
            String roomName,
            Instant lastSeenAt,
            boolean friend) {}

    public record SendChat(@NotBlank @Size(max = 2000) String body, UUID replyToId) {}

    public record ShareVideo(
            @NotBlank @Size(max = 40) String provider,
            @NotBlank @Size(max = 2000) String mediaId,
            @NotBlank @Size(max = 500) String title) {}

    public record ReactionRequest(@NotBlank @Size(max = 16) String reaction) {}

    public record MentionEvent(
            String type,
            UUID senderId,
            String senderName,
            String body,
            UUID roomId,
            UUID messageId,
            boolean haptic) {}

    public record MentionTarget(UUID userId, String subject, boolean hapticFeedback) {}

    public record TimelineChanged(UUID roomId, String action, UUID messageId) {}
}
