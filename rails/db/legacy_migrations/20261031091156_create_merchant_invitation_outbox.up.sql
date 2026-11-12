
CREATE TABLE merchant_invitation_outbox (
                                            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

                                            merchant_invitation_id UUID NOT NULL UNIQUE
                                                REFERENCES merchant_invitations(id)
                                                    ON DELETE RESTRICT,

                                            attempts INTEGER NOT NULL DEFAULT 0,

                                            next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                            locked_until TIMESTAMPTZ,
                                            sent_at TIMESTAMPTZ,

                                            last_error TEXT,

                                            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                                            CONSTRAINT invitation_outbox_attempts_check
                                                CHECK (attempts >= 0)
);

CREATE INDEX merchant_invitation_outbox_pending_idx
    ON merchant_invitation_outbox(next_attempt_at, created_at)
    WHERE sent_at IS NULL;

