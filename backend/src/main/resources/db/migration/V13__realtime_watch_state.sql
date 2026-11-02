ALTER TABLE room_watch_state
    ADD COLUMN source_type VARCHAR(30) NOT NULL DEFAULT 'YOUTUBE',
    ADD COLUMN source_url VARCHAR(2000),
    ADD COLUMN duration_seconds DOUBLE PRECISION,
    ADD COLUMN revision BIGINT NOT NULL DEFAULT 1;

CREATE TABLE room_watch_commands (
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    command_id UUID NOT NULL,
    state_revision BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (room_id, command_id)
);

CREATE INDEX room_watch_commands_created_at_idx ON room_watch_commands(created_at);
