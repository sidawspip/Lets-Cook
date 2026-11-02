ALTER TABLE app_users
    ADD COLUMN IF NOT EXISTS hide_location BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS restrict_invites BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS floating_video BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS mute_other_audio BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS haptic_feedback BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS auto_translate BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(16) NOT NULL DEFAULT 'en',
    ADD COLUMN IF NOT EXISTS quick_reaction VARCHAR(32) NOT NULL DEFAULT '❤️';

CREATE TABLE user_profile_connections (
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    provider VARCHAR(40) NOT NULL,
    url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, provider)
);

CREATE TABLE user_profile_interests (
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    interest VARCHAR(60) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, interest)
);

CREATE INDEX idx_profile_connections_user ON user_profile_connections(user_id);
CREATE INDEX idx_profile_interests_user ON user_profile_interests(user_id);
