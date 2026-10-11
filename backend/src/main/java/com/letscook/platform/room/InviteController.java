package com.letscook.platform.room;

import com.letscook.platform.common.CurrentUserService;
import com.letscook.platform.room.RoomDtos.AcceptInviteRequest;
import com.letscook.platform.room.RoomDtos.AccessResult;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/invites")
public class InviteController {
    private final RoomService roomService;
    private final CurrentUserService currentUserService;

    public InviteController(RoomService roomService, CurrentUserService currentUserService) {
        this.roomService = roomService;
        this.currentUserService = currentUserService;
    }

    @PostMapping("/{code}/accept")
    AccessResult accept(@AuthenticationPrincipal Jwt jwt, @PathVariable String code,
                        @RequestBody(required = false) AcceptInviteRequest request) {
        return roomService.acceptInvite(currentUserService.synchronize(jwt), code,
                request == null ? null : request.accessKey());
    }
}
