package com.letscook.platform.common;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.Map;

public final class MediaLibraryModels {
    private MediaLibraryModels() {}

    public record RecordMedia(
            @NotBlank @Size(max = 2000) String mediaId,
            @NotBlank @Size(max = 40) String provider,
            @NotBlank @Size(max = 500) String title,
            String thumbnailUrl,
            String sourceUrl,
            Boolean sensitive,
            Long watchSeconds,
            @Size(max = 40) String sourceType) {}

    public record MediaFlag(@NotBlank @Size(max = 2000) String mediaId, boolean enabled) {}

    public record Settings(boolean hideSensitiveContent) {}

    public record MediaItem(
            String mediaId,
            String provider,
            String title,
            String thumbnailUrl,
            String sourceUrl,
            boolean sensitive,
            int playCount,
            long watchSeconds,
            boolean liked,
            boolean inGallery,
            Instant lastWatchedAt,
            String sourceType) {}

    public record Dashboard(
            List<MediaItem> history,
            List<MediaItem> gallery,
            List<MediaItem> likes,
            Map<String, Long> categories,
            long watchTogetherSeconds,
            int friendCount,
            boolean hideSensitiveContent) {}
}
