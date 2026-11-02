package com.letscook.platform.media;

import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * API for resolving a public HTTPS webpage into a directly playable MP4 or HLS source.
 *
 * <p>This endpoint does not bypass authentication or DRM. Network safety checks, redirect
 * limits, content inspection, and source extraction are delegated to the resolver service.</p>
 */
@RestController
@RequestMapping("/api/media")
public class WebMediaResolverController {
    private final WebMediaResolverService resolver;
    public WebMediaResolverController(WebMediaResolverService resolver){this.resolver=resolver;}
    /** Resolves one public HTTPS page URL to normalized direct-media metadata or returns 422. */
    @PostMapping("/resolve-web")
    WebMediaResolverRepository.ResolvedWebMedia resolve(@Valid @RequestBody WebMediaResolverRepository.ResolveWebMediaRequest request){return resolver.resolve(request);}
}
