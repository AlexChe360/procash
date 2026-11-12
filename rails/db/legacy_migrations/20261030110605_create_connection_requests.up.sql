CREATE TABLE connection_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    contact_name TEXT NOT NULL,
    contact_email TEXT NOT NULL,
    contact_phone TEXT NOT NULL,

    establishment_name TEXT NOT NULL,
    city TEXT NOT NULL,
    pos_system TEXT,
    comment TEXT,

    status VARCHAR(20) NOT NULL DEFAULT 'new',

    consent_accepted_at TIMESTAMPTZ NOT NULL,

    reviewed_by UUID REFERENCES users(id)
                ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT connection_requests_status_check
               CHECK ( status IN (
                    'new',
                    'in_review',
                    'approved',
                    'rejected'
               ))
);

CREATE INDEX connection_requests_status_created_at_idx
            ON connection_requests (status, created_at DESC);
