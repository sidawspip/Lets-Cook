package com.letscook.platform.common;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.letscook.platform.common.MediaLibraryModels.MediaItem;
import com.letscook.platform.common.MediaLibraryModels.RecordMedia;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class MediaLibraryServiceImplTest {
    @Test
    void webHistoryRetainsPageIdentityAndSignedPlaybackSource() {
        MediaLibraryRepository repository = mock(MediaLibraryRepository.class);
        MediaLibraryServiceImpl service = new MediaLibraryServiceImpl(repository);
        UUID userId = UUID.randomUUID();
        String page = "https://example.com/watch/42";
        String stream = "https://cdn.example.com/video.mp4?token=temporary";

        service.record(userId, new RecordMedia(
                page, "WEB", "Video", null, stream, false, 0L, "direct_mp4"));

        verify(repository).upsert(
                userId, page, "WEB", "Video", null, stream, false, 0, "DIRECT_MP4");
        verify(repository).item(userId, page);
    }

    @Test
    void repeatedYoutubeUrlUsesTheCanonicalVideoId() {
        MediaLibraryRepository repository = mock(MediaLibraryRepository.class);
        MediaLibraryServiceImpl service = new MediaLibraryServiceImpl(repository);
        UUID userId = UUID.randomUUID();
        String videoId = "dQw4w9WgXcQ";
        String supplied = "https://www.youtube.com/watch?v=" + videoId + "&feature=share";
        MediaItem expected = new MediaItem(
                videoId, "YOUTUBE", "Video", null, supplied,
                false, 2, 30, false, false, Instant.now(), null);
        when(repository.item(userId, videoId)).thenReturn(expected);

        service.record(userId, new RecordMedia(
                supplied, "youtube", "Video", null, supplied, false, 30L, null));

        verify(repository).normalizeAlias(userId, supplied, videoId);
        verify(repository).upsert(
                userId, videoId, "YOUTUBE", "Video", null, supplied, false, 30, "YOUTUBE");
        verify(repository).item(userId, videoId);
    }

    @Test
    void youtubeShortAndEmbedUrlsResolveToTheSameHistoryKey() {
        MediaLibraryRepository repository = mock(MediaLibraryRepository.class);
        MediaLibraryServiceImpl service = new MediaLibraryServiceImpl(repository);
        UUID userId = UUID.randomUUID();
        String videoId = "dQw4w9WgXcQ";
        MediaItem expected = new MediaItem(
                videoId, "YOUTUBE", "Video", null, null,
                false, 1, 0, false, false, Instant.now(), null);
        when(repository.item(userId, videoId)).thenReturn(expected);

        service.record(userId, new RecordMedia(
                "https://youtube.com/shorts/" + videoId,
                "YOUTUBE", "Video", null, null, false, 0L, null));
        service.record(userId, new RecordMedia(
                "https://youtube.com/embed/" + videoId,
                "YOUTUBE", "Video", null, null, false, 0L, null));

        verify(repository).normalizeAlias(
                userId, "https://youtube.com/shorts/" + videoId, videoId);
        verify(repository).normalizeAlias(
                userId, "https://youtube.com/embed/" + videoId, videoId);
    }

    @Test
    void rotatingDirectCdnUrlsResolveToTheSameUnderlyingVideo() {
        MediaLibraryRepository repository = mock(MediaLibraryRepository.class);
        MediaLibraryServiceImpl service = new MediaLibraryServiceImpl(repository);
        UUID userId = UUID.randomUUID();
        String signedUrl = "https://video5.xhpingcdn.com/key=temporary/027/867/843/480p.h264.mp4";
        String canonical = "xh:027867843";
        MediaItem expected = new MediaItem(
                canonical, "DIRECT_MP4", "Video", null, signedUrl,
                true, 2, 20, false, false, Instant.now(), null);
        when(repository.item(userId, canonical)).thenReturn(expected);

        service.record(userId, new RecordMedia(
                signedUrl, "DIRECT_MP4", "Video", null, signedUrl, true, 20L, null));

        verify(repository).normalizeAlias(userId, signedUrl, canonical);
        verify(repository).upsert(
                userId, canonical, "DIRECT_MP4", "Video", null, signedUrl, true, 20, "DIRECT_MP4");
    }
}
