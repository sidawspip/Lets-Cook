package com.letscook.platform.media;

import org.junit.jupiter.api.Test;

import java.net.URI;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class WebMediaResolverRepositoryTest {
    private final WebMediaResolverRepository repository = new WebMediaResolverRepository();

    @Test
    void explicitMobileRenditionBeatsMultiRenditionEndpoint() {
        URI explicit240 = URI.create("https://cdn.example/video_240.mp4");
        URI explicit360 = URI.create("https://cdn.example/video_360.mp4");
        URI multi = URI.create(
                "https://cdn.example/media=hls4/multi=256x144:144p:,426x240:240p:,854x480:480p:/video.mp4"
        );

        assertThat(repository.mobilePlaybackRank(explicit360))
                .isLessThan(repository.mobilePlaybackRank(explicit240));
        assertThat(repository.mobilePlaybackRank(explicit240))
                .isLessThan(repository.mobilePlaybackRank(multi));
    }

    @Test
    void rejectsUnresolvedProviderTemplateAsMedia() {
        URI template = URI.create(
                "https://cdn.example/media=hls4/multi=256x144:144p:,426x240:240p:,854x480:480p:/video/_TPL_.av1.mp4"
        );

        assertThat(repository.isUnresolvedTemplate(template)).isTrue();
        assertThat(repository.mobilePlaybackRank(template)).isEqualTo(100);
    }

    @Test
    void rejectsAdvertisingCdnOnXhamsterPage() {
        URI page = URI.create("https://xhamster19.com/videos/queen-marika-123");

        assertThat(repository.isAllowedMediaCandidate(
                page, URI.create("https://lumen.flirtify.com/campaign/480p.h264.mp4")))
                .isFalse();
        assertThat(repository.isAllowedMediaCandidate(
                page, URI.create("https://video5.xhpingcdn.com/027/867/843/480p.h264.mp4")))
                .isTrue();
    }

    @Test
    void doesNotAcceptUnrelatedVideoHostForXhamsterPage() {
        assertThat(repository.isAllowedMediaCandidate(
                URI.create("https://xhamster.com/videos/example"),
                URI.create("https://unrelated.example/video.mp4")))
                .isFalse();
    }

    @Test
    void acceptsObservedMediaCdnButRejectsLookalikeHost() {
        URI page = URI.create("https://xhamster.com/videos/example");
        assertThat(repository.isAllowedMediaCandidate(page,
                URI.create("https://video.xhmediacdn.com/video.mp4"))).isTrue();
        assertThat(repository.isAllowedMediaCandidate(page,
                URI.create("https://notxhpingcdn.com/video.mp4"))).isFalse();
    }

    @Test
    void buildsBackwardCompatibleNormalizedResourceWithOrderedSources() {
        URI page = URI.create("https://watch.example/videos/queen?view=party");
        URI primary = URI.create("https://cdn.example/queen_360p.mp4?expire=1793500000");
        URI fallback = URI.create("https://cdn.example/queen_480p.mp4?expire=1793600000");

        var resource = repository.normalizedResult(
                page,
                List.of(primary, fallback),
                "Queen",
                "Watch Example",
                "",
                "https://watch.example/poster.jpg");

        assertThat(resource.resourceId()).isEqualTo(page.toString());
        assertThat(resource.pageUrl()).isEqualTo(page.toString());
        assertThat(resource.sourceUrl()).isEqualTo(primary.toString());
        assertThat(resource.sourceType()).isEqualTo("DIRECT_MP4");
        assertThat(resource.streamExpiry()).isEqualTo(1793500000L);
        assertThat(resource.sources()).extracting(WebMediaResolverRepository.WebMediaSource::url)
                .containsExactly(primary.toString(), fallback.toString());
        assertThat(resource.sources().getFirst().quality()).isEqualTo("360p");
    }

    @Test
    void playbackHeadersAreOriginScopedAndNeverContainCookiesOrPagePath() {
        URI page = URI.create("https://watch.example/private/video?token=page-secret");
        URI media = URI.create("https://cdn.example/video_360p.mp4");

        var source = repository.webMediaSource(page, media, "video/mp4");

        assertThat(source.httpHeaders())
                .containsEntry("Referer", "https://watch.example/")
                .containsEntry("Origin", "https://watch.example")
                .containsKey("User-Agent")
                .doesNotContainKeys("Cookie", "Authorization");
        assertThat(source.httpHeaders().values())
                .noneMatch(value -> value.contains("page-secret") || value.contains("/private/video"));
    }

    @Test
    void directMediaDoesNotReceiveSyntheticPlaybackHeaders() {
        URI media = URI.create("https://cdn.example/video.mp4");

        assertThat(repository.webMediaSource(media, media, "video/mp4").httpHeaders()).isEmpty();
    }

    @Test
    void expiryInferenceAcceptsEpochSecondsAndMillisecondsOnly() {
        assertThat(repository.streamExpiry(
                URI.create("https://cdn.example/video.mp4?expire=1793500000")))
                .isEqualTo(1793500000L);
        assertThat(repository.streamExpiry(
                URI.create("https://cdn.example/video.mp4?expires=1793500000000")))
                .isEqualTo(1793500000L);
        assertThat(repository.streamExpiry(
                URI.create("https://cdn.example/video.mp4?exp=soon")))
                .isNull();
    }
}
