-- A killed app or lost connection can miss the explicit leave request. Close those
-- sessions at their last heartbeat so offline time is never counted as watch time.
UPDATE user_room_sessions s
SET left_at = p.last_seen_at,
    duration_seconds = GREATEST(
        0,
        EXTRACT(EPOCH FROM p.last_seen_at - s.joined_at)::bigint
    )
FROM room_live_presence p
WHERE s.user_id = p.user_id
  AND s.room_id = p.room_id
  AND s.left_at IS NULL
  AND p.last_seen_at < now() - interval '45 seconds';

-- An orphaned open session without a presence record has no trustworthy live
-- interval. Close it at its join time rather than fabricating offline watch time.
UPDATE user_room_sessions s
SET left_at = s.joined_at,
    duration_seconds = 0
WHERE s.left_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM room_live_presence p
      WHERE p.user_id = s.user_id AND p.room_id = s.room_id
  );

DELETE FROM room_live_presence
WHERE last_seen_at < now() - interval '45 seconds';
