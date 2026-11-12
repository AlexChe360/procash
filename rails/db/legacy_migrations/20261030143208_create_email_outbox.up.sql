
CREATE TABLE email_outbox (
                              id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

                              connection_request_id UUID NOT NULL
                                  REFERENCES connection_requests(id)
                                      ON DELETE CASCADE,

                              attempts INTEGER NOT NULL DEFAULT 0,
                              next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                              locked_until TIMESTAMPTZ,
                              sent_at TIMESTAMPTZ,

                              last_error TEXT,
                              created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                              CONSTRAINT email_outbox_request_unique
                                  UNIQUE (connection_request_id),

                              CONSTRAINT email_outbox_attempts_check
                                  CHECK (attempts >= 0)
);

CREATE INDEX email_outbox_pending_idx
    ON email_outbox (next_attempt_at, created_at)
    WHERE sent_at IS NULL;

