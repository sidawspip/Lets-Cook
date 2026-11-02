package com.letscook.platform.media;

import org.springframework.stereotype.Service;

/**
 * Business boundary for safe web-media resolution.
 * Provider-specific network access and extraction remain isolated in the repository gateway.
 */
@Service
class WebMediaResolverServiceImpl implements WebMediaResolverService {
    private final WebMediaResolverRepository repository;
    WebMediaResolverServiceImpl(WebMediaResolverRepository repository){this.repository=repository;}
    public WebMediaResolverRepository.ResolvedWebMedia resolve(WebMediaResolverRepository.ResolveWebMediaRequest request){return repository.resolve(request);}
}
