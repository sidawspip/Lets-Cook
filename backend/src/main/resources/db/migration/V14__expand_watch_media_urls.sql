ALTER TABLE room_watch_state
    ALTER COLUMN media_id TYPE VARCHAR(2000);

ALTER TABLE room_watch_queue
    ALTER COLUMN media_id TYPE VARCHAR(2000);
