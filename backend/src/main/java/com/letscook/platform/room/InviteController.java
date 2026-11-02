package com.letscook.platform.room;

import com.letscook.platform.common.CurrentUserService;
import com.letscook.platform.room.RoomDtos.AcceptInviteRequest;
import com.letscook.platform.room.RoomDtos.AccessResult;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * API for accepting share-code room invitations.
 *
 * <p>The service validates expiry, revocation, usage limits, room capacity, optional room
 * key requirements, and approval mode before creating or activating membership.</p>
 */
@RestController
@RequestMapping("/api/invites")
public class InviteController {
    private final RoomService roomService;
    private final CurrentUserService currentUserService;

    public InviteController(RoomService roomService, CurrentUserService currentUserService) {
        this.roomService = roomService;
        this.currentUserService = currentUserService;
    }

    /** Accepts a valid share-code invite and returns ACTIVE or PENDING membership state. */
    @PostMapping("/{code}/accept")
    AccessResult accept(@AuthenticationPrincipal Jwt jwt, @PathVariable String code,
                        @RequestBody(required = false) AcceptInviteRequest request) {
        return roomService.acceptInvite(currentUserService.synchronize(jwt), code,
                request == null ? null : request.accessKey());
    }
}
