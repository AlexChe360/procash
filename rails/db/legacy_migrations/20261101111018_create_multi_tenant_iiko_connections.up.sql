
-- 1. Подключения iiko принадлежат компаниям.

CREATE TABLE iiko_connections (
                                  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

                                  merchant_id UUID NOT NULL
                                      REFERENCES merchants(id) ON DELETE RESTRICT,

                                  name VARCHAR(150) NOT NULL,

                                  api_key_ciphertext BYTEA NOT NULL,
                                  api_key_nonce BYTEA NOT NULL,
                                  encryption_key_version INTEGER NOT NULL DEFAULT 1,

                                  status VARCHAR(30) NOT NULL DEFAULT 'draft',

                                  last_verified_at TIMESTAMPTZ,
                                  last_error_code VARCHAR(64),

                                  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

                                  CONSTRAINT iiko_connections_ciphertext_check
                                      CHECK (OCTET_LENGTH(api_key_ciphertext) > 16),

                                  CONSTRAINT iiko_connections_nonce_check
                                      CHECK (OCTET_LENGTH(api_key_nonce) = 12),

                                  CONSTRAINT iiko_connections_version_check
                                      CHECK (encryption_key_version > 0),

                                  CONSTRAINT iiko_connections_status_check
                                      CHECK (status IN ('draft', 'verified', 'disabled')),

                                  CONSTRAINT iiko_connections_id_merchant_unique
                                      UNIQUE (id, merchant_id)
);

CREATE INDEX iiko_connections_merchant_idx
    ON iiko_connections(merchant_id);


-- 2. Подготавливаем составной внешний ключ
-- для проверки владельца торговой точки.

ALTER TABLE merchant_outlets
    ADD CONSTRAINT merchant_outlets_id_merchant_unique
        UNIQUE (id, merchant_id);


-- 3. Дополняем существующие настройки POS.

ALTER TABLE outlet_iiko_settings
    ADD COLUMN merchant_id UUID;

-- Существующие строки привязываем
-- к реальному владельцу ресторана.

UPDATE outlet_iiko_settings AS s
SET merchant_id = o.merchant_id
FROM merchant_outlets AS o
WHERE o.id = s.outlet_id;

ALTER TABLE outlet_iiko_settings
    ALTER COLUMN merchant_id SET NOT NULL;


-- 4. Проверяем связь ресторана и компании.

ALTER TABLE outlet_iiko_settings
    ADD CONSTRAINT outlet_iiko_settings_outlet_merchant_fk
        FOREIGN KEY (outlet_id, merchant_id)
            REFERENCES merchant_outlets(id, merchant_id)
            ON DELETE CASCADE;


-- 5. Одно подключение может использоваться
-- несколькими ресторанами одной компании.

ALTER TABLE outlet_iiko_settings
    ADD COLUMN connection_id UUID;

ALTER TABLE outlet_iiko_settings
    ADD CONSTRAINT outlet_iiko_settings_connection_merchant_fk
        FOREIGN KEY (connection_id, merchant_id)
            REFERENCES iiko_connections(id, merchant_id)
            ON DELETE RESTRICT;

CREATE INDEX outlet_iiko_settings_connection_idx
    ON outlet_iiko_settings(connection_id)
    WHERE connection_id IS NOT NULL;
