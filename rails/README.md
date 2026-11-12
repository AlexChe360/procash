# ProCash Rails migration

Rails 8.1.3.1 / Ruby 4.0.6 / PostgreSQL 17. SSR, Turbo, Stimulus, Tailwind;
no SPA. Work in progress; this is not a completed production migration.

Source `/Users/alex/Documents/Development/rust/procash` is read-only.
No `.env`, live database data or secret keys were copied.

## Local start

Use the Ruby version in `.ruby-version` (for example `mise use ruby@4.0.6`).
Install native PostgreSQL and Argon2 runtime libraries (`libargon2-1` on Ubuntu;
`argon2` with Homebrew). `ARGON2_LIBRARY` may specify a library path.

```sh
bundle install
# Local development: settings are loaded automatically from .env.
# Use .env.example as a template; never commit .env.
# Start a separate PostgreSQL on 55439, or run the dedicated Compose database.
bin/rails db:create db:migrate
RAILS_ENV=test bin/rails db:migrate
bin/rails test
bin/rails procash:create_admin
bin/rails server -b 127.0.0.1 -p 3101
```

The current development run uses a dedicated temporary PostgreSQL cluster at
`/private/tmp/procash-rails-pg`, port **55439**, user `procash_rails`. It contains
only newly created Rails development/test databases. Trust authentication is
limited to this disposable local cluster; do not use it on a shared or production server.
The server runs at `http://127.0.0.1:3101` so it does not replace Rust on 3000.

Routes: `/`, `/login`, `/admin/login`, `/connect`, `/dashboard`,
`/demo/requests`, `/t/:uuid`. Merchant accounts are created by invitation only.
The demo merchant form `/demo/merchants/new` only validates input, like Rust.

## Email

Requests/invitations persist notification jobs in the original transactional
outbox tables. Run `bin/rails procash:mail_worker` as a separate process.
Active Job executes deliveries; PostgreSQL handles claiming (`SKIP LOCKED`),
leases (5 minutes for notifications, 2 for invitations), retries (8 attempts, quadratic delay capped at 60 minutes) and recovery.
Messages have a stable Message-ID. Delivery is at least once: SMTP can accept
mail immediately before a worker crash, so Message-ID is not an exactly-once guarantee.
SMTP is not sent in tests. Configure `SMTP_MODE`, host and recipients before
running a real worker. Never start it with real recipients just for UI testing.

## Compatibility

- Original SQLx schema, UUIDs, indexes, foreign keys and PL/pgSQL triggers retained.
- Argon2id PHC password hashes verified using libargon2, without password reset.
- Session hashes: SHA-256 of random 64-character hex tokens; 12-hour expiry.
  Rails uses its own encrypted cookie name, requiring a controlled login on cutover.
- Invitations: compatible UUID-byte HMAC-SHA256 format and SHA-256 lookup.
- iiko API secrets: compatible AES-256-GCM with connection-specific AAD and tag
  appended to ciphertext. Correct original master key is required for imported data.
- Bills use BigDecimal; JSON < 3 is pinned for Rails 8.1 compatibility.
- `/t/:uuid` tokens are unchanged. QR URLs use APP_ORIGIN, never an untrusted Host header.
- No payment processing. The guest button remains disabled.

## Status and deployment

See `docs/MIGRATION_AUDIT.md`, `docs/MIGRATION_PROGRESS.md`, and
`docs/DEPLOYMENT.md`. A fresh test schema is supported. Adoption of an existing
Rust database is not automatic: the bootstrap migration is for empty databases.

## Development .env

`dotenv-rails` loads `rails/.env` automatically in development for the web server
and the mail worker. Exported shell variables take precedence. Tests do not
load this development-only dependency. Production uses environment variables
or the deployment secret manager.

Fill SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM and SMTP_TO in `.env`,
then uncomment SMTP_MODE=starttls (587) or SMTP_MODE=tls (465). Restart the
Rails server and start `bin/rails procash:mail_worker` in a separate terminal.
This sends pending outbox messages as well as new ones.

The local `.env` contains generated, independent invitation/encryption keys.
Keep them stable; they are shared by the web server and mail worker. They are
not the Rust production keys and cannot decrypt production data.
