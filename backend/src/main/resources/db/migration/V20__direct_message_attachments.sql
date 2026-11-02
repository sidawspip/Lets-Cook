ALTER TABLE direct_messages
    ADD COLUMN attachment_type VARCHAR(16),
    ADD COLUMN attachment_url VARCHAR(500),
    ADD COLUMN attachment_name VARCHAR(255);

ALTER TABLE direct_messages
    ADD CONSTRAINT direct_messages_attachment_type_check
    CHECK (attachment_type IS NULL OR attachment_type IN ('IMAGE', 'VIDEO'));
