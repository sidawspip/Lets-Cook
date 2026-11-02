-- A room may expose a media item only once while it is waiting in the queue.
-- Preserve the oldest card and move any selection from a duplicate onto it.
WITH duplicates AS (
  SELECT id,
         FIRST_VALUE(id) OVER (
           PARTITION BY room_id, provider, media_id
           ORDER BY created_at, id
         ) AS keeper_id,
         ROW_NUMBER() OVER (
           PARTITION BY room_id, provider, media_id
           ORDER BY created_at, id
         ) AS duplicate_number
  FROM room_watch_queue
  WHERE status = 'QUEUED'
)
UPDATE room_watch_votes votes
SET queue_id = duplicates.keeper_id
FROM duplicates
WHERE votes.queue_id = duplicates.id
  AND duplicates.duplicate_number > 1;

WITH duplicates AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY room_id, provider, media_id
           ORDER BY created_at, id
         ) AS duplicate_number
  FROM room_watch_queue
  WHERE status = 'QUEUED'
)
DELETE FROM room_watch_queue queue
USING duplicates
WHERE queue.id = duplicates.id
  AND duplicates.duplicate_number > 1;

CREATE UNIQUE INDEX uq_room_watch_queue_active_media
  ON room_watch_queue(room_id, provider, media_id)
  WHERE status = 'QUEUED';
