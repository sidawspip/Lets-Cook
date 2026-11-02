package com.letscook.platform.common;

import static com.letscook.platform.common.MediaLibraryModels.*;

import java.util.UUID;

/**
 * Personal media-library use cases: history, likes, gallery, statistics, and content settings.
 */
public interface MediaLibraryService {
    /** Composes history, gallery, likes, categories, statistics, and settings. */
    Dashboard dashboard(UUID userId);
    /** Normalizes and upserts a watched item while accumulating play/watch statistics. */
    MediaItem record(UUID userId, RecordMedia input);
    /** Hides one item from history while preserving its like and gallery membership. */
    void remove(UUID userId, String mediaId);
    /** Sets the persistent liked flag for a media item. */
    void setLiked(UUID userId, MediaFlag flag);
    /** Sets the persistent profile-gallery flag for a media item. */
    void setInGallery(UUID userId, MediaFlag flag);
    /** Updates the user's sensitive-content filtering preference. */
    void updateSettings(UUID userId, Settings input);
}
