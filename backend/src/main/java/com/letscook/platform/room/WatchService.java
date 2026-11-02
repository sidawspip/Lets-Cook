package com.letscook.platform.room;

import static com.letscook.platform.room.WatchModels.*;
import static com.letscook.platform.room.WatchQueueModels.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Synchronized playback use cases, including state, commands, heartbeats, queue operations,
 * voting, settings, per-member permissions, and provider search.
 */
public interface WatchService {
    /** Returns current playback state after membership validation. */
    WatchState state(UUID roomId, UUID userId);
    /** Replaces and broadcasts playback state as host. */
    WatchState update(UUID roomId, UUID userId, WatchUpdate input);
    /** Applies one idempotent revision-aware playback command as host. */
    void command(UUID roomId, UUID userId, WatchCommand command);
    /** Refreshes authoritative playback time as host. */
    WatchState heartbeat(UUID roomId, UUID userId);
    /** Returns queue state and caller-specific permissions/votes. */
    QueueResponse queue(UUID roomId, UUID userId);
    /** Adds or selects a deduplicated queue item according to policy. */
    QueueItem addQueue(UUID roomId, UUID userId, QueueAdd input);
    /** Reorders the member's complete personal queue. */
    void reorder(UUID roomId, UUID userId, List<UUID> queueIds);
    /** Adds a skip vote and advances/stops playback when required. */
    SkipVoteResult skipVote(UUID roomId, UUID userId);
      /** Replaces one member's single active room pick. */
    QueueResponse vote(UUID roomId, UUID userId, UUID queueId);
    /** Removes a queue item as host/co-host. */
    void removeQueue(UUID roomId, UUID userId, UUID queueId);
    /** Starts a requested or ranked next item as host. */
    WatchState playNext(UUID roomId, UUID userId, UUID requestedQueueId);
    /** Updates queue mode and transition time as host/co-host. */
    void updateSettings(UUID roomId, UUID userId, WatchSettings input);
    /** Changes one member's video-add permission as host/co-host. */
    void updateVideoPermission(UUID roomId, UUID userId, UUID targetUserId, Map<String, Boolean> input);
    /** Requests room-owner approval before the caller may receive the video surface. */
    void requestVideoAccess(UUID roomId, UUID userId);
    /** Grants or revokes a member's room video access as host/co-host. */
    void updateVideoAccess(UUID roomId, UUID userId, UUID targetUserId, Map<String, Boolean> input);
    /** Searches YouTube through the configured catalogue gateway. */
    SearchResponse searchYoutube(String query, String pageToken);
}
