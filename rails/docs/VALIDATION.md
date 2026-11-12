# Validation — 2026-11-12

Runtime: Ruby 4.0.6, Rails 8.1.3.1, PostgreSQL 17 (dedicated local cluster, 55439).

- `bin/rails zeitwerk:check`: passed.
- `RAILS_ENV=test bin/rails test`: 43 runs, 211 assertions, 0 failures, 0 errors, 1 skip.
- `bundle exec brakeman --no-pager -q`: 0 security warnings, 0 errors (Brakeman 8.0.6).
- All 21 original SQLx up migrations applied to empty dedicated databases.
- Source SHA-256 manifest: 137 files checked, 0 changes.
- Browser QA: published home and local copy, wide/narrow home, merchant login.
- Published CSS byte comparison: equal. HTML comparison: equal except intentional absolute PDF links.

Tests cover sessions/roles/CSRF/Origin/body limits, onboarding and one-time invitations,
outbox claims/retries, tenant access, Argon2id, authenticated encryption, money/
tips/guest rendering, QR output, POS resolution, iiko payloads, schema triggers,
activation freshness and three multi-thread PostgreSQL races.

Not verified: full original Rust suite parity, all administration UI flows,
external staging SMTP/iiko, old real password/ciphertext samples, existing
database adoption, Linux Docker build, production readiness and load behavior.
The manually enabled iiko test is deliberately skipped by default.
