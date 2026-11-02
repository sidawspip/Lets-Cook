ALTER TABLE room_session_messages
    ADD COLUMN message_type VARCHAR(24) NOT NULL DEFAULT 'MESSAGE',
    ADD COLUMN reply_to_message_id UUID REFERENCES room_session_messages(id) ON DELETE SET NULL,
    ADD COLUMN media_provider VARCHAR(40),
    ADD COLUMN media_id VARCHAR(2000),
    ADD COLUMN media_title VARCHAR(500);

CREATE INDEX idx_room_session_messages_reply
    ON room_session_messages(reply_to_message_id)
    WHERE reply_to_message_id IS NOT NULL;

CREATE TABLE room_message_reactions (
    message_id UUID NOT NULL REFERENCES room_session_messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    reaction VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, user_id, reaction)
);

CREATE INDEX idx_room_message_reactions_message
    ON room_message_reactions(message_id, created_at);
