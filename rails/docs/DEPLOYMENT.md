# Deployment and rollback preparation

Status: TODO — configuration is a starting point, not a production certification.

1. Back up Rust database and preserve the Rust application, migrations, encryption
   key and invitation secret in the existing secret manager. Do not commit secrets.
2. Restore a database snapshot to a separate Rails staging PostgreSQL. Never run
   the bootstrap migration against an existing Rust schema. A reviewed adoption
   procedure and data-level comparison must be completed before doing that.
3. Use a separate DB role and database. Check UUIDs, row counts, constraints,
   triggers, passwords, QR tokens, and encrypted API-key interoperability.
4. Run the Rails test suite against a disposable test database. Then compare
   source and Rails behavior using the same synthetic restaurant/order fixtures.
5. Provision libargon2, Ruby, Puma and the outbox worker. Use explicit migrations
   as a release step; the Docker entrypoint intentionally does not migrate on boot.
6. Configure HTTPS through an independent Nginx staging hostname, with correct
   APP_ORIGIN, APP_HOST, SECRET_KEY_BASE and SMTP settings. Puma listens on 3101.
   Keep the current Rust upstream on 3000. Restrict the DB to the application host.
7. Keep production SMTP, iiko and payment operations out of automated tests.
   The manual read-only iiko test requires dedicated staging credentials and token.
8. Validate desktop/mobile UI, membership permissions, invitation reuse, stale
   activation races, outbox lease recovery, and error reporting. Measure bill
   latency and resource usage; no performance equivalence has been established.
9. Only after explicit approval: switch the reverse proxy upstream, ensure a single
   active mail-worker fleet, and require a new Rails session login.
10. Rollback: return the proxy upstream to Rust and stop Rails workers. Preserve
    a pre-cutover snapshot and reconcile any writes accepted during the cutover.
    Automatic rollback is not safe until bidirectional data compatibility is proven.

Unverified: container build on Linux, external SMTP/iiko, live data import,
full Rust/Rails end-to-end parity, production backups/restores and load behavior.
