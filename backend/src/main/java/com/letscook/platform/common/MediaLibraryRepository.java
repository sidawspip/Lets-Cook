package com.letscook.platform.common;

import static com.letscook.platform.common.MediaLibraryModels.*;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Persistence and projections for personal media history, likes, gallery entries, and statistics.
 */
@Repository
public class MediaLibraryRepository {
    private final JdbcClient jdbc;

    public MediaLibraryRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public List<MediaItem> history(UUID userId, int limit) {
        return items(userId, "AND history_visible=true", limit);
    }

    public List<MediaItem> gallery(UUID userId, int limit) {
        return items(userId, "AND in_gallery=true", limit);
    }

    public List<MediaItem> likes(UUID userId, int limit) {
        return items(userId, "AND liked=true", limit);
    }

    public long watchTogetherSeconds(UUID userId) {
        return jdbc.sql("""
                        SELECT COALESCE(SUM(duration_seconds + CASE WHEN left_at IS NULL THEN COALESCE((
                          SELECT GREATEST(0,EXTRACT(EPOCH FROM LEAST(now(),p.last_seen_at+interval '45 seconds')-user_room_sessions.joined_at)::bigint)
                          FROM room_live_presence p WHERE p.user_id=user_room_sessions.user_id AND p.room_id=user_room_sessions.room_id
                        ),0) ELSE 0 END),0)
                        FROM user_room_sessions WHERE user_id=:user
                        """)
                .param("user", userId)
                .query(Long.class)
                .single();
    }

    public Map<String, Long> categories(UUID userId) {
        return jdbc.sql("""
                        SELECT CASE WHEN provider='YOUTUBE' THEN 'YouTube'
                          WHEN provider='CRUNCHYROLL' THEN 'Anime'
                          WHEN provider LIKE 'DIRECT%' THEN 'Direct' ELSE 'Web' END category,
                          SUM(play_count) views
                        FROM user_media_history WHERE user_id=:user AND history_visible=true
                        GROUP BY category ORDER BY views DESC
                        """)
                .param("user", userId)
                .query((rs, row) -> Map.entry(rs.getString("category"), rs.getLong("views")))
                .list()
                .stream()
                .collect(Collectors.toMap(
                        Map.Entry::getKey,
                        Map.Entry::getValue,
                        (left, right) -> left,
                        LinkedHashMap::new));
    }

    public boolean hideSensitiveContent(UUID userId) {
        return jdbc.sql("SELECT hide_sensitive_content FROM app_users WHERE id=:user")
                .param("user", userId)
                .query(Boolean.class)
                .single();
    }

    public int friendCount(UUID userId) {
        return jdbc.sql("""
                        SELECT COUNT(*) FROM friendships
                        WHERE status='ACCEPTED' AND (requester_id=:user OR addressee_id=:user)
                        """)
                .param("user", userId)
                .query(Integer.class)
                .single();
    }

    public void upsert(
            UUID userId,
            String mediaId,
            String provider,
            String title,
            String thumbnailUrl,
            String sourceUrl,
            boolean sensitive,
            long watchSeconds) {
        jdbc.sql("""
                        INSERT INTO user_media_history(
                          user_id,media_id,provider,title,thumbnail_url,source_url,sensitive,watch_seconds)
                        VALUES(:user,:media,:provider,:title,:thumbnail,:source,:sensitive,:seconds)
                        ON CONFLICT(user_id,media_id) DO UPDATE SET
                          provider=EXCLUDED.provider,title=EXCLUDED.title,
                          thumbnail_url=COALESCE(EXCLUDED.thumbnail_url,user_media_history.thumbnail_url),
                          source_url=COALESCE(EXCLUDED.source_url,user_media_history.source_url),
                          sensitive=EXCLUDED.sensitive,
                          history_visible=true,
                          play_count=user_media_history.play_count+1,
                          watch_seconds=user_media_history.watch_seconds+EXCLUDED.watch_seconds,
                          last_watched_at=now()
                        """)
                .param("user", userId)
                .param("media", mediaId)
                .param("provider", provider)
                .param("title", title)
                .param("thumbnail", thumbnailUrl)
                .param("source", sourceUrl)
                .param("sensitive", sensitive)
                .param("seconds", watchSeconds)
                .update();
    }

