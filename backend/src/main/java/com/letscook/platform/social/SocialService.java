package com.letscook.platform.social;

import com.letscook.platform.common.CurrentUser;
import org.springframework.web.multipart.MultipartFile;
import java.util.List;
import java.util.UUID;

/**
 * Social-domain use cases for friendships, blocking, DMs, attachments, and notification delivery.
 */
interface SocialService {
    /** Lists accepted, unblocked friends with presence and shared-watch statistics. */
    List<SocialModels.Friend> friends(UUID userId);
    /** Lists pending friend requests received by the user. */
    List<SocialModels.FriendRequest> requests(UUID userId);
    /** Combines pending requests and unread-DM summaries newest first. */
    List<SocialModels.Notification> notifications(UUID userId);
    /** Creates a pending friend request after self/block/duplicate checks. */
    void request(UUID userId,UUID targetId);
    /** Removes any friendship or pending request between the two users. */
    void removeFriend(UUID userId,UUID targetId);
    /** Accepts or rejects a pending request owned by the user. */
    void decide(UUID userId,UUID requestId,String decision);
    /** Lists users blocked by the caller. */
    List<SocialModels.BlockedPerson> blocked(UUID userId);
    /** Blocks the target and tears down conflicting friendship/message state. */
    void block(UUID userId,UUID targetId);
    /** Removes the caller's block for the target. */
    void unblock(UUID userId,UUID targetId);
    /** Returns a friendship-gated conversation and marks incoming messages read. */
    List<SocialModels.Message> messages(UUID userId,UUID friendId);
    /** Persists a text DM and emits its targeted delivery event. */
    SocialModels.Message send(CurrentUser user,UUID friendId,SocialModels.SendMessage input);
    /** Validates/stores an attachment DM and emits its targeted delivery event. */
    SocialModels.Message sendAttachment(CurrentUser user,UUID friendId,MultipartFile file,String kind);
    /** Resolves a safe attachment filename to its stored file metadata. */
    SocialModels.StoredFile attachment(String fileName);
}
