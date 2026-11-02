package com.letscook.platform.social;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.nio.file.Path;
import java.time.Instant;
import java.util.UUID;

final class SocialModels {
    private SocialModels() {}
    record Friend(UUID id,String username,String displayName,String avatarUrl,boolean online,long watchTogetherSeconds) {}
    record FriendRequest(UUID id,UUID userId,String username,String displayName) {}
    record BlockedPerson(UUID id,String username,String displayName,String avatarUrl,Instant blockedAt) {}
    record Notification(UUID id,String type,UUID userId,String username,String displayName,String body,int unreadCount,Instant createdAt) {}
    record PushEvent(String type,UUID senderId,String senderName,String body,UUID roomId) {}
    record Message(UUID id,UUID senderId,UUID recipientId,String body,String attachmentType,String attachmentUrl,String attachmentName,Instant createdAt) {}
    record SendMessage(@NotBlank @Size(max=2000) String body) {}
    record StoredFile(Path path,String contentType) {}
}
