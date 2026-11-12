# Rails first deployment on the existing ProCash VPS

The user selected a **new, empty Rails database**. The existing Go database is
not imported, altered or removed. The existing HTTPS reverse proxy is retained.

`Deploy ProCash Rails` uses the existing `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`,
`VPS_KNOWN_HOSTS` secrets, and the same port/path variables as the Go deployment.
Tests run on disposable PostgreSQL; the Linux image is published as
`ghcr.io/alexche360/procash-rails` and deployed by immutable digest/revision.

Runtime files live under `/opt/procash/.deploy/rails` with mode 0700. Its `.env`
is mode 0600, generated once, and never uploaded to GitHub. It has independent
Rails/database/encryption/invitation keys. SMTP settings are taken from the
existing app container without logging values. Neither local `.env` nor local
customer data is included in the release.

The `procash_rails` Compose project has its own PostgreSQL volume and credentials.
The script first verifies a custom-format backup of the Go database, migrates
only the new Rails database, starts Rails on loopback 3101, and checks health,
public pages and static assets. `ADMIN_BOOTSTRAP_PASSWORD` is required to create
`info@procash.kz`; it is passed only over stdin and is not printed. If this secret
is absent, staging remains available internally and the old public site keeps
running. Set the secret and rerun the workflow from the intended branch.

After checks succeed, the old Go app is stopped (not deleted), and Rails takes
over its loopback 8080 upstream port. Its mail-outbox worker starts only after
HTTPS health and documentation checks pass. Failure during cutover stops Rails
and restores the original Go image. Databases and backups are retained.

The AI assistant is **disabled on the VPS** until a private connection to the
Raspberry Pi is configured. A home `.local` address is not a production endpoint.
No payment provider credentials or real payment processing are enabled.

## Rollback

SSH as the existing deployment user, then:

```sh
cd /opt/procash
# Read the saved Rails image without printing secrets.
export PROCASH_IMAGE="$(cat .deploy/rails/active-image)"
export PROCASH_BIND_PORT=8080
docker compose --project-directory "$PWD/.deploy/rails" --env-file "$PWD/.deploy/rails/.env" -f "$PWD/.deploy/rails/compose.yml" stop worker app
unset PROCASH_IMAGE PROCASH_BIND_PORT
# The original Go .env and Compose files remain intact.
docker compose up -d --no-deps --no-build --pull never app
```

This returns the old Go database and old application, not data written to Rails
after launch. Reconcile any new Rails requests/accounts before using rollback.
Do not delete or overwrite either database/volume.

The old automatic Go push deployment is disabled in this migration PR; the Go
workflow remains manually runnable for a deliberate rollback. The first-launch
Rails script refuses to redeploy if `active-image` exists. Subsequent releases
need an explicit reviewed update procedure and a fresh Rails database backup.
Do not remove that guard to rerun migrations blindly.

`python3 deploy/test_rails_deploy.py` verifies staging without a password, successful
cutover ordering, secret-safe output and rollback to the original image with
controlled fake Docker/HTTP processes. Linux container and Rails tests must also
pass before a real release.
