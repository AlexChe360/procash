CREATE TABLE restaurant_tables (
    id UUID PRIMARY KEY,

    restaurant_id UUID NOT NULL,

    table_number VARCHAR(50) NOT NULL,
    display_name VARCHAR(150),

    qr_token UUID NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,

    CONSTRAINT restaurant_tables_restaurant_fk
        FOREIGN KEY (restaurant_id)
        REFERENCES restaurants (id)
        ON DELETE CASCADE,

    CONSTRAINT restaurant_tables_restaurant_number_unique
        UNIQUE (restaurant_id, table_number),

    CONSTRAINT restaurant_tables_qr_token_unique
        UNIQUE (qr_token)
);

CREATE INDEX restaurant_tables_restaurant_id_index
    ON restaurant_tables (restaurant_id);

CREATE INDEX restaurant_tables_qr_token_index
    ON restaurant_tables (qr_token);