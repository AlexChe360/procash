CREATE TABLE merchants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    legal_name TEXT NOT NULL,
    bin_iin VARCHAR(12) NOT NULL UNIQUE,

    status VARCHAR(20) NOT NULL DEFAULT 'draft',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT merchants_bin_iin_format
        CHECK (bin_iin ~ '^[0-9]{12}$'),

    CONSTRAINT merchants_legal_name_not_empty
        CHECK (LENGTH(BTRIM(legal_name)) > 0),

    CONSTRAINT mercahnts_status_check
        CHECK (status IN ('draft', 'active', 'suspended'))
);
