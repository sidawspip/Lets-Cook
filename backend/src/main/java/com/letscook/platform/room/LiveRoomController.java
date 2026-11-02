package com.letscook.platform.room;

import static com.letscook.platform.room.LiveRoomModels.*;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.CurrentUserService;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * API for the live room session lifecycle.
 *
 * <p>Handles join/heartbeat/leave presence, active participants, recently encountered users,
 * and the current user's session-scoped room timeline. Active room membership is required for
 * every operation.</p>
 */
@RestController
@RequestMapping("/api/rooms/{roomId}/live")
public class LiveRoomController {
    private final CurrentUserService users;
    private final LiveRoomService liveRoom;

    public LiveRoomController(CurrentUserService users, LiveRoomService liveRoom) {
        this.users = users;
        this.liveRoom = liveRoom;
    }

    /** Opens or refreshes live presence and starts a room-session record for an active member. */
    @PostMapping("/join")
    void join(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        liveRoom.join(roomId, users.synchronize(jwt));
    }

    /** Refreshes presence so the member remains visible and stale presences can be cleaned. */
    @PostMapping("/heartbeat")
    void heartbeat(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        liveRoom.heartbeat(roomId, users.synchronize(jwt).id());
    }

    /** Ends the user's session, removes presence, rebalances leadership, and handles empty-party cleanup. */
    @DeleteMapping("/leave")
    void leave(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        liveRoom.leave(roomId, users.synchronize(jwt).id());
    }

    /** Lists current participants and records unique recent encounters for the viewer. */
    @GetMapping("/participants")
    List<Participant> participants(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return liveRoom.participants(roomId, users.synchronize(jwt).id());
    }

    /** Lists up to the retained recent people encountered in shared rooms, with friendship state. */
    @GetMapping("/recent-people")
    List<RecentPerson> recentPeople(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return liveRoom.recentPeople(roomId, users.synchronize(jwt).id());
    }

    /** Returns messages plus join, leave, and video events from the caller's current room session. */
    @GetMapping("/messages")
    List<ChatMessage> messages(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return liveRoom.messages(roomId, users.synchronize(jwt).id());
    }

    /** Sends a message with optional reply context and delivers push/haptic events to active @mentions. */
    @PostMapping("/messages")
    ChatMessage send(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @Valid @RequestBody SendChat input) {
        CurrentUser user = users.synchronize(jwt);
        return liveRoom.send(roomId, user, input);
    }

    /** Shares a selected provider video into the room timeline without playing it. */
    @PostMapping("/messages/video")
    ChatMessage shareVideo(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @Valid @RequestBody ShareVideo input) {
        return liveRoom.shareVideo(roomId, users.synchronize(jwt), input);
    }

    /** Toggles one supported emoji reaction on a timeline message and returns its new reaction totals. */
    @PostMapping("/messages/{messageId}/reactions")
    ChatMessage react(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@PathVariable UUID messageId,
                      @Valid @RequestBody ReactionRequest input) {
        return liveRoom.toggleReaction(roomId,users.synchronize(jwt).id(),messageId,input.reaction());
    }
}
