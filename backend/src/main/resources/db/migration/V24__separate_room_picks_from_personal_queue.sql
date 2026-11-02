ALTER TABLE room_watch_queue
  ADD COLUMN IF NOT EXISTS personal_queue_item BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_watch_queue_room_picks
  ON room_watch_queue(room_id, status, personal_queue_item, created_at);