    public void normalizeAlias(UUID userId, String aliasMediaId, String canonicalMediaId) {
        if (aliasMediaId.equals(canonicalMediaId)) return;
        int merged = jdbc.sql("""
                        UPDATE user_media_history canonical SET
                          play_count=canonical.play_count+alias.play_count,
                          watch_seconds=canonical.watch_seconds+alias.watch_seconds,
                          liked=canonical.liked OR alias.liked,
                          in_gallery=canonical.in_gallery OR alias.in_gallery,
                          history_visible=canonical.history_visible OR alias.history_visible,
                          first_watched_at=LEAST(canonical.first_watched_at,alias.first_watched_at),
                          last_watched_at=GREATEST(canonical.last_watched_at,alias.last_watched_at),
                          thumbnail_url=COALESCE(canonical.thumbnail_url,alias.thumbnail_url),
                          source_url=COALESCE(canonical.source_url,alias.source_url)
                        FROM user_media_history alias
                        WHERE canonical.user_id=:user AND canonical.media_id=:canonical
                          AND alias.user_id=:user AND alias.media_id=:alias
                        """)
                .param("user", userId)
                .param("canonical", canonicalMediaId)
                .param("alias", aliasMediaId)
                .update();
        if (merged > 0) {
            jdbc.sql("DELETE FROM user_media_history WHERE user_id=:user AND media_id=:alias")
                    .param("user", userId)
                    .param("alias", aliasMediaId)
                    .update();
            return;
        }
        jdbc.sql("""
                        UPDATE user_media_history SET media_id=:canonical
                        WHERE user_id=:user AND media_id=:alias
                          AND NOT EXISTS (
                            SELECT 1 FROM user_media_history
                            WHERE user_id=:user AND media_id=:canonical)
                        """)
                .param("user", userId)
                .param("alias", aliasMediaId)
                .param("canonical", canonicalMediaId)
                .update();
    }

    public void remove(UUID userId, String mediaId) {
        jdbc.sql("UPDATE user_media_history SET history_visible=false WHERE user_id=:user AND media_id=:media")
                .param("user", userId)
                .param("media", mediaId)
                .update();
    }

    public void setLiked(UUID userId, String mediaId, boolean enabled) {
        setFlag(userId, mediaId, "liked", enabled);
    }

    public void setInGallery(UUID userId, String mediaId, boolean enabled) {
        setFlag(userId, mediaId, "in_gallery", enabled);
    }

    public void updateSensitiveSetting(UUID userId, boolean hide) {
        jdbc.sql("UPDATE app_users SET hide_sensitive_content=:hide,updated_at=now() WHERE id=:user")
                .param("hide", hide)
                .param("user", userId)
                .update();
    }

    public MediaItem item(UUID userId, String mediaId) {
        return jdbc.sql("SELECT * FROM user_media_history WHERE user_id=:user AND media_id=:media")
                .param("user", userId)
                .param("media", mediaId)
                .query((rs, row) -> map(rs))
                .single();
    }

    private List<MediaItem> items(UUID userId, String filter, int limit) {
        return jdbc.sql("SELECT * FROM user_media_history WHERE user_id=:user " + filter
                        + " ORDER BY last_watched_at DESC LIMIT " + limit)
                .param("user", userId)
                .query((rs, row) -> map(rs))
                .list();
    }

    private void setFlag(UUID userId, String mediaId, String column, boolean enabled) {
        jdbc.sql("UPDATE user_media_history SET " + column
                        + "=:enabled WHERE user_id=:user AND media_id=:media")
                .param("enabled", enabled)
                .param("user", userId)
                .param("media", mediaId)
                .update();
    }

    private MediaItem map(ResultSet rs) throws SQLException {
        return new MediaItem(
                rs.getString("media_id"),
                rs.getString("provider"),
                rs.getString("title"),
                rs.getString("thumbnail_url"),
                rs.getString("source_url"),
                rs.getBoolean("sensitive"),
                rs.getInt("play_count"),
                rs.getLong("watch_seconds"),
                rs.getBoolean("liked"),
                rs.getBoolean("in_gallery"),
                rs.getTimestamp("last_watched_at").toInstant());
    }
}
