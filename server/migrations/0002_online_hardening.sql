-- Extend the first local groups migration without rewriting a deployed D1 table.
-- Idempotency rows reserve a key and bind it to the exact request before a
-- mutation. The completed flag keeps the old response column non-null while
-- allowing D1 batch() to reserve and complete atomically.
ALTER TABLE memberships ADD COLUMN revoked_at TEXT;
ALTER TABLE memberships ADD COLUMN revoked_join_code TEXT;
ALTER TABLE idempotency ADD COLUMN method TEXT NOT NULL DEFAULT '';
ALTER TABLE idempotency ADD COLUMN path TEXT NOT NULL DEFAULT '';
ALTER TABLE idempotency ADD COLUMN body_hash TEXT NOT NULL DEFAULT '';
ALTER TABLE idempotency ADD COLUMN response_status INTEGER NOT NULL DEFAULT 200;
ALTER TABLE idempotency ADD COLUMN completed INTEGER NOT NULL DEFAULT 1;
