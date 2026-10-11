ALTER TABLE room_watch_queue ADD COLUMN IF NOT EXISTS personal_position INTEGER NOT NULL DEFAULT 0;

WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY room_id, added_by ORDER BY created_at, id) - 1 AS position
  FROM room_watch_queue
)
UPDATE room_watch_queue q SET personal_position = ranked.position
FROM ranked WHERE ranked.id = q.id;

CREATE TABLE IF NOT EXISTS room_watch_skip_votes (
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  media_id VARCHAR(500) NOT NULL,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, media_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_watch_queue_personal_order
  ON room_watch_queue(room_id, added_by, status, personal_position, created_at);
