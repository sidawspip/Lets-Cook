package com.letscook.platform.common;

import static com.letscook.platform.common.MediaLibraryModels.*;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * API for a user's personal media library.
 *
 * <p>Exposes recent watch history, likes, gallery entries, aggregate statistics, and
 * the sensitive-content preference. This controller only translates HTTP input and
 * delegates media-library policy to {@link MediaLibraryService}.</p>
 */
@RestController
@RequestMapping("/api/me/media")
public class MediaLibraryController {
    private final CurrentUserService users;
    private final MediaLibraryService mediaLibrary;

    public MediaLibraryController(CurrentUserService users, MediaLibraryService mediaLibrary) {
        this.users = users;
        this.mediaLibrary = mediaLibrary;
    }

    /** Returns history, gallery, likes, categories, social statistics, and content settings. */
    @GetMapping
    Dashboard dashboard(@AuthenticationPrincipal Jwt jwt) {
        return mediaLibrary.dashboard(users.synchronize(jwt).id());
    }

    /** Records or updates a watched media item and returns its accumulated library state. */
    @PostMapping("/history")
    MediaItem record(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody RecordMedia input) {
        return mediaLibrary.record(users.synchronize(jwt).id(), input);
    }

    /** Hides an item from history without changing its independent like or gallery flags. */
    @DeleteMapping("/history")
    void remove(@AuthenticationPrincipal Jwt jwt, @RequestParam String mediaId) {
        mediaLibrary.remove(users.synchronize(jwt).id(), mediaId);
    }

    /** Sets or clears the liked flag for an existing media-library item. */
    @PutMapping("/like")
    void like(@AuthenticationPrincipal Jwt jwt, @RequestBody MediaFlag flag) {
        mediaLibrary.setLiked(users.synchronize(jwt).id(), flag);
    }

    /** Sets or clears whether a media item is displayed in the user's profile gallery. */
    @PutMapping("/gallery")
    void gallery(@AuthenticationPrincipal Jwt jwt, @RequestBody MediaFlag flag) {
        mediaLibrary.setInGallery(users.synchronize(jwt).id(), flag);
    }

    /** Updates whether sensitive media is hidden from personal library projections. */
    @PatchMapping("/settings")
    void settings(@AuthenticationPrincipal Jwt jwt, @RequestBody Settings input) {
        mediaLibrary.updateSettings(users.synchronize(jwt).id(), input);
    }
}
