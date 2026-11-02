package com.letscook.platform.social;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.CurrentUserService;
import jakarta.validation.Valid;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import java.time.Duration;
import java.util.List;
import java.util.UUID;

/**
 * Social API for friends, requests, blocks, direct messages, attachments, and notification summaries.
 *
 * <p>Direct messages are limited to accepted, unblocked friendships. Message history is
 * persistent, while live DM notification events are delivered to the target user's STOMP queue.</p>
 */
@RestController
@RequestMapping("/api/social")
public class SocialController {
    private final CurrentUserService users;private final SocialService social;
    public SocialController(CurrentUserService users,SocialService social){this.users=users;this.social=social;}
    /** Lists accepted, unblocked friends with online and shared-watch information. */
    @GetMapping("/friends") List<SocialModels.Friend> friends(@AuthenticationPrincipal Jwt jwt){return social.friends(users.synchronize(jwt).id());}

    /** Lists pending friend requests received by the authenticated user. */
    @GetMapping("/friend-requests") List<SocialModels.FriendRequest> requests(@AuthenticationPrincipal Jwt jwt){return social.requests(users.synchronize(jwt).id());}

    /** Returns pending friend-request and unread-DM summaries ordered newest first. */
    @GetMapping("/notifications") List<SocialModels.Notification> notifications(@AuthenticationPrincipal Jwt jwt){return social.notifications(users.synchronize(jwt).id());}

    /** Sends a friend request unless the target is self, blocked, or already has a relationship. */
    @PostMapping("/friend-requests/{userId}") void request(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID userId){social.request(users.synchronize(jwt).id(),userId);}

    /** Removes an accepted friendship or cancels a pending relationship. */
    @DeleteMapping("/friends/{userId}") void removeFriend(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID userId){social.removeFriend(users.synchronize(jwt).id(),userId);}

    /** Accepts or rejects a received pending request; decision must be accept or reject. */
    @PostMapping("/friend-requests/{requestId}/{decision}") void decide(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID requestId,@PathVariable String decision){social.decide(users.synchronize(jwt).id(),requestId,decision);}

    /** Lists up to 500 users blocked by the authenticated user. */
    @GetMapping("/blocked") List<SocialModels.BlockedPerson> blocked(@AuthenticationPrincipal Jwt jwt){return social.blocked(users.synchronize(jwt).id());}

    /** Blocks a user, removes any friendship, and marks incoming messages from that user read. */
    @PostMapping("/blocks/{userId}") void block(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID userId){social.block(users.synchronize(jwt).id(),userId);}

    /** Removes the authenticated user's block for the target user. */
    @DeleteMapping("/blocks/{userId}") void unblock(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID userId){social.unblock(users.synchronize(jwt).id(),userId);}

    /** Returns the latest 100 messages with a friend in chronological order and marks incoming messages read. */
    @GetMapping("/messages/{friendId}") List<SocialModels.Message> messages(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID friendId){return social.messages(users.synchronize(jwt).id(),friendId);}

    /** Stores a text DM for an accepted friend and emits a targeted real-time notification. */
    @PostMapping("/messages/{friendId}") SocialModels.Message send(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID friendId,@Valid @RequestBody SocialModels.SendMessage input){CurrentUser user=users.synchronize(jwt);return social.send(user,friendId,input);}

    /** Stores a validated IMAGE or VIDEO attachment DM and emits a targeted notification. */
    @PostMapping(value="/messages/{friendId}/attachments",consumes=MediaType.MULTIPART_FORM_DATA_VALUE) SocialModels.Message sendAttachment(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID friendId,@RequestParam("file") MultipartFile file,@RequestParam("kind") String kind){return social.sendAttachment(users.synchronize(jwt),friendId,file,kind);}

    /** Serves a validated local DM attachment with a seven-day cache policy. */
    @GetMapping("/attachments/{fileName:.+}") ResponseEntity<FileSystemResource> attachment(@PathVariable String fileName){var file=social.attachment(fileName);return ResponseEntity.ok().cacheControl(CacheControl.maxAge(Duration.ofDays(7))).contentType(MediaType.parseMediaType(file.contentType())).body(new FileSystemResource(file.path()));}
}
