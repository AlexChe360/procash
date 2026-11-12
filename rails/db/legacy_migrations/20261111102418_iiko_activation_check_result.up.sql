CREATE TABLE outlet_iiko_activation_checks (
                                               outlet_id UUID PRIMARY KEY
                                                   REFERENCES merchant_outlets(id)
                                                       ON DELETE CASCADE,

                                               checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                                               status VARCHAR(16) NOT NULL
                                                   CHECK (status IN ('passed', 'failed')),

                                               error_code VARCHAR(64),

                                               CONSTRAINT iiko_activation_check_result_valid
                                                   CHECK (
                                                       (status = 'passed' AND error_code IS NULL)
                                                           OR
                                                       (status = 'failed' AND error_code IS NOT NULL)
                                                       )
);
