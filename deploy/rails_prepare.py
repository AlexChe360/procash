#!/usr/bin/env python3
"""Create a dedicated Rails environment without exposing or reusing Go keys."""
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

root = Path(sys.argv[1])
env_path = root / '.env'
if env_path.exists():
    print('Existing Rails environment preserved')
    raise SystemExit(0)
# Read only the resolved SMTP configuration of the existing application.
container = subprocess.check_output(['docker', 'compose', 'ps', '-q', 'app'], text=True).strip()
if not container:
    raise SystemExit('Existing application is required to obtain mail settings')
metadata = json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]
settings = dict(item.split('=', 1) for item in metadata['Config']['Env'] if '=' in item)
mail_host = settings.get('SMTP_HOST', '')
security = settings.get('SMTP_SECURITY', '') or ('tls' if settings.get('SMTP_PORT') == '465' else 'starttls')
if security not in ('tls', 'starttls') or not mail_host:
    raise SystemExit('Configure TLS SMTP on existing deployment first')
values = {
    'RAILS_ENV': 'production', 'PORT': '3101', 'RAILS_MAX_THREADS': '3',
    'PROCASH_DB_HOST': 'db', 'PROCASH_DB_PORT': '5432',
    'PROCASH_DB_NAME': 'procash_rails_production', 'PROCASH_DB_USER': 'procash_rails',
    'PROCASH_DB_PASSWORD': secrets.token_hex(32),
    'SECRET_KEY_BASE': secrets.token_hex(64),
    'PROCASH_ENCRYPTION_KEY_V1': base64.b64encode(secrets.token_bytes(32)).decode(),
    'INVITATION_TOKEN_SECRET': base64.b64encode(secrets.token_bytes(32)).decode(),
    'APP_ORIGIN': 'https://procash.kz', 'APP_HOST': 'procash.kz',
    'SMTP_MODE': security, 'SMTP_HOST': mail_host,
    'SMTP_PORT': settings.get('SMTP_PORT', '465' if security == 'tls' else '587'),
    'SMTP_USERNAME': settings.get('SMTP_USERNAME', ''),
    'SMTP_PASSWORD': settings.get('SMTP_PASSWORD', ''),
    'SMTP_FROM': settings.get('SMTP_FROM', 'info@procash.kz'),
    'SMTP_TO': settings.get('NOTIFY_EMAIL', 'info@procash.kz'),
    'AI_ASSISTANT_ENABLED': '0',
}
# Single-quoted Compose dotenv values preserve $, backslashes and double quotes.
# Reject line breaks/quotes rather than risk malformed or interpolated secrets.
if any(any(c in str(value) for c in "\r\n'") for value in values.values()):
    raise SystemExit('Environment value requires manual quoting review')
fd = os.open(env_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as handle:
    for key, value in values.items():
        handle.write(f"{key}='{value}'\n")
print('Dedicated Rails environment created; SMTP reused, new database and crypto keys generated')
