package com.letscook.platform.common;

import org.springframework.web.multipart.MultipartFile;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Profile use cases for the current user and privacy-filtered public profile views.
 */
interface ProfileService {
    /** Loads one user's stored profile fields. */
    ProfileModels.ProfileView profile(UUID userId);
    /** Applies editable profile changes and returns the refreshed profile. */
    ProfileModels.ProfileView update(UUID userId, ProfileModels.UpdateProfile input);
    /** Composes the authenticated user's complete profile-settings dashboard. */
    ProfileModels.ProfileDashboard dashboard(UUID userId);
    /** Builds a viewer-specific profile with privacy-hidden sections omitted. */
    Map<String,Object> publicProfile(UUID viewerId,UUID profileId);
    /** Validates and replaces all section visibility levels. */
    ProfileModels.ProfileVisibility updateVisibility(UUID userId,ProfileModels.ProfileVisibility input);
    /** Validates and partially updates user preferences. */
    ProfileModels.Preferences updatePreferences(UUID userId,ProfileModels.PreferencesPatch input);
    /** Atomically replaces validated external connections. */
    void replaceConnections(UUID userId,List<ProfileModels.Connection> input);
    /** Atomically replaces normalized, unique interests. */
    void replaceInterests(UUID userId,List<String> input);
    /** Validates/stores an avatar, removes the replaced local file, and returns the profile. */
    ProfileModels.ProfileView uploadAvatar(UUID userId,MultipartFile file);
    /** Resolves a safe stored avatar filename to its file and content type. */
    ProfileModels.StoredFile avatar(String fileName);
}
