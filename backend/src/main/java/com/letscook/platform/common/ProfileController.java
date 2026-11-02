package com.letscook.platform.common;

import jakarta.validation.Valid;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * API for the authenticated user's identity and profile.
 *
 * <p>Provides profile reads/updates, dashboard preferences, per-section visibility,
 * interests, external connections, public profile views, and avatar upload/download.
 * Authentication is synchronized through {@link CurrentUserService}; profile rules are
 * delegated to {@link ProfileService}.</p>
 */
@RestController
@RequestMapping("/api/me")
public class ProfileController {
    private final CurrentUserService users;
    private final ProfileService profiles;
    public ProfileController(CurrentUserService users,ProfileService profiles){this.users=users;this.profiles=profiles;}
    /** Returns and synchronizes the application user represented by the bearer JWT. */
    @GetMapping CurrentUser me(@AuthenticationPrincipal Jwt jwt){return users.synchronize(jwt);}

    /** Returns the authenticated user's editable profile fields. */
    @GetMapping("/profile") ProfileModels.ProfileView profile(@AuthenticationPrincipal Jwt jwt){return profiles.profile(users.synchronize(jwt).id());}

    /** Partially updates display name and bio, then returns the refreshed profile. */
    @PatchMapping("/profile") ProfileModels.ProfileView update(@AuthenticationPrincipal Jwt jwt,@Valid @RequestBody ProfileModels.UpdateProfile input){return profiles.update(users.synchronize(jwt).id(),input);}

    /** Returns profile, preferences, visibility, connections, and interests in one dashboard response. */
    @GetMapping("/profile/dashboard") ProfileModels.ProfileDashboard dashboard(@AuthenticationPrincipal Jwt jwt){return profiles.dashboard(users.synchronize(jwt).id());}

    /** Returns another user's profile with every section filtered by owner/friend/public visibility. */
    @GetMapping("/profile/view/{profileId}") Map<String,Object> publicProfile(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID profileId){return profiles.publicProfile(users.synchronize(jwt).id(),profileId);}

    /** Replaces per-section profile visibility using PUBLIC, FRIENDS, or PRIVATE values. */
    @PatchMapping("/profile/visibility") ProfileModels.ProfileVisibility visibility(@AuthenticationPrincipal Jwt jwt,@RequestBody ProfileModels.ProfileVisibility input){return profiles.updateVisibility(users.synchronize(jwt).id(),input);}

    /** Partially updates playback, translation, privacy, language, and quick-reaction preferences. */
    @PatchMapping("/profile/preferences") ProfileModels.Preferences preferences(@AuthenticationPrincipal Jwt jwt,@Valid @RequestBody ProfileModels.PreferencesPatch input){return profiles.updatePreferences(users.synchronize(jwt).id(),input);}

    /** Replaces all external profile connections; accepts at most ten validated HTTPS links. */
    @PutMapping("/profile/connections") void connections(@AuthenticationPrincipal Jwt jwt,@RequestBody List<ProfileModels.Connection> input){profiles.replaceConnections(users.synchronize(jwt).id(),input);}

    /** Replaces all profile interests after trimming, deduplicating, and applying size limits. */
    @PutMapping("/profile/interests") void interests(@AuthenticationPrincipal Jwt jwt,@RequestBody List<String> input){profiles.replaceInterests(users.synchronize(jwt).id(),input);}

    /** Uploads a validated JPG, PNG, WebP, or GIF avatar up to 5 MB and returns the profile. */
    @PostMapping(value="/avatar",consumes=MediaType.MULTIPART_FORM_DATA_VALUE) ProfileModels.ProfileView uploadAvatar(@AuthenticationPrincipal Jwt jwt,@RequestParam("file") MultipartFile file){return profiles.uploadAvatar(users.synchronize(jwt).id(),file);}

    /** Serves a validated local avatar file with no-cache response headers; bearer authentication is not required. */
    @GetMapping("/avatar/{fileName:.+}") ResponseEntity<FileSystemResource> avatar(@PathVariable String fileName){var file=profiles.avatar(fileName);return ResponseEntity.ok().cacheControl(CacheControl.noCache()).contentType(MediaType.parseMediaType(file.contentType())).body(new FileSystemResource(file.path()));}
}
