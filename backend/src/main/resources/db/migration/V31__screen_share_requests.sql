ALTER TABLE room_members ADD COLUMN screen_share_requested BOOLEAN NOT NULL DEFAULT false;

-- Sharing now requires an explicit grant from the host, including for co-hosts.
UPDATE room_members SET can_share_screen = false WHERE role <> 'HOST';
UPDATE room_members SET can_add_videos = false WHERE role <> 'HOST';
