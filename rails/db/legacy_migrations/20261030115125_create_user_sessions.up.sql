CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(id)
        ON DELETE CASCADE,

    token_hash BYTEA NOT NULL UNIQUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,

    CONSTRAINT user_sessions_token_hash_length
               CHECK ( OCTET_LENGTH(token_hash) = 32 ),

    CONSTRAINT user_sessions_expiration_check
               CHECK ( expires_at > created_at )
);

CREATE INDEX user_sessions_user_idx
             ON user_sessions (user_id);

CREATE INDEX user_sessions_expires_idx
             ON user_sessions (expires_at);