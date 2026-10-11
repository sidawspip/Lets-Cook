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

@RestController
@RequestMapping("/api/rooms")
public class RoomController {
    private final RoomService roomService;
    private final CurrentUserService currentUserService;

    public RoomController(RoomService roomService, CurrentUserService currentUserService) {
        this.roomService = roomService;
        this.currentUserService = currentUserService;
    }

    @GetMapping
    List<RoomSummary> rooms(@AuthenticationPrincipal Jwt jwt) {
        return roomService.listFor(user(jwt));
    }

    @GetMapping("/public-live")
    List<RoomDtos.PublicRoom> publicLive(@AuthenticationPrincipal Jwt jwt) {
        return roomService.publicLive(user(jwt));
    }

    @PostMapping
    RoomCreated create(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody CreateRoomRequest request) {
        return roomService.create(user(jwt), request);
    }

    @PostMapping("/{roomId}/unlock")
    AccessResult unlock(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId,
                        @Valid @RequestBody UnlockRequest request) {
        return roomService.unlock(user(jwt), roomId, request.accessKey());
    }

    @PostMapping("/{roomId}/invites")
    InviteCreated createInvite(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId,
                               @Valid @RequestBody CreateInviteRequest request) {
        return roomService.createInvite(user(jwt), roomId, request);
    }

    @PostMapping("/{roomId}/media-token")
    MediaToken mediaToken(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return roomService.createMediaToken(user(jwt), roomId);
    }

    @DeleteMapping("/{roomId}")
    void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        roomService.delete(user(jwt), roomId);
    }

    @GetMapping("/{roomId}/requests")
    List<JoinRequest> requests(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return roomService.joinRequests(user(jwt), roomId);
    }

    @PostMapping("/{roomId}/requests/{userId}/{decision}")
    void decideRequest(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId, @PathVariable UUID userId,
                       @PathVariable String decision) {
        if (!decision.equals("approve") && !decision.equals("reject"))
            throw new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.BAD_REQUEST, "Invalid decision");
        roomService.decideJoinRequest(user(jwt), roomId, userId, decision.equals("approve"));
    }

    @GetMapping("/{roomId}/members")
    List<RoomDtos.RoomMember> members(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId) {
        return roomService.members(user(jwt), roomId);
    }

    @PostMapping("/{roomId}/members/{userId}/screen-permission")
    void screenPermission(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId, @PathVariable UUID userId,
                          @RequestBody java.util.Map<String,Boolean> body) {
        roomService.setScreenPermission(user(jwt),roomId,userId,Boolean.TRUE.equals(body.get("allowed")));
    }

    @DeleteMapping("/{roomId}/members/{userId}")
    void kickMember(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId, @PathVariable UUID userId) {
        roomService.kickMember(user(jwt), roomId, userId);
    }

    @PostMapping("/{roomId}/invite-user/{userId}")
    void inviteUser(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@PathVariable UUID userId) {
        roomService.inviteUser(user(jwt),roomId,userId);
    }

    @PostMapping("/{roomId}/members/{userId}/leadership/{action}")
    void leadership(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@PathVariable UUID userId,@PathVariable String action) {
        roomService.setLeadership(user(jwt),roomId,userId,action.toUpperCase());
    }

    @org.springframework.web.bind.annotation.PatchMapping("/{roomId}/settings")
    void settings(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID roomId,
                  @Valid @RequestBody RoomDtos.UpdateRoomSettings request) {
        roomService.updateSettings(user(jwt),roomId,request);
    }

    private CurrentUser user(Jwt jwt) {
        return currentUserService.synchronize(jwt);
    }
}

