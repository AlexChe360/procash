
CREATE TABLE outlet_tip_settings (
                                     outlet_id UUID PRIMARY KEY
                                         REFERENCES merchant_outlets(id)
                                             ON DELETE CASCADE,

                                     is_enabled BOOLEAN NOT NULL DEFAULT FALSE,

                                     percentages INTEGER[] NOT NULL
                                                                 DEFAULT ARRAY[5, 10, 15],

                                     allow_custom_amount BOOLEAN NOT NULL DEFAULT FALSE,

                                     created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                     updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
