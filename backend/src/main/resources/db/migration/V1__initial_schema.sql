CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE app_users (
    id UUID PRIMARY KEY,
    identity_subject VARCHAR(255) NOT NULL UNIQUE,
    username VARCHAR(80) NOT NULL UNIQUE,
    display_name VARCHAR(120) NOT NULL,
    email VARCHAR(255),
    avatar_url TEXT,
    bio VARCHAR(500),
    status VARCHAR(20) NOT NULL DEFAULT 'ONLINE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_app_users_username_trgm ON app_users USING gin (username gin_trgm_ops);
CREATE INDEX idx_app_users_display_name_trgm ON app_users USING gin (display_name gin_trgm_ops);

CREATE TABLE rooms (
    id UUID PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    description VARCHAR(500),
    owner_id UUID NOT NULL REFERENCES app_users(id),
    room_type VARCHAR(30) NOT NULL DEFAULT 'GENERAL',
    visibility VARCHAR(30) NOT NULL DEFAULT 'PRIVATE',
    access_policy VARCHAR(30) NOT NULL DEFAULT 'INVITE_OR_KEY',
    key_verifier VARCHAR(100),
    key_version INTEGER NOT NULL DEFAULT 1,
    approval_required BOOLEAN NOT NULL DEFAULT false,
    locked BOOLEAN NOT NULL DEFAULT false,
    max_members INTEGER NOT NULL DEFAULT 25 CHECK (max_members BETWEEN 2 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_rooms_name_trgm ON rooms USING gin (name gin_trgm_ops);

CREATE TABLE room_members (
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    role VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    invited_by UUID REFERENCES app_users(id),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (room_id, user_id)
);

CREATE TABLE room_invites (
    id UUID PRIMARY KEY,
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES app_users(id),
    code VARCHAR(80) NOT NULL UNIQUE,
    role_granted VARCHAR(30) NOT NULL DEFAULT 'MEMBER',
    expires_at TIMESTAMPTZ,
    max_uses INTEGER,
    used_count INTEGER NOT NULL DEFAULT 0,
    revoked BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

