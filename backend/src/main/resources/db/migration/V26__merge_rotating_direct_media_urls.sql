-- Some direct-video providers issue a different signed CDN URL on every replay.
-- Their stable numeric media path identifies the underlying item.
WITH aliases AS (
    SELECT user_id,
           media_id old_media_id,
           'xh:' || (regexp_match(media_id, '/([0-9]{3})/([0-9]{3})/([0-9]{3})/'))[1]
                 || (regexp_match(media_id, '/([0-9]{3})/([0-9]{3})/([0-9]{3})/'))[2]
                 || (regexp_match(media_id, '/([0-9]{3})/([0-9]{3})/([0-9]{3})/'))[3] canonical_id
    FROM user_media_history
    WHERE provider LIKE 'DIRECT%'
      AND media_id ~ '/[0-9]{3}/[0-9]{3}/[0-9]{3}/'
), merged AS (
    SELECT h.user_id,a.canonical_id,
           (array_agg(h.provider ORDER BY h.last_watched_at DESC))[1] provider,
           (array_agg(h.title ORDER BY h.last_watched_at DESC))[1] title,
           (array_agg(h.thumbnail_url ORDER BY h.last_watched_at DESC) FILTER (WHERE h.thumbnail_url IS NOT NULL))[1] thumbnail_url,
           (array_agg(h.source_url ORDER BY h.last_watched_at DESC) FILTER (WHERE h.source_url IS NOT NULL))[1] source_url,
           bool_or(h.sensitive) sensitive,
           sum(h.play_count)::integer play_count,
           sum(h.watch_seconds)::bigint watch_seconds,
           bool_or(h.liked) liked,
           bool_or(h.in_gallery) in_gallery,
           bool_or(h.history_visible) history_visible,
           min(h.first_watched_at) first_watched_at,
           max(h.last_watched_at) last_watched_at
    FROM aliases a JOIN user_media_history h
      ON h.user_id=a.user_id AND h.media_id=a.old_media_id
    GROUP BY h.user_id,a.canonical_id
), deleted AS (
    DELETE FROM user_media_history h USING aliases a
    WHERE h.user_id=a.user_id AND h.media_id=a.old_media_id
)
INSERT INTO user_media_history(
    user_id,media_id,provider,title,thumbnail_url,source_url,sensitive,
    play_count,watch_seconds,liked,in_gallery,history_visible,
    first_watched_at,last_watched_at)
SELECT user_id,canonical_id,provider,title,thumbnail_url,source_url,sensitive,
       play_count,watch_seconds,liked,in_gallery,history_visible,
       first_watched_at,last_watched_at
FROM merged
ON CONFLICT(user_id,media_id) DO UPDATE SET
    play_count=user_media_history.play_count+EXCLUDED.play_count,
    watch_seconds=user_media_history.watch_seconds+EXCLUDED.watch_seconds,
    liked=user_media_history.liked OR EXCLUDED.liked,
    in_gallery=user_media_history.in_gallery OR EXCLUDED.in_gallery,
    history_visible=user_media_history.history_visible OR EXCLUDED.history_visible,
    last_watched_at=GREATEST(user_media_history.last_watched_at,EXCLUDED.last_watched_at);
