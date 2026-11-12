CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    email TEXT NOT NULL,
    password_hash TEXT NOT NULL,

    display_name TEXT,

    platform_role VARCHAR(20) NOT NULL DEFAULT 'user',

    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    email_verified_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT users_email_not_empty
        CHECK ( LENGTH(BTRIM(email)) BETWEEN 4 AND 254),

    CONSTRAINT users_platform_role_check
        CHECK ( platform_role IN ('user', 'admin'))
);

CREATE UNIQUE INDEX users_email_unique
    ON users (LOWER(email));
