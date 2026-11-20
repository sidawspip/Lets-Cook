-- Room admission already enforces public/friend/invite, key and approval rules.
-- An admitted viewer should not need a second request just to watch the room.
ALTER TABLE room_members ALTER COLUMN can_view_video SET DEFAULT true;

UPDATE room_members
SET can_view_video = true, video_access_requested = false
WHERE status = 'ACTIVE';
