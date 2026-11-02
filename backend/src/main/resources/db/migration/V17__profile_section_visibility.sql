ALTER TABLE app_users
    ADD COLUMN IF NOT EXISTS bio_visibility VARCHAR(16) NOT NULL DEFAULT 'PUBLIC',
    ADD COLUMN IF NOT EXISTS gallery_visibility VARCHAR(16) NOT NULL DEFAULT 'PUBLIC',
    ADD COLUMN IF NOT EXISTS activity_visibility VARCHAR(16) NOT NULL DEFAULT 'FRIENDS',
    ADD COLUMN IF NOT EXISTS stats_visibility VARCHAR(16) NOT NULL DEFAULT 'PUBLIC',
    ADD COLUMN IF NOT EXISTS friends_visibility VARCHAR(16) NOT NULL DEFAULT 'FRIENDS',
    ADD COLUMN IF NOT EXISTS interests_visibility VARCHAR(16) NOT NULL DEFAULT 'PUBLIC',
    ADD COLUMN IF NOT EXISTS connections_visibility VARCHAR(16) NOT NULL DEFAULT 'PUBLIC';

ALTER TABLE app_users ADD CONSTRAINT chk_profile_visibility
CHECK (bio_visibility IN ('PUBLIC','FRIENDS','PRIVATE')
   AND gallery_visibility IN ('PUBLIC','FRIENDS','PRIVATE')
   AND activity_visibility IN ('PUBLIC','FRIENDS','PRIVATE')
   AND stats_visibility IN ('PUBLIC','FRIENDS','PRIVATE')
   AND friends_visibility IN ('PUBLIC','FRIENDS','PRIVATE')
   AND interests_visibility IN ('PUBLIC','FRIENDS','PRIVATE')
   AND connections_visibility IN ('PUBLIC','FRIENDS','PRIVATE'));
