ALTER TABLE rooms ADD COLUMN screen_share_policy VARCHAR(30) NOT NULL DEFAULT 'HOSTS_ONLY';
ALTER TABLE room_members ADD COLUMN can_share_screen BOOLEAN NOT NULL DEFAULT false;
UPDATE room_members SET can_share_screen = true WHERE role IN ('HOST', 'CO_HOST');
