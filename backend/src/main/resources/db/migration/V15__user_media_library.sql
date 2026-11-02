ALTER TABLE app_users ADD COLUMN IF NOT EXISTS hide_sensitive_content BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE user_media_history (
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    media_id TEXT NOT NULL,
    provider VARCHAR(40) NOT NULL,
    title VARCHAR(500) NOT NULL,
    thumbnail_url TEXT,
    source_url TEXT,
    sensitive BOOLEAN NOT NULL DEFAULT false,
    play_count INTEGER NOT NULL DEFAULT 1,
    watch_seconds BIGINT NOT NULL DEFAULT 0,
    liked BOOLEAN NOT NULL DEFAULT false,
    in_gallery BOOLEAN NOT NULL DEFAULT false,
    first_watched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_watched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, media_id)
);
CREATE INDEX idx_user_media_history_recent ON user_media_history(user_id,last_watched_at DESC);
CREATE INDEX idx_user_media_history_gallery ON user_media_history(user_id,in_gallery,last_watched_at DESC);

CREATE TABLE user_room_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at TIMESTAMPTZ,
    duration_seconds BIGINT NOT NULL DEFAULT 0
);
CREATE INDEX idx_user_room_sessions_user ON user_room_sessions(user_id,joined_at DESC);
CREATE UNIQUE INDEX idx_user_room_sessions_open ON user_room_sessions(user_id,room_id) WHERE left_at IS NULL;
