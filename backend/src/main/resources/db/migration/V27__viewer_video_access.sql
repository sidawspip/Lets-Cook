ALTER TABLE room_members
    ADD COLUMN can_view_video BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN video_access_requested BOOLEAN NOT NULL DEFAULT false;

UPDATE room_members
SET can_view_video = true
WHERE role IN ('HOST', 'CO_HOST');
