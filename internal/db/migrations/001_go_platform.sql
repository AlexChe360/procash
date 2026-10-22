-- Adopt the existing Laravel/Spring schema. No existing records or IDs are replaced.
CREATE TABLE IF NOT EXISTS users (
 id uuid PRIMARY KEY, email varchar(255) NOT NULL UNIQUE, password_hash varchar(255) NOT NULL,
 role varchar(30) NOT NULL DEFAULT 'USER', enabled boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS name varchar(255) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone varchar(30) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS temporary_password_expires_at timestamptz;
CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_unique ON users(lower(email));
CREATE TABLE IF NOT EXISTS restaurants (
 id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES users(id), name varchar(150) NOT NULL,
 slug varchar(150) NOT NULL UNIQUE, description varchar(1000), phone varchar(30), city varchar(100),
 status varchar(30) NOT NULL DEFAULT 'DRAFT', active boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS restaurants_owner_idx ON restaurants(owner_id);
CREATE TABLE IF NOT EXISTS freedom_pay_applications (
 id uuid PRIMARY KEY, restaurant_id uuid NOT NULL UNIQUE REFERENCES restaurants(id),
 status varchar(30) NOT NULL DEFAULT 'DRAFT', current_step varchar(30) NOT NULL DEFAULT 'COMPANY',
 organization_type varchar(50), company_name varchar(255), bin varchar(20), director_name varchar(255),
 director_iin varchar(20), director_phone varchar(30), director_email varchar(255), legal_address varchar(500),
 city varchar(100), postal_code varchar(20), iban varchar(50), bank_name varchar(255), bank_bic varchar(30),
 website_url varchar(500), business_category varchar(150), business_description varchar(1500),
 partner_application_id varchar(255), merchant_id varchar(255), average_check numeric(19,2),
 expected_monthly_turnover numeric(19,2), review_comment text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE freedom_pay_applications ADD COLUMN IF NOT EXISTS review_comment text;
CREATE TABLE IF NOT EXISTS restaurant_tables (
 id uuid PRIMARY KEY, restaurant_id uuid NOT NULL REFERENCES restaurants(id), table_number varchar(50) NOT NULL,
 display_name varchar(150), qr_token uuid NOT NULL UNIQUE, active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(restaurant_id,table_number)
);
CREATE TABLE IF NOT EXISTS restaurant_orders (
 id uuid PRIMARY KEY, restaurant_id uuid NOT NULL REFERENCES restaurants(id),
 restaurant_table_id uuid NOT NULL REFERENCES restaurant_tables(id), external_order_id varchar(255),
 order_number varchar(100) NOT NULL, status varchar(30) NOT NULL DEFAULT 'OPEN', total_amount numeric(19,2) NOT NULL DEFAULT 0,
 opened_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS order_items (
 id uuid PRIMARY KEY, order_id uuid NOT NULL REFERENCES restaurant_orders(id), name varchar(255) NOT NULL,
 quantity numeric(10,3) NOT NULL DEFAULT 1, unit_price numeric(19,2) NOT NULL, total_price numeric(19,2) NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS payments (
 id uuid PRIMARY KEY, order_id uuid NOT NULL REFERENCES restaurant_orders(id), restaurant_id uuid NOT NULL REFERENCES restaurants(id),
 amount numeric(19,2) NOT NULL, status varchar(30) NOT NULL, provider varchar(30) NOT NULL,
 external_payment_id varchar(255), paid_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payments_metrics_idx ON payments(restaurant_id,paid_at) WHERE status='PAID';
CREATE INDEX IF NOT EXISTS restaurant_orders_metrics_idx ON restaurant_orders(restaurant_id,opened_at);
CREATE TABLE IF NOT EXISTS connection_requests (
 id uuid PRIMARY KEY, contact_name varchar(255) NOT NULL, email varchar(255) NOT NULL,
 phone varchar(30) NOT NULL, restaurant_name varchar(150) NOT NULL, city varchar(100) NOT NULL,
 pos_system varchar(100) NOT NULL DEFAULT '', comment text NOT NULL DEFAULT '',
 status varchar(30) NOT NULL DEFAULT 'NEW' CHECK(status IN ('NEW','IN_REVIEW','APPROVED','REJECTED')),
 review_comment text NOT NULL DEFAULT '', user_id uuid REFERENCES users(id), restaurant_id uuid REFERENCES restaurants(id),
 reviewed_by uuid REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS connection_requests_open_unique ON connection_requests(lower(email),lower(restaurant_name)) WHERE status IN ('NEW','IN_REVIEW');
CREATE INDEX IF NOT EXISTS connection_requests_status_idx ON connection_requests(status,created_at DESC);
CREATE TABLE IF NOT EXISTS iiko_applications (
 id uuid PRIMARY KEY, restaurant_id uuid NOT NULL UNIQUE REFERENCES restaurants(id),
 status varchar(30) NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','READY_FOR_REVIEW','IN_PROGRESS','NEEDS_CHANGES','APPROVED','REJECTED')),
 data jsonb NOT NULL DEFAULT '{}', review_comment text NOT NULL DEFAULT '', partner_reference varchar(255) NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS sessions (
 token_hash text PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions(user_id);
CREATE INDEX IF NOT EXISTS sessions_expiry_idx ON sessions(expires_at);
CREATE TABLE IF NOT EXISTS rate_limits (
 key text PRIMARY KEY, window_start timestamptz NOT NULL DEFAULT now(), attempts int NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS mail_outbox (
 id uuid PRIMARY KEY, recipient varchar(255) NOT NULL, subject varchar(255) NOT NULL,
 payload bytea, status varchar(20) NOT NULL DEFAULT 'PENDING', attempts int NOT NULL DEFAULT 0,
 next_attempt_at timestamptz NOT NULL DEFAULT now(), lease_until timestamptz,
 last_error text NOT NULL DEFAULT '', created_at timestamptz NOT NULL DEFAULT now(), sent_at timestamptz
);
CREATE INDEX IF NOT EXISTS mail_outbox_due_idx ON mail_outbox(next_attempt_at) WHERE status IN ('PENDING','SENDING');
CREATE TABLE IF NOT EXISTS audit_events (
 id bigserial PRIMARY KEY, actor_id uuid REFERENCES users(id), action varchar(100) NOT NULL,
 entity_id uuid, created_at timestamptz NOT NULL DEFAULT now()
);

UPDATE freedom_pay_applications SET status=CASE status
 WHEN 'READY_TO_SUBMIT' THEN 'READY_FOR_REVIEW'
 WHEN 'SUBMITTED' THEN 'SUBMITTED_TO_FREEDOM'
 WHEN 'UNDER_REVIEW' THEN 'UNDER_FREEDOM_REVIEW'
 ELSE status END WHERE status IN ('READY_TO_SUBMIT','SUBMITTED','UNDER_REVIEW');
