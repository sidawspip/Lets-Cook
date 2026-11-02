package com.letscook.platform.common;

import static com.letscook.platform.common.MediaLibraryModels.*;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Business logic for the personal media library.
 *
 * <p>Normalizes recorded media, applies sensitive-content visibility rules, updates flags,
 * and composes the user's media dashboard from repository projections.</p>
 */
@Service
public class MediaLibraryServiceImpl implements MediaLibraryService {
    private static final Pattern YOUTUBE_ID = Pattern.compile("[A-Za-z0-9_-]{11}");
    private static final Pattern XHAMSTER_MEDIA_PATH = Pattern.compile("/(\\d{3})/(\\d{3})/(\\d{3})/");
    private final MediaLibraryRepository repository;

    public MediaLibraryServiceImpl(MediaLibraryRepository repository) {
        this.repository = repository;
    }

    @Override
    @Transactional(readOnly = true)
    public Dashboard dashboard(UUID userId) {
        return new Dashboard(
                repository.history(userId, 60),
                repository.gallery(userId, 60),
                repository.likes(userId, 60),
                repository.categories(userId),
                repository.watchTogetherSeconds(userId),
                repository.friendCount(userId),
                repository.hideSensitiveContent(userId));
    }

    @Override
    @Transactional
    public MediaItem record(UUID userId, RecordMedia input) {
        String provider = input.provider().trim().toUpperCase(Locale.ROOT);
        String suppliedMediaId = input.mediaId().trim();
        String mediaId = canonicalMediaId(provider, suppliedMediaId, input.sourceUrl());
        boolean sensitive = input.sensitive() != null
                ? input.sensitive()
                : isSensitive(input.title() + " " + input.mediaId() + " " + input.sourceUrl());
        repository.normalizeAlias(userId, suppliedMediaId, mediaId);
        repository.upsert(
                userId,
                mediaId,
                provider,
                input.title().trim(),
                input.thumbnailUrl(),
                input.sourceUrl(),
                sensitive,
                Math.max(0, input.watchSeconds() == null ? 0 : input.watchSeconds()));
        return repository.item(userId, mediaId);
    }

    @Override
    @Transactional
    public void remove(UUID userId, String mediaId) {
        repository.remove(userId, mediaId);
    }

    @Override
    @Transactional
    public void setLiked(UUID userId, MediaFlag flag) {
        repository.setLiked(userId, flag.mediaId(), flag.enabled());
    }

    @Override
    @Transactional
    public void setInGallery(UUID userId, MediaFlag flag) {
        repository.setInGallery(userId, flag.mediaId(), flag.enabled());
    }

    @Override
    @Transactional
    public void updateSettings(UUID userId, Settings input) {
        repository.updateSensitiveSetting(userId, input.hideSensitiveContent());
    }

    private boolean isSensitive(String value) {
        String text = String.valueOf(value).toLowerCase(Locale.ROOT);
        return List.of(
                        "nsfw", "adult", "porn", "xxx", "xhamster", "xvideos",
                        "pornhub", "femdom", "nude", "sex")
                .stream()
                .anyMatch(text::contains);
    }

    private String canonicalMediaId(String provider, String mediaId, String sourceUrl) {
        if ("YOUTUBE".equals(provider)) {
            String extracted = youtubeId(mediaId);
            if (extracted == null) extracted = youtubeId(sourceUrl);
            return extracted == null ? mediaId : extracted;
        }
        if (provider.startsWith("DIRECT")) {
            String extracted = stableDirectId(mediaId);
            if (extracted == null) extracted = stableDirectId(sourceUrl);
            return extracted == null ? mediaId : extracted;
        }
        return mediaId;
    }

    private String stableDirectId(String value) {
        if (value == null) return null;
        try {
            URI uri = URI.create(value.trim());
            String host = uri.getHost();
            if (host == null) return null;
            String path = uri.getPath() == null ? "" : uri.getPath();
            if (host.toLowerCase(Locale.ROOT).contains("xhpingcdn.com")) {
                var matcher = XHAMSTER_MEDIA_PATH.matcher(path);
                if (matcher.find()) {
                    return "xh:" + matcher.group(1) + matcher.group(2) + matcher.group(3);
                }
            }
            return new URI(
                    uri.getScheme() == null ? "https" : uri.getScheme().toLowerCase(Locale.ROOT),
                    null,
                    host.toLowerCase(Locale.ROOT),
                    uri.getPort(),
                    path,
                    null,
                    null).toString();
        } catch (Exception ignored) {
            return null;
        }
    }

    private String youtubeId(String value) {
        if (value == null) return null;
        String candidate = value.trim();
        if (YOUTUBE_ID.matcher(candidate).matches()) return candidate;
        try {
            URI uri = URI.create(candidate);
            String host = uri.getHost();
            if (host == null) return null;
            host = host.toLowerCase(Locale.ROOT);
            String path = uri.getPath() == null ? "" : uri.getPath();
            if (host.equals("youtu.be") || host.endsWith(".youtu.be")) {
                return validYoutubeId(firstPathSegment(path));
            }
            if (!host.equals("youtube.com") && !host.endsWith(".youtube.com")) return null;
            String[] segments = path.split("/");
            if (segments.length > 2
                    && List.of("shorts", "embed", "live").contains(segments[1])) {
                return validYoutubeId(segments[2]);
            }
            String query = uri.getRawQuery();
            if (query != null) {
                for (String pair : query.split("&")) {
                    String[] parts = pair.split("=", 2);
                    if (parts.length == 2 && "v".equals(parts[0])) {
                        return validYoutubeId(URLDecoder.decode(parts[1], StandardCharsets.UTF_8));
                    }
                }
            }
        } catch (IllegalArgumentException ignored) {
            return null;
        }
        return null;
    }

    private String firstPathSegment(String path) {
        for (String segment : path.split("/")) {
            if (!segment.isBlank()) return segment;
        }
        return null;
    }

    private String validYoutubeId(String value) {
        return value != null && YOUTUBE_ID.matcher(value).matches() ? value : null;
    }
}
