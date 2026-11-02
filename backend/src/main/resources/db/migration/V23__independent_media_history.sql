ALTER TABLE user_media_history
    ADD COLUMN IF NOT EXISTS history_visible BOOLEAN NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_user_media_history_visible
    ON user_media_history(user_id,history_visible,last_watched_at DESC);
