package com.letscook.platform.room;

import static com.letscook.platform.room.WatchModels.*;

import java.time.Duration;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;
import tools.jackson.databind.JsonNode;

/** External YouTube catalog gateway. */
/**
 * YouTube Data API gateway for paginated video search and normalized catalogue results.
 */
@Repository
public class YoutubeCatalogRepository {
    private final String apiKey;
    private final RestClient rest = RestClient.create();

    public YoutubeCatalogRepository(@Value("${app.youtube.api-key:}") String apiKey) {
        this.apiKey = apiKey;
    }

    public SearchResponse search(String query, String pageToken) {
        if (apiKey.isBlank()) {
            return new SearchResponse(
                    false,
                    List.of(),
                    "Set YOUTUBE_API_KEY to enable search. Paste a YouTube URL for now.",
                    null,
                    null);
        }
        UriComponentsBuilder builder = UriComponentsBuilder
                .fromUriString("https://www.googleapis.com/youtube/v3/search")
                .queryParam("part", "snippet")
                .queryParam("type", "video")
                .queryParam("videoEmbeddable", "true")
                .queryParam("safeSearch", "moderate")
                .queryParam("maxResults", 50)
                .queryParam("q", query.trim())
                .queryParam("key", apiKey.trim());
        if (pageToken != null && !pageToken.isBlank()) {
            builder.queryParam("pageToken", pageToken.trim());
        }
        JsonNode json = rest.get().uri(builder.build().encode().toUri()).retrieve().body(JsonNode.class);
        List<String> ids = new ArrayList<>();
        if (json != null) {
            for (JsonNode item : json.path("items")) {
                String id = item.path("id").path("videoId").asText();
                if (!id.isBlank()) ids.add(id);
            }
        }
        Set<String> normalVideos = normalVideoIds(ids);
        List<YoutubeResult> results = new ArrayList<>();
        if (json != null) {
            for (JsonNode item : json.path("items")) {
                String id = item.path("id").path("videoId").asText();
                JsonNode snippet = item.path("snippet");
                if (normalVideos.contains(id) && results.size() < 20) {
                    results.add(new YoutubeResult(
                            id,
                            snippet.path("title").asText(),
                            snippet.path("channelTitle").asText(),
                            snippet.path("thumbnails").path("medium").path("url").asText()));
                }
            }
        }
        String next = json == null ? "" : json.path("nextPageToken").asText("");
        String previous = json == null ? "" : json.path("prevPageToken").asText("");
        return new SearchResponse(
                true,
                results,
                null,
                next.isBlank() ? null : next,
                previous.isBlank() ? null : previous);
    }

    private Set<String> normalVideoIds(List<String> ids) {
        Set<String> normal = new HashSet<>();
        if (ids.isEmpty()) return normal;
        JsonNode details = rest.get().uri(UriComponentsBuilder
                        .fromUriString("https://www.googleapis.com/youtube/v3/videos")
                        .queryParam("part", "contentDetails,snippet")
                        .queryParam("id", String.join(",", ids))
                        .queryParam("key", apiKey.trim())
                        .build().encode().toUri())
                .retrieve().body(JsonNode.class);
        if (details == null) return normal;
        for (JsonNode video : details.path("items")) {
            String duration = video.path("contentDetails").path("duration").asText();
            JsonNode snippet = video.path("snippet");
            String metadata = (snippet.path("title").asText() + " "
                            + snippet.path("description").asText() + " "
                            + snippet.path("tags").toString())
                    .toLowerCase(Locale.ROOT);
            try {
                long seconds = Duration.parse(duration).toSeconds();
                boolean shortsSignal = metadata.matches(
                        "(?s).*(#shorts?\\b|youtube\\s+shorts?\\b|\\bshorts?\\s+video\\b|vertical\\s+video).*");
                if (seconds == 0 || seconds > 180 || !shortsSignal) {
                    normal.add(video.path("id").asText());
                }
            } catch (Exception ignored) {
                // Malformed duration is skipped instead of exposing an unverified short.
            }
        }
        return normal;
    }
}
