
CREATE TABLE merchant_outlets (
                                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

                                  merchant_id UUID NOT NULL
                                      REFERENCES merchants(id)
                                          ON DELETE RESTRICT,

                                  name VARCHAR(150) NOT NULL,
                                  city VARCHAR(100) NOT NULL,
                                  address TEXT NOT NULL,

                                  pos_system VARCHAR(30),

                                  status VARCHAR(20) NOT NULL DEFAULT 'draft',

                                  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                                  CONSTRAINT merchant_outlets_name_check
                                      CHECK (LENGTH(BTRIM(name)) >= 2),

                                  CONSTRAINT merchant_outlets_city_check
                                      CHECK (LENGTH(BTRIM(city)) >= 2),

                                  CONSTRAINT merchant_outlets_address_check
                                      CHECK (LENGTH(BTRIM(address)) >= 3),

                                  CONSTRAINT merchant_outlets_pos_check
                                      CHECK (
                                          pos_system IS NULL
                                              OR pos_system IN (
                                                                'iiko',
                                                                'r_keeper',
                                                                'other'
                                              )
                                          ),

                                  CONSTRAINT merchant_outlets_status_check
                                      CHECK (
                                          status IN (
                                                     'draft',
                                                     'active',
                                                     'disabled'
                                              )
                                          )
);

CREATE INDEX merchant_outlets_merchant_idx
    ON merchant_outlets(merchant_id);
