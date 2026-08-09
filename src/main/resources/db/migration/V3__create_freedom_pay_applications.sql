CREATE TABLE freedom_pay_applications (
    id UUID PRIMARY KEY,

    restaurant_id UUID NOT NULL,

    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    current_step VARCHAR(30) NOT NULL DEFAULT 'COMPANY',

    organization_type VARCHAR(50),
    company_name VARCHAR(255),
    bin VARCHAR(20),

    director_name VARCHAR(255),
    director_iin VARCHAR(20),
    director_phone VARCHAR(30),
    director_email VARCHAR(255),

    legal_address VARCHAR(500),
    city VARCHAR(100),
    postal_code VARCHAR(20),

    iban VARCHAR(50),
    bank_name VARCHAR(255),
    bank_bic VARCHAR(30),

    website_url VARCHAR(500),
    business_category VARCHAR(150),
    business_description VARCHAR(1500),
    average_check NUMERIC(19, 2),
    expected_monthly_turnover NUMERIC(19, 2),

    partner_application_id VARCHAR(255),
    merchant_id VARCHAR(255),

    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,

    CONSTRAINT freedom_pay_applications_restaurant_fk
        FOREIGN KEY (restaurant_id)
        REFERENCES restaurants (id)
        ON DELETE CASCADE,

    CONSTRAINT freedom_pay_applications_restaurant_unique
        UNIQUE (restaurant_id)
);

CREATE INDEX freedom_pay_applications_status_index
    ON freedom_pay_applications (status);