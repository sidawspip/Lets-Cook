package com.letscook.platform.media;

/**
 * Resolves supported public webpages to direct media metadata without exposing fetch details.
 */
interface WebMediaResolverService {
    /** Validates/fetches a public page and returns direct playable media metadata. */
    WebMediaResolverRepository.ResolvedWebMedia resolve(WebMediaResolverRepository.ResolveWebMediaRequest request);
}
