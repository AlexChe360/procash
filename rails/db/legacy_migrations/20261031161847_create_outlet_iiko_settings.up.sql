
CREATE TABLE outlet_iiko_settings (
                                      outlet_id UUID PRIMARY KEY
                                          REFERENCES merchant_outlets(id)
                                              ON DELETE CASCADE,

                                      organization_id UUID,
                                      terminal_group_id UUID,

                                      is_enabled BOOLEAN NOT NULL DEFAULT FALSE,

                                      last_success_at TIMESTAMPTZ,
                                      last_error TEXT,

                                      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                                      CONSTRAINT iiko_enabled_requires_ids CHECK (
                                          NOT is_enabled
                                              OR (
                                              organization_id IS NOT NULL
                                                  AND terminal_group_id IS NOT NULL
                                              )
                                          )
);
