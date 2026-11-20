ALTER TABLE user_media_history ADD COLUMN source_type varchar(40);

UPDATE user_media_history SET source_type = provider
WHERE provider IN ('YOUTUBE', 'DIRECT_MP4', 'DIRECT_HLS');
