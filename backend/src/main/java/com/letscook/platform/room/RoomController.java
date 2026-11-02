package com.letscook.platform.room;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.CurrentUserService;
import com.letscook.platform.room.RoomDtos.AccessResult;
import com.letscook.platform.room.RoomDtos.CreateInviteRequest;
import com.letscook.platform.room.RoomDtos.CreateRoomRequest;
import com.letscook.platform.room.RoomDtos.InviteCreated;
import com.letscook.platform.room.RoomDtos.RoomCreated;
import com.letscook.platform.room.RoomDtos.RoomSummary;
import com.letscook.platform.room.RoomDtos.UnlockRequest;
import com.letscook.platform.room.RoomDtos.MediaToken;
import com.letscook.platform.room.RoomDtos.JoinRequest;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * API for room lifecycle, access, governance, invitations, and LiveKit media tokens.
 *
 * <p>Room visibility and access policy are separate concerns: visibility controls discovery,
 * while {@link AccessPolicy} controls how membership is obtained. Ownership and manager
 * permissions are enforced by {@link RoomService}.</p>
 */
@RestController
@RequestMapping("/api/rooms")
public class RoomController {
    private final RoomService roomService;
    private final CurrentUserService currentUserService;

    public RoomController(RoomService roomService, CurrentUserService currentUserService) {
        this.roomService = roomService;
        this.currentUserService = currentUserService;
    }

    /** Lists active rooms in which the current user has active membership. */
    @GetMapping
    List<RoomSummary> rooms(@AuthenticationPrincipal Jwt jwt) {
        return roomService.listFor(user(jwt));
    }

    /** Discovers currently live rooms filtered by PUBLIC/FRIENDS visibility and bans. */
    @GetMapping("/public-live")
    List<RoomDtos.PublicRoom> publicLive(@AuthenticationPrincipal Jwt jwt) {
        return roomService.publicLive(user(jwt));
    }

    /** Creates a uniquely named room, grants HOST membership, and returns any one-time access key. */
    @PostMapping
    RoomCreated create(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody CreateRoomRequest request) {
        return roomService.create(user(jwt), request);
    }

    /** Requests membership using room visibility, access policy, optional key, capacity, and approval rules. */
    @PostMapping("/{roomId}/unlock")
    AccessResult unlock(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId,
                        @Valid @RequestBody UnlockRequest request) {
        return roomService.unlock(user(jwt), roomId, request.accessKey());
    }

    /** Creates a limited or expiring share-code invite; only hosts/co-hosts may call it. */
    @PostMapping("/{roomId}/invites")
    InviteCreated createInvite(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId,
                               @Valid @RequestBody CreateInviteRequest request) {
        return roomService.createInvite(user(jwt), roomId, request);
    }

    /** Issues a one-hour LiveKit token for an active member with role-aware publish grants. */
    @PostMapping("/{roomId}/media-token")
    MediaToken mediaToken(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return roomService.createMediaToken(user(jwt), roomId);
    }

    /** Permanently deletes a room; only its owner may call this endpoint. */
    @DeleteMapping("/{roomId}")
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        roomService.delete(user(jwt), roomId);
    }

    /** Lists pending membership requests; requires HOST or CO_HOST. */
    @GetMapping("/{roomId}/requests")
    List<JoinRequest> requests(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return roomService.joinRequests(user(jwt), roomId);
    }

    /** Approves or rejects one pending membership request; requires HOST or CO_HOST. */
    @PostMapping("/{roomId}/requests/{userId}/{decision}")
    void decideRequest(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId, @PathVariable UUID userId,
                       @PathVariable String decision) {
        if (!decision.equals("approve") && !decision.equals("reject"))
            throw new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.BAD_REQUEST, "Invalid decision");
        roomService.decideJoinRequest(user(jwt), roomId, userId, decision.equals("approve"));
    }

    /** Lists active room members and their roles/permissions; requires room-manager access. */
    @GetMapping("/{roomId}/members")
    List<RoomDtos.RoomMember> members(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return roomService.members(user(jwt), roomId);
    }

    /** Grants or revokes an individual non-host member's screen-sharing permission; owner only. */
    @PostMapping("/{roomId}/members/{userId}/screen-permission")
    void screenPermission(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId, @PathVariable UUID userId,
                          @RequestBody java.util.Map<String,Boolean> body) {
        roomService.setScreenPermission(user(jwt),roomId,userId,Boolean.TRUE.equals(body.get("allowed")));
    }

    /** Removes and bans a non-owner room member; owner only. */
    @DeleteMapping("/{roomId}/members/{userId}")
    void kickMember(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId, @PathVariable UUID userId) {
        roomService.kickMember(user(jwt), roomId, userId);
    }

    /** Directly invites a user, creates active membership, and sends a targeted ROOM_INVITE event. */
    @PostMapping("/{roomId}/invite-user/{userId}")
    void inviteUser(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@PathVariable UUID userId) {
        roomService.inviteUser(user(jwt),roomId,userId);
    }

    /** Applies TRANSFER, CO_HOST, or MEMBER leadership changes; owner only and max three co-hosts. */
    @PostMapping("/{roomId}/members/{userId}/leadership/{action}")
    void leadership(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@PathVariable UUID userId,@PathVariable String action) {
        roomService.setLeadership(user(jwt),roomId,userId,action.toUpperCase());
    }

    /** Partially updates room identity, visibility, entry policy, approval, and sharing policy; owner only. */
    @org.springframework.web.bind.annotation.PatchMapping("/{roomId}/settings")
    void settings(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId,
                  @Valid @RequestBody RoomDtos.UpdateRoomSettings request) {
        roomService.updateSettings(user(jwt),roomId,request);
    }

    private CurrentUser user(Jwt jwt) {
        return currentUserService.synchronize(jwt);
    }
}

