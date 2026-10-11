ALTER TABLE room_members ADD COLUMN can_add_videos BOOLEAN NOT NULL DEFAULT false;
UPDATE room_members SET can_add_videos = true WHERE role IN ('HOST', 'CO_HOST');

ALTER TABLE rooms ADD COLUMN watch_queue_mode VARCHAR(30) NOT NULL DEFAULT 'HOSTS_ONLY';
ALTER TABLE rooms ADD COLUMN watch_transition_seconds INTEGER NOT NULL DEFAULT 10;
ALTER TABLE room_watch_state ADD COLUMN transition_until TIMESTAMPTZ;

CREATE TABLE room_watch_queue (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
 provider VARCHAR(30) NOT NULL,
 media_id VARCHAR(500) NOT NULL,
 title VARCHAR(500) NOT NULL,
 thumbnail_url VARCHAR(1000),
 added_by UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
 status VARCHAR(20) NOT NULL DEFAULT 'QUEUED',
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_watch_queue_room ON room_watch_queue(room_id, status, created_at);

CREATE TABLE room_watch_votes (
 queue_id UUID NOT NULL REFERENCES room_watch_queue(id) ON DELETE CASCADE,
 user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(queue_id, user_id)
);

