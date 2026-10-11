CREATE TABLE user_recent_room_people (
    viewer_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    seen_user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (viewer_id, seen_user_id)
);

CREATE INDEX idx_recent_room_people_viewer
    ON user_recent_room_people(viewer_id, last_seen_at DESC);
