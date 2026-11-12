

CREATE TABLE merchant_memberships (
                                      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

                                      merchant_id UUID NOT NULL
                                          REFERENCES merchants(id)
                                              ON DELETE RESTRICT,

                                      user_id UUID NOT NULL
                                          REFERENCES users(id)
                                              ON DELETE RESTRICT,

                                      role VARCHAR(20) NOT NULL DEFAULT 'staff',

                                      is_active BOOLEAN NOT NULL DEFAULT TRUE,

                                      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                                      CONSTRAINT merchant_memberships_unique
                                          UNIQUE (merchant_id, user_id),

                                      CONSTRAINT merchant_memberships_role_check
                                          CHECK (
                                              role IN (
                                                       'owner',
                                                       'manager',
                                                       'cashier',
                                                       'staff'
                                                  )
                                              )
);

CREATE INDEX merchant_memberships_user_idx
    ON merchant_memberships(user_id);
