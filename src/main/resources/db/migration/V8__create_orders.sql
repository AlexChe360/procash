CREATE TABLE restaurant_orders
(
    id                  UUID PRIMARY KEY,
    restaurant_id       UUID                     NOT NULL,
    restaurant_table_id UUID                     NOT NULL,

    external_order_id   VARCHAR(255),

    order_number        VARCHAR(100)             NOT NULL,

    status              VARCHAR(30)              NOT NULL,

    total_amount        NUMERIC(19, 2)           NOT NULL DEFAULT 0,

    opened_at           TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL,

    CONSTRAINT restaurant_orders_restaurant_fk
        FOREIGN KEY (restaurant_id)
            REFERENCES restaurants (id)
            ON DELETE CASCADE,

    CONSTRAINT restaurant_orders_table_fk
        FOREIGN KEY (restaurant_table_id)
            REFERENCES restaurant_tables (id)
            ON DELETE CASCADE
);

CREATE INDEX restaurant_orders_restaurant_id_index
    ON restaurant_orders (restaurant_id);

CREATE INDEX restaurant_orders_table_id_index
    ON restaurant_orders (restaurant_table_id);

CREATE TABLE order_items
(
    id          UUID PRIMARY KEY,
    order_id    UUID                     NOT NULL,

    name        VARCHAR(255)             NOT NULL,

    quantity    NUMERIC(10, 3)           NOT NULL DEFAULT 1,

    unit_price  NUMERIC(19, 2)           NOT NULL,

    total_price NUMERIC(19, 2)           NOT NULL,

    created_at  TIMESTAMP WITH TIME ZONE NOT NULL,

    CONSTRAINT order_items_order_fk
        FOREIGN KEY (order_id)
            REFERENCES restaurant_orders (id)
            ON DELETE CASCADE
);

CREATE INDEX order_items_order_id_index
    ON order_items (order_id);