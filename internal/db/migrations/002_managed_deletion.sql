-- Keep transaction history while removing accounts and venues from active use.
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
