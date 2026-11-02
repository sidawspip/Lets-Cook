package com.letscook.platform.room;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class WatchModels {
    private WatchModels() {}

    public record WatchState(
            UUID roomId,
            String provider,
            String sourceType,
            String mediaId,
            String sourceUrl,
            String thumbnailUrl,
            String title,
            boolean playing,
            double positionSeconds,
            Double durationSeconds,
            double playbackRate,
            long revision,
            Instant updatedAt,
            Instant serverTime,
            Instant transitionUntil) {}

    public record WatchUpdate(
            @NotBlank String provider,
            String sourceType,
            @NotBlank @Size(max = 2000) String mediaId,
            @Size(max = 2000) String sourceUrl,
            @Size(max = 500) String title,
            boolean playing,
            double positionSeconds,
            Double durationSeconds,
            double playbackRate) {}

    public record Media(
            @NotBlank String provider,
            String sourceType,
            @NotBlank @Size(max = 2000) String mediaId,
            @Size(max = 2000) String sourceUrl,
            @Size(max = 500) String title,
            Double durationSeconds) {}

    public record WatchCommand(
            UUID commandId,
            long expectedRevision,
            @NotBlank String type,
            Media media,
            Double positionSeconds,
            Double playbackRate,
            Instant clientTime) {}

    public record WatchEvent(WatchState state, UUID commandId, UUID initiatedBy) {}

    public record YoutubeResult(String videoId, String title, String channelTitle, String thumbnailUrl) {}

    public record SearchResponse(
            boolean configured,
            List<YoutubeResult> results,
            String message,
            String nextPageToken,
            String previousPageToken) {}

    public record QueueAdd(
            @NotBlank String provider,
            @NotBlank @Size(max = 2000) String mediaId,
            @NotBlank @Size(max = 500) String title,
            @Size(max = 1000) String thumbnailUrl,
            Boolean personalQueueItem) {}

    public record WatchSettings(String mode, int transitionSeconds) {}
    public record NextRequest(UUID queueId) {}
    public record ReorderRequest(List<UUID> queueIds) {}
    public record SkipVoteResult(boolean skipped, int votes, int required, WatchState state) {}
}
