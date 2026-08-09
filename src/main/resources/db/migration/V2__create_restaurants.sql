CREATE TABLE restaurants (
    id UUID PRIMARY KEY,

    owner_id UUID NOT NULL,

    name VARCHAR(150) NOT NULL,
    slug VARCHAR(150) NOT NULL,

    description VARCHAR(1000),
    phone VARCHAR(30),
    city VARCHAR(100),

    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    active BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,

    CONSTRAINT restaurants_owner_fk
            FOREIGN KEY (owner_id)
            REFERENCES users (id)
            ON DELETE CASCADE,

    CONSTRAINT restaurants_slug_unique UNIQUE (slug)
);

CREATE INDEX restaurants_owner_id_index ON restaurants (owner_id);
CREATE INDEX restaurants_status_index ON restaurants (status);