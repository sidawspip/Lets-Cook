package com.letscook.platform.room;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

public final class RoomDtos {
    private RoomDtos() {
    }

    public record CreateRoomRequest(
            @NotBlank @Size(max = 120) String name,
            @Size(max = 500) String description,
            @NotNull AccessPolicy accessPolicy,
            boolean approvalRequired,
            @Min(2) @Max(500) int maxMembers,
            String visibility,
            Boolean ephemeral) {
    }

    public record RoomSummary(
            UUID id,
            String name,
            String ownerName,
            String description,
            AccessPolicy accessPolicy,
            RoomRole role,
            boolean locked,
            int memberCount,
            int pendingCount,
            String visibility,
            String screenSharePolicy,
            int viewerCount,
            String mediaTitle,
            String mediaId,
            String mediaProvider,
            String thumbnailUrl,
            double positionSeconds,
            Double durationSeconds) {
    }

    public record RoomCreated(RoomSummary room, String accessKey) {
    }

    public record UnlockRequest(String accessKey) {
    }

    public record AccessResult(UUID roomId, boolean accessGranted, RoomRole role, String status) {
    }

    public record CreateInviteRequest(
            @NotNull RoomRole role,
            Instant expiresAt,
            @Min(1) Integer maxUses) {
    }

    public record InviteCreated(String code, String path, Instant expiresAt, Integer maxUses) {
    }

    public record AcceptInviteRequest(String accessKey) {
    }

    public record MediaToken(String url, String token, String roomName, boolean canPublish) {
    }

    public record JoinRequest(UUID userId, String username, String displayName, String avatarUrl) {
    }

    public record UpdateRoomSettings(@Size(max = 120) String name, @Size(max = 500) String description,
                                     String visibility, AccessPolicy accessPolicy, Boolean approvalRequired,
                                     String screenSharePolicy) {
    }

    public record RoomMember(UUID userId, String username, String displayName, RoomRole role,
                             boolean canShareScreen, boolean canAddVideos, boolean canViewVideo,
                             boolean videoAccessRequested, boolean online) {
    }

    public record PublicRoom(UUID id,String name,String ownerName,String description,AccessPolicy accessPolicy,int viewerCount,
                             String mediaTitle,String mediaId,String mediaProvider,String thumbnailUrl,
                             double positionSeconds,Double durationSeconds,
                             java.util.List<String> viewerAvatars,boolean joined,RoomRole role) {}
}

