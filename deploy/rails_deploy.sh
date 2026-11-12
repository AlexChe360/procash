#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
legacy_root="${1:?Existing deployment directory}"
image="${2:?Immutable image digest}"
revision="${3:?Commit}"
registry_user="${4:?Registry user}"
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
[[ "$image" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$ ]]
[[ "$revision" =~ ^[a-f0-9]{40}$ ]]
cd -- "$legacy_root"
[[ "$(git rev-parse --show-toplevel)" == "$PWD" ]]
exec 9>"$(git rev-parse --git-path procash-deploy.lock)"
flock -w 90 9
IFS= read -r registry_token
IFS= read -r admin_password || admin_password=''
auth_dir="$(mktemp -d)"
trap 'rm -rf -- "$auth_dir"' EXIT
printf '%s' "$registry_token" | docker --config "$auth_dir" login ghcr.io -u "$registry_user" --password-stdin
unset registry_token
docker --config "$auth_dir" pull "$image"
[[ "$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")" == "$revision" ]]
root="$PWD/.deploy/rails"
mkdir -p "$root" "$PWD/.deploy/backups"
chmod 700 "$root"
python3 "$script_dir/rails_prepare.py" "$root"
install -m 600 "$script_dir/compose.production.yml" "$root/compose.yml"
export PROCASH_IMAGE="$image"
export PROCASH_BIND_PORT=3101
compose() { docker compose --project-directory "$root" --env-file "$root/.env" -f "$root/compose.yml" "$@"; }
# This first deployment intentionally uses a separate, empty database.
if [[ -f "$root/active-image" ]]; then
  echo 'Rails is already published. Use a reviewed update release; refusing first-cutover script.' >&2
  exit 1
fi
backup="$PWD/.deploy/backups/pre-rails-$(date -u +%Y%m%dT%H%M%SZ)-${revision:0:12}.dump"
docker compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$backup.partial"
[[ -s "$backup.partial" ]]
docker compose exec -T db pg_restore --list < "$backup.partial" >/dev/null
mv -- "$backup.partial" "$backup"
printf 'Verified previous database backup: %s\n' "$backup"
compose up -d --wait --wait-timeout 120 db
compose run --rm --no-deps app bin/rails db:migrate
compose up -d --no-deps --wait --wait-timeout 150 app
for route in /health / /login /admin/login /connect /documentation /assets/home.css /assets/procash-logo.png; do
  curl --fail --silent --show-error --max-time 15 -H 'Host: procash.kz' "http://127.0.0.1:3101$route" >/dev/null
done
# Request a configured password only after the isolated release is healthy.
if [[ -z "$admin_password" ]]; then
  echo '::error::Rails is staged on loopback port 3101. Set ADMIN_BOOTSTRAP_PASSWORD repository secret, then rerun. Current public site remains unchanged.'
  exit 1
fi
printf '%s\n' "$admin_password" | compose exec -T app bin/rails runner /rails/deploy/bootstrap_admin.rb
unset admin_password
legacy_stopped=false
on_failure() {
  local status="$?"
  trap - ERR HUP INT TERM
  set +e
  compose stop worker app
  if [[ "$legacy_stopped" == true ]]; then docker compose up -d --no-deps --no-build --pull never app; fi
  echo 'Rails cutover failed; old application restored. Separate Rails database retained.' >&2
  exit "$status"
}
trap on_failure ERR HUP INT TERM
# Preserve the existing container/image/volume and reverse proxy. Only its port changes owner.
docker compose stop app
legacy_stopped=true
export PROCASH_BIND_PORT=8080
compose up -d --no-deps --force-recreate --wait --wait-timeout 150 app
curl --fail --silent --show-error --max-time 15 -H 'Host: procash.kz' http://127.0.0.1:8080/health >/dev/null
curl --fail --silent --show-error --max-time 20 https://procash.kz/health >/dev/null
curl --fail --silent --show-error --max-time 20 https://procash.kz/documentation >/dev/null
compose up -d --no-deps worker
printf '%s\n' "$image" > "$root/active-image"
printf '%s\n' "$revision" > "$root/active-revision"
trap - ERR HUP INT TERM
printf 'Rails deployed: %s\nOld database retained; backup: %s\nAI disabled until private connectivity to Raspberry Pi is configured.\n' "$revision" "$backup"
