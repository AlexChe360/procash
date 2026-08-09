CREATE TABLE payments
(
    id                  UUID PRIMARY KEY,

    order_id            UUID                     NOT NULL,
    restaurant_id       UUID                     NOT NULL,

    amount              NUMERIC(19, 2)           NOT NULL,

    status              VARCHAR(30)              NOT NULL,

    provider            VARCHAR(30)              NOT NULL,

    external_payment_id VARCHAR(255),

    created_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    paid_at             TIMESTAMP WITH TIME ZONE,

    CONSTRAINT payments_order_fk
        FOREIGN KEY (order_id)
            REFERENCES restaurant_orders (id)
            ON DELETE CASCADE,

    CONSTRAINT payments_restaurant_fk
        FOREIGN KEY (restaurant_id)
            REFERENCES restaurants (id)
            ON DELETE CASCADE
);

CREATE INDEX payments_order_id_index
    ON payments (order_id);

CREATE INDEX payments_restaurant_id_index
    ON payments (restaurant_id);