package com.letscook.platform.room;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Data exchanged between the watch queue repository, service, and API. */
public final class WatchQueueModels {
    private WatchQueueModels() {}

    public record QueuePicker(UUID userId, String displayName, String avatarUrl) {}

    public record QueueItem(
            UUID id,
            String provider,
            String mediaId,
            String title,
            String thumbnailUrl,
            UUID addedBy,
            String addedByName,
            int personalPosition,
            boolean personalQueueItem,
            int voteCount,
            boolean votedByMe,
            List<QueuePicker> pickers,
            Instant createdAt) {
        QueueItem withPickers(List<QueuePicker> value) {
            return new QueueItem(
                    id,
                    provider,
                    mediaId,
                    title,
                    thumbnailUrl,
                    addedBy,
                    addedByName,
                    personalPosition,
                    personalQueueItem,
                    voteCount,
                    votedByMe,
                    List.copyOf(value),
                    createdAt);
        }
    }

    public record QueueResponse(
            String mode,
            int transitionSeconds,
            boolean canAdd,
            UUID nextItemId,
            int skipVotes,
            int skipRequired,
            boolean skipVotedByMe,
            List<QueueItem> items) {}

    public record QueueSettings(String mode, int transitionSeconds) {}

    public record SkipStatus(int votes, int required, boolean votedByMe) {}

    public record NextVideo(
            UUID id,
            String provider,
            String mediaId,
            String title,
            UUID addedBy,
            Instant createdAt,
            int votes) {}
}
