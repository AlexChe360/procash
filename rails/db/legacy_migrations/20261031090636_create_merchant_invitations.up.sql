
CREATE TABLE merchant_invitations (
                                      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

                                      merchant_id UUID NOT NULL
                                          REFERENCES merchants(id)
                                              ON DELETE RESTRICT,

                                      connection_request_id UUID NOT NULL
                                          REFERENCES connection_requests(id)
                                              ON DELETE RESTRICT,

                                      email TEXT NOT NULL,

                                      token_hash BYTEA NOT NULL UNIQUE,

                                      created_by UUID NOT NULL
                                          REFERENCES users(id)
                                              ON DELETE RESTRICT,

                                      expires_at TIMESTAMPTZ NOT NULL,

                                      accepted_at TIMESTAMPTZ,
                                      revoked_at TIMESTAMPTZ,

                                      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                                      CONSTRAINT invitations_token_hash_length
                                          CHECK (OCTET_LENGTH(token_hash) = 32),

                                      CONSTRAINT invitations_email_not_empty
                                          CHECK (LENGTH(BTRIM(email)) > 3),

                                      CONSTRAINT invitations_expiration_check
                                          CHECK (expires_at > created_at),

                                      CONSTRAINT invitations_not_both_closed
                                          CHECK (
                                              accepted_at IS NULL
                                                  OR revoked_at IS NULL
                                              )
);

CREATE INDEX merchant_invitations_merchant_idx
    ON merchant_invitations(merchant_id);

CREATE INDEX merchant_invitations_pending_idx
    ON merchant_invitations(expires_at)
    WHERE accepted_at IS NULL
        AND revoked_at IS NULL;

CREATE UNIQUE INDEX merchant_invitations_one_pending_idx
    ON merchant_invitations(merchant_id)
    WHERE accepted_at IS NULL
        AND revoked_at IS NULL;
