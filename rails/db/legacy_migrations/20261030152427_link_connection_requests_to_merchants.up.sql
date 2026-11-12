ALTER TABLE connection_requests
    ADD COLUMN merchant_id UUID
        UNIQUE
        REFERENCES merchants(id)
            ON DELETE RESTRICT;

