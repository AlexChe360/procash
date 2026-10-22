#!/usr/bin/env python3
"""Run the existing administrator CLI through the deployment SSH connection."""
import os
from pathlib import Path
import shlex
import subprocess
import sys


REMOTE_COMMAND = r"""set -euo pipefail
umask 077
cd -- "$1"
[[ "$(git rev-parse --show-toplevel)" == "$PWD" ]] || { echo 'Invalid deployment directory' >&2; exit 1; }
exec 9>"$(git rev-parse --git-path procash-deploy.lock)"
flock -w 60 9 || { echo 'Another production operation is running' >&2; exit 1; }
IFS= read -r admin_password
printf '%s\n' "$admin_password" | docker compose --project-directory "$PWD" --env-file "$PWD/.env" exec -T app procash admin --email "$2"
unset admin_password
"""


def main():
    required = ("VPS_HOST", "VPS_USER", "DEPLOY_PATH", "ADMIN_EMAIL", "ADMIN_BOOTSTRAP_PASSWORD")
    if any(not os.environ.get(key) for key in required):
        print("Configure the VPS secrets and ADMIN_BOOTSTRAP_PASSWORD before running this workflow.", file=sys.stderr)
        return 1
    password = os.environ["ADMIN_BOOTSTRAP_PASSWORD"]
    if not 12 <= len(password.encode("utf-8")) <= 72 or any(c in password for c in "\r\n"):
        print("ADMIN_BOOTSTRAP_PASSWORD must contain 12–72 UTF-8 bytes without line breaks.", file=sys.stderr)
        return 1
    email = os.environ["ADMIN_EMAIL"].strip()
    if "@" not in email or any(c.isspace() for c in email):
        print("Enter a valid administrator email.", file=sys.stderr)
        return 1
    port = os.environ.get("VPS_PORT", "22")
    if not port.isascii() or not port.isdigit() or not 1 <= int(port) <= 65535:
        print("Invalid VPS_PORT.", file=sys.stderr)
        return 1
    remote = shlex.join(["bash", "-c", REMOTE_COMMAND, "--", os.environ["DEPLOY_PATH"], email])
    command = [
        "ssh", "-T", "-i", str(Path.home() / ".ssh/id_ed25519"), "-p", port,
        "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=15",
        "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4",
        os.environ["VPS_USER"] + "@" + os.environ["VPS_HOST"], remote,
    ]
    environment = {key: value for key, value in os.environ.items() if key != "ADMIN_BOOTSTRAP_PASSWORD"}
    return subprocess.run(command, input=password + "\n", text=True, env=environment, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
