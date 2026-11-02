package com.letscook.platform.room;

import static com.letscook.platform.room.WatchModels.*;
import static com.letscook.platform.room.WatchQueueModels.*;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.CurrentUserService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;
import java.util.Map;
import java.util.UUID;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

/**
 * REST and STOMP API for synchronized playback and the shared room queue.
 *
 * <p>Hosts control playback, hosts/co-hosts manage queue policy, and active members may add
 * or vote according to room settings. Playback changes are revisioned and broadcast to
 * {@code /topic/rooms/{roomId}/watch}.</p>
 */
@RestController
@RequestMapping("/api")
public class WatchController {
    private final CurrentUserService users;
    private final WatchService watch;

    public WatchController(CurrentUserService users, WatchService watch) {
        this.users = users;
        this.watch = watch;
    }

    /** Returns the current extrapolated playback state; active room membership is required. */
    @GetMapping("/rooms/{roomId}/watch")
    WatchState state(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return watch.state(roomId, users.synchronize(jwt).id());
    }

    /** Replaces playback media/state, increments its revision, and broadcasts it; HOST only. */
    @PutMapping("/rooms/{roomId}/watch")
    WatchState update(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @Valid @RequestBody WatchUpdate input) {
        return watch.update(roomId, users.synchronize(jwt).id(), input);
    }

    /** Applies an idempotent LOAD/PLAY/PAUSE/SEEK/RATE/STOP/NEXT STOMP command; HOST only. */
    @MessageMapping("/rooms/{roomId}/watch/command")
    public void command(
            JwtAuthenticationToken authentication,
            @DestinationVariable UUID roomId,
            WatchCommand command) {
        CurrentUser user = users.synchronize(authentication.getToken());
        watch.command(roomId, user.id(), command);
    }

    /** Refreshes the authoritative playback timestamp and returns state; HOST only. */
    @PostMapping("/rooms/{roomId}/watch/heartbeat")
    WatchState heartbeat(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return watch.heartbeat(roomId, users.synchronize(jwt).id());
    }

    /** Returns ranked queue items, selected users, votes, permissions, settings, and skip status. */
    @GetMapping("/rooms/{roomId}/watch/queue")
    QueueResponse queue(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return watch.queue(roomId, users.synchronize(jwt).id());
    }

    /** Adds/selects media according to queue policy; duplicate media reuses the existing card. */
    @PostMapping("/rooms/{roomId}/watch/queue")
    QueueItem addQueue(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @Valid @RequestBody QueueAdd input) {
        return watch.addQueue(roomId, users.synchronize(jwt).id(), input);
    }

    /** Reorders the caller's complete personal queue; omitted or foreign IDs reject the request. */
    @PutMapping("/rooms/{roomId}/watch/queue/reorder")
    void reorder(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @RequestBody ReorderRequest request) {
        watch.reorder(roomId, users.synchronize(jwt).id(), request.queueIds());
    }

    /** Adds an idempotent skip vote and advances/stops playback once the threshold is reached. */
    @PostMapping("/rooms/{roomId}/watch/skip-vote")
    SkipVoteResult skipVote(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return watch.skipVote(roomId, users.synchronize(jwt).id());
    }

    /** Toggles the caller's pick and returns the freshly ranked single-choice queue. */
    @PostMapping("/rooms/{roomId}/watch/queue/{queueId}/vote")
    QueueResponse vote(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @PathVariable UUID queueId) {
        return watch.vote(roomId, users.synchronize(jwt).id(), queueId);
    }

    /** Removes a queue item; requires HOST or CO_HOST. */
    @DeleteMapping("/rooms/{roomId}/watch/queue/{queueId}")
    void removeQueue(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @PathVariable UUID queueId) {
        watch.removeQueue(roomId, users.synchronize(jwt).id(), queueId);
    }

    /** Starts the requested or highest-ranked playable queue item; HOST only. */
    @PostMapping("/rooms/{roomId}/watch/queue/next")
    WatchState playNext(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @RequestBody(required = false) NextRequest request) {
        return watch.playNext(
                roomId,
                users.synchronize(jwt).id(),
                request == null ? null : request.queueId());
    }

    /** Updates HOSTS_ONLY, PERMISSION, or VOTE queue mode and the clamped transition delay. */
    @PatchMapping("/rooms/{roomId}/watch/settings")
    void watchSettings(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @RequestBody WatchSettings input) {
        watch.updateSettings(roomId, users.synchronize(jwt).id(), input);
    }

    /** Grants or revokes a member's add-video permission; requires HOST or CO_HOST. */
    @PostMapping("/rooms/{roomId}/members/{userId}/video-permission")
    void videoPermission(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @PathVariable UUID userId,
            @RequestBody Map<String, Boolean> input) {
        watch.updateVideoPermission(roomId, users.synchronize(jwt).id(), userId, input);
    }

    /** Requests permission to reveal this room's video and controls to the caller. */
    @PostMapping("/rooms/{roomId}/watch/access-request")
    void requestVideoAccess(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        watch.requestVideoAccess(roomId, users.synchronize(jwt).id());
    }

    /** Grants or revokes one member's video access; requires HOST or CO_HOST. */
    @PostMapping("/rooms/{roomId}/members/{userId}/video-access")
    void videoAccess(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID roomId,
            @PathVariable UUID userId,
            @RequestBody Map<String, Boolean> input) {
        watch.updateVideoAccess(roomId, users.synchronize(jwt).id(), userId, input);
    }

    /** Searches the configured YouTube catalogue with an optional page token. */
    @GetMapping("/youtube/search")
    SearchResponse search(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam("q") @Size(min = 2, max = 100) String query,
            @RequestParam(value = "pageToken", required = false) @Size(max = 200) String pageToken) {
        users.synchronize(jwt);
        return watch.searchYoutube(query, pageToken);
    }
}
