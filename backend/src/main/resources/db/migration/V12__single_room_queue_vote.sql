ALTER TABLE room_watch_votes ADD COLUMN IF NOT EXISTS room_id UUID;

UPDATE room_watch_votes votes
SET room_id = queue.room_id
FROM room_watch_queue queue
WHERE queue.id = votes.queue_id
  AND votes.room_id IS NULL;

WITH ranked AS (
  SELECT votes.queue_id,
         votes.user_id,
         ROW_NUMBER() OVER (
           PARTITION BY votes.room_id, votes.user_id
           ORDER BY CASE WHEN queue.status = 'QUEUED' THEN 0 ELSE 1 END,
                    votes.created_at DESC,
                    votes.queue_id
         ) AS selection_number
  FROM room_watch_votes votes
  JOIN room_watch_queue queue ON queue.id = votes.queue_id
)
DELETE FROM room_watch_votes votes
USING ranked
WHERE votes.queue_id = ranked.queue_id
  AND votes.user_id = ranked.user_id
  AND ranked.selection_number > 1;

ALTER TABLE room_watch_votes ALTER COLUMN room_id SET NOT NULL;
ALTER TABLE room_watch_votes
  ADD CONSTRAINT fk_room_watch_votes_room
  FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX uq_room_watch_votes_user_selection
  ON room_watch_votes(room_id, user_id);
