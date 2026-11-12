
CREATE TABLE outlet_tables (
                               id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

                               outlet_id UUID NOT NULL
                                   REFERENCES merchant_outlets(id)
                                       ON DELETE RESTRICT,

                               code VARCHAR(32) NOT NULL,
                               name VARCHAR(120) NOT NULL,

                               zone VARCHAR(100),

                               qr_token UUID NOT NULL
                                                   DEFAULT gen_random_uuid(),

                               pos_table_id VARCHAR(150),

                               is_active BOOLEAN NOT NULL DEFAULT TRUE,

                               created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                               updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                               CONSTRAINT outlet_tables_code_check
                                   CHECK (
                                       LENGTH(BTRIM(code)) BETWEEN 1 AND 32
                                       ),

                               CONSTRAINT outlet_tables_name_check
                                   CHECK (
                                       LENGTH(BTRIM(name)) BETWEEN 2 AND 120
                                       ),

                               CONSTRAINT outlet_tables_qr_unique
                                   UNIQUE (qr_token)
);

CREATE UNIQUE INDEX outlet_tables_code_unique
    ON outlet_tables(outlet_id, LOWER(code));

CREATE UNIQUE INDEX outlet_tables_pos_unique
    ON outlet_tables(outlet_id, pos_table_id)
    WHERE pos_table_id IS NOT NULL;

CREATE INDEX outlet_tables_outlet_idx
    ON outlet_tables(outlet_id);
