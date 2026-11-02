CREATE INDEX idx_direct_messages_unread_recipient
    ON direct_messages (recipient_id, sender_id, created_at DESC)
    WHERE read_at IS NULL;

CREATE INDEX idx_friendships_pending_addressee
    ON friendships (addressee_id, created_at DESC)
    WHERE status = 'PENDING';
