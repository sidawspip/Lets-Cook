package com.letscook.platform.media;

import org.junit.jupiter.api.Test;

import java.net.URI;

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
}
