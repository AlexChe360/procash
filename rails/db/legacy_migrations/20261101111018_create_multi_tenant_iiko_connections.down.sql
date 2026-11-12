
ALTER TABLE outlet_iiko_settings
    DROP CONSTRAINT outlet_iiko_settings_connection_merchant_fk;

ALTER TABLE outlet_iiko_settings
    DROP CONSTRAINT outlet_iiko_settings_outlet_merchant_fk;

ALTER TABLE outlet_iiko_settings
    DROP COLUMN connection_id;

ALTER TABLE outlet_iiko_settings
    DROP COLUMN merchant_id;

DROP TABLE iiko_connections;

ALTER TABLE merchant_outlets
    DROP CONSTRAINT merchant_outlets_id_merchant_unique;
