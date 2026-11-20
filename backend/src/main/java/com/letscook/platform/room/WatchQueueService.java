package com.letscook.platform.room;

import static com.letscook.platform.room.WatchQueueModels.*;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Queue policy contract for ranking, deduplication, voting, personal ordering, and skip votes.
 */
public interface WatchQueueService {
    /** Builds ranked queue state with caller-specific permissions and skip status. */
    QueueResponse queue(UUID roomId, UUID userId);

    /** Validates and inserts/selects one deduplicated media item. */
    QueueItem add(
            UUID roomId,
            UUID userId,
            String provider,
            String mediaId,
            String sourceUrl,
            String title,
            String thumbnailUrl,
            boolean personalQueueItem);

    /** Replaces the caller's personal ordering using their complete owned queue. */
    void reorder(UUID roomId, UUID userId, List<UUID> queueIds);

    /** Replaces the caller's single active room pick with one existing queue item. */
    void toggleVote(UUID roomId, UUID userId, UUID queueId);

    /** Deletes one queue item and its dependent selections. */
    void remove(UUID roomId, UUID queueId);

    /** Adds an idempotent vote to skip the currently playing media. */
    SkipStatus addSkipVote(UUID roomId, UUID userId);

    /** Takes the requested or highest-ranked playable item and marks it played. */
    Optional<NextVideo> takeNext(UUID roomId, UUID requestedQueueId);

    /** Loads current queue mode and transition delay. */
    QueueSettings settings(UUID roomId);

    /** Validates and updates queue mode plus clamped transition delay. */
    void updateSettings(UUID roomId, String mode, int transitionSeconds);

    /** Updates a member's explicit add-video permission. */
    void updateVideoPermission(UUID roomId, UUID userId, boolean allowed);
}
