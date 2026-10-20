#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

deploy_root="${1:?Deployment directory is required}"
image_ref="${2:?Image digest is required}"
revision="${3:?Git revision is required}"
registry_user="${4:?Registry username is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "$revision" =~ ^[a-f0-9]{40}$ ]] || { echo 'Invalid Git revision' >&2; exit 1; }
[[ "$image_ref" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$ ]] || { echo 'Expected an immutable GHCR digest' >&2; exit 1; }
cd -- "$deploy_root"
[[ "$(git rev-parse --show-toplevel)" == "$PWD" ]] || { echo 'Deploy path must be the repository root' >&2; exit 1; }
[[ -f .env && -w .env && -w . ]] || { echo 'Configure the server .env before deployment' >&2; exit 1; }

exec 9>"$(git rev-parse --git-path procash-deploy.lock)"
flock -n 9 || { echo 'Another production deployment is running' >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo 'Preserve local tracked changes before deployment' >&2; exit 1; }

previous_revision="$(git rev-parse HEAD)"
previous_image=''
previous_running=false
worktree_changed=false
app_replaced=false
backup_file=''
auth_dir="$(mktemp -d)"
trap 'rm -rf -- "$auth_dir"' EXIT

compose() { docker compose --project-directory "$PWD" --env-file "$PWD/.env" "$@"; }

prepare_env() {
  docker run --rm --user "$(id -u):$(id -g)" --entrypoint php \
    -v "$PWD:/deploy" \
    -v "$script_dir/prepare-env.php:/var/www/html/deploy/prepare-env.php:ro" \
    "$image_ref" /var/www/html/deploy/prepare-env.php /deploy/.env "$@"
}

on_failure() {
  local status="$1"
  trap - ERR HUP INT TERM
  set +e
  echo 'Deployment failed.' >&2
  if [[ "$app_replaced" == true ]]; then compose logs --tail=80 app >&2; fi
  if [[ "$worktree_changed" == true ]]; then
    if git checkout --no-overwrite-ignore --detach "$previous_revision"; then
      if [[ "$app_replaced" == true && "$previous_running" == true ]]; then
        export PROCASH_IMAGE="$previous_image"
        if compose up -d --no-deps --no-build --pull never --force-recreate app; then
          if compose exec -T app sh -c 'command -v php >/dev/null && test -f artisan'; then
            compose exec -T app php artisan view:cache
          fi
          echo 'Previous application image restored; database migrations were not reversed.' >&2
        else
          echo 'Automatic application restore failed; inspect the server.' >&2
        fi
      elif [[ "$app_replaced" == true ]]; then
        compose stop app
      fi
    else
      echo 'Cannot restore the previous checkout; inspect local changes on the server.' >&2
    fi
  fi
  if [[ -n "$backup_file" ]]; then printf 'Database backup: %s\n' "$backup_file" >&2; fi
  exit "$status"
}
trap 'on_failure "$?"' ERR
trap 'on_failure 143' HUP TERM
trap 'on_failure 130' INT

# Token arrives only on stdin, never as a process argument or saved server credential.
IFS= read -r registry_token || true
[[ -n "$registry_token" ]] || { echo 'Registry token is missing' >&2; exit 1; }
printf '%s' "$registry_token" | docker --config "$auth_dir" login ghcr.io --username "$registry_user" --password-stdin
unset registry_token
docker --config "$auth_dir" pull "$image_ref"
image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image_ref")"
[[ "$image_revision" == "$revision" ]] || { echo 'Image revision differs from the tested commit' >&2; exit 1; }
expected_image="$(docker image inspect --format '{{.Id}}' "$image_ref")"

prepare_env
previous_container="$(compose ps -a -q app)"
if [[ -n "$previous_container" ]]; then
  previous_image="$(docker inspect --format '{{.Image}}' "$previous_container")"
  previous_running="$(docker inspect --format '{{.State.Running}}' "$previous_container")"
fi

# Reuse the server's existing Git authentication, including its old deploy key.
export GIT_TERMINAL_PROMPT=0
if [[ -z "${GIT_SSH_COMMAND:-}" && -r "$HOME/.ssh/procash_deploy_git" ]]; then
  printf -v GIT_SSH_COMMAND 'ssh -i %q -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes' "$HOME/.ssh/procash_deploy_git"
  export GIT_SSH_COMMAND
fi
git fetch --no-tags origin main
git cat-file -e "$revision^{commit}"
git merge-base --is-ancestor "$revision" FETCH_HEAD
git checkout --no-overwrite-ignore --detach "$revision"
worktree_changed=true
export PROCASH_IMAGE="$image_ref"
compose config --quiet
compose up -d --wait --wait-timeout 90 db

mkdir -p .deploy/backups
backup_path="$PWD/.deploy/backups/$(date -u +%Y%m%dT%H%M%SZ)-${revision:0:12}-$$.dump"
compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$backup_path.partial"
[[ -s "$backup_path.partial" ]]
compose exec -T db pg_restore --list < "$backup_path.partial" > /dev/null
mv -- "$backup_path.partial" "$backup_path"
backup_file="$backup_path"

compose run --rm --no-deps --pull never app php artisan migrate --force --no-interaction
app_replaced=true
compose up -d --no-deps --no-build --pull never --force-recreate --wait --wait-timeout 120 app
container="$(compose ps -q app)"
[[ -n "$container" && "$(docker inspect --format '{{.Image}}' "$container")" == "$expected_image" ]]
compose exec -T app php artisan view:cache
curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8080/actuator/health > /dev/null
curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8080/login > /dev/null

prepare_env "$image_ref"
trap - ERR HUP INT TERM
printf 'Deployed commit %s\nDatabase backup: %s\n' "$revision" "$backup_file"
