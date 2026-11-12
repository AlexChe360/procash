#!/usr/bin/env python3
"""Read deployment metadata through the existing Actions SSH credentials."""
import os
import shlex
import subprocess
from pathlib import Path

REMOTE = r'''set -euo pipefail
cd -- "$1"
printf '=== System ===\n'
uname -sr
free -m
df -h /
printf '\n=== Existing deployment ===\n'
git rev-parse HEAD
docker compose version
docker compose ps --format json
printf '\n=== Listening ports ===\n'
ss -lnt
printf '\n=== Database size and schema (no records or credentials) ===\n'
docker compose exec -T db sh -c 'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<'SQL'
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;
SELECT table_name, string_agg(column_name || ':' || data_type, ', ' ORDER BY ordinal_position) AS columns
FROM information_schema.columns WHERE table_schema = 'public' GROUP BY table_name ORDER BY table_name;
SQL
printf '\n=== HTTP health ===\n'
curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8080/actuator/health
printf '\n=== Reverse proxy availability ===\n'
command -v nginx || true
sudo -n test -d /etc/nginx/sites-enabled && sudo -n ls /etc/nginx/sites-enabled || true
'''

port = os.environ.get('VPS_PORT', '22')
if not port.isascii() or not port.isdigit() or not 1 <= int(port) <= 65535:
    raise SystemExit('Invalid SSH port')
remote = shlex.join(['bash', '-c', REMOTE, '--', os.environ['DEPLOY_PATH']])
command = ['ssh', '-T', '-i', str(Path.home() / '.ssh/id_ed25519'), '-p', port,
           '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
           '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4',
           os.environ['VPS_USER'] + '@' + os.environ['VPS_HOST'], remote]
raise SystemExit(subprocess.run(command, check=False).returncode)
