package com.letscook.platform.common;

import jakarta.validation.constraints.Size;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.UUID;

final class ProfileModels {
    private ProfileModels() {}

    record UpdateProfile(@Size(max=120) String displayName,@Size(max=500) String bio) {}
    record ProfileView(UUID id,String username,String displayName,String email,String bio,String avatarUrl) {}
    record Preferences(boolean hideSensitiveContent,boolean hideLocation,boolean restrictInvites,boolean floatingVideo,
                       boolean muteOtherAudio,boolean hapticFeedback,boolean autoTranslate,
                       @Size(max=16) String preferredLanguage,@Size(max=16) String quickReaction) {}
    record PreferencesPatch(Boolean hideSensitiveContent,Boolean hideLocation,Boolean restrictInvites,Boolean floatingVideo,
                            Boolean muteOtherAudio,Boolean hapticFeedback,Boolean autoTranslate,
                            @Size(max=16) String preferredLanguage,@Size(max=16) String quickReaction) {}
    record Connection(@Size(max=40) String provider,@Size(max=2000) String url) {}
    record ProfileVisibility(String bio,String gallery,String activity,String stats,String friends,String interests,String connections) {}
    record ProfileDashboard(ProfileView profile,Preferences preferences,ProfileVisibility visibility,List<Connection> connections,List<String> interests) {}
    record StoredFile(Path path,String contentType) {}
}
