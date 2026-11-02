package com.letscook.platform.room;

import static com.letscook.platform.room.LiveRoomModels.*;

import com.letscook.platform.common.CurrentUser;
import java.util.List;
import java.util.UUID;

/**
 * Live-session use cases for presence, participants, recent people, and the room timeline.
 */
public interface LiveRoomService {
    /** Establishes presence and starts a session for an active member. */
    void join(UUID roomId, CurrentUser user);
    /** Refreshes presence and removes stale participants. */
    void heartbeat(UUID roomId, UUID userId);
    /** Ends the session, removes presence, and performs leadership/empty-room cleanup. */
    void leave(UUID roomId, UUID userId);
    /** Returns active participants and records recent co-presence for the viewer. */
    List<Participant> participants(UUID roomId, UUID viewerId);
    /** Returns unique users recently encountered by the viewer. */
    List<RecentPerson> recentPeople(UUID roomId, UUID viewerId);
    /** Returns only the messages and system events created since this user's current join time. */
    List<ChatMessage> messages(UUID roomId, UUID userId);
    /** Persists a reply-capable message and emits targeted notifications for active @mentions. */
    ChatMessage send(UUID roomId, CurrentUser user, SendChat input);
    /** Shares a selected video card in chat without starting playback. */
    ChatMessage shareVideo(UUID roomId, CurrentUser user, ShareVideo input);
    /** Toggles one emoji reaction for the current user and returns the refreshed message. */
    ChatMessage toggleReaction(UUID roomId,UUID userId,UUID messageId,String reaction);
    /** Adds a video-played event to the active room timeline. */
    void recordVideoPlayed(UUID roomId,UUID actorId,String provider,String mediaId,String title);
}
