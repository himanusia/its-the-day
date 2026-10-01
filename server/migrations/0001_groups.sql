PRAGMA foreign_keys = ON;

-- Better Auth core schema. The app never writes passwords or sessions itself;
-- Better Auth owns these tables and the auth handler below owns the lifecycle.
CREATE TABLE IF NOT EXISTS "user" (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  emailVerified INTEGER NOT NULL DEFAULT 0,
  image TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS session (
  id TEXT PRIMARY KEY,
  expiresAt TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  ipAddress TEXT,
  userAgent TEXT,
  userId TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS session_userId ON session(userId);
CREATE TABLE IF NOT EXISTS account (
  id TEXT PRIMARY KEY,
  accountId TEXT NOT NULL,
  providerId TEXT NOT NULL,
  userId TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  accessToken TEXT,
  refreshToken TEXT,
  idToken TEXT,
  accessTokenExpiresAt TEXT,
  refreshTokenExpiresAt TEXT,
  scope TEXT,
  password TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS account_userId ON account(userId);
CREATE TABLE IF NOT EXISTS verification (
  id TEXT PRIMARY KEY,
  identifier TEXT NOT NULL,
  value TEXT NOT NULL,
  expiresAt TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS verification_identifier ON verification(identifier);

CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  join_code TEXT NOT NULL UNIQUE,
  owner_id TEXT NOT NULL REFERENCES accounts(id),
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS memberships (
  group_id TEXT NOT NULL REFERENCES groups(id),
  account_id TEXT NOT NULL REFERENCES accounts(id),
  role TEXT NOT NULL CHECK(role IN ('owner','member')),
  active INTEGER NOT NULL DEFAULT 1,
  joined_at TEXT NOT NULL,
  PRIMARY KEY(group_id,account_id)
);
CREATE TABLE IF NOT EXISTS goals (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES accounts(id),
  group_id TEXT REFERENCES groups(id),
  visibility TEXT NOT NULL CHECK(visibility IN ('private','shared')),
  kind TEXT NOT NULL CHECK(kind IN ('quantity','checklist')),
  target_mode TEXT NOT NULL CHECK(target_mode IN ('shared_total','individual')),
  title TEXT NOT NULL,
  unit TEXT NOT NULL,
  target INTEGER NOT NULL CHECK(target > 0),
  deadline TEXT NOT NULL,
  created_at TEXT NOT NULL,
  deleted_at TEXT
);
CREATE TABLE IF NOT EXISTS progress (
  id TEXT PRIMARY KEY,
  goal_id TEXT NOT NULL REFERENCES goals(id),
  actor_id TEXT NOT NULL REFERENCES accounts(id),
  amount INTEGER NOT NULL CHECK(amount > 0),
  title TEXT,
  note TEXT,
  url TEXT,
  occurred_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  deleted_at TEXT
);
CREATE TABLE IF NOT EXISTS checklist_items (
  id TEXT PRIMARY KEY,
  goal_id TEXT NOT NULL REFERENCES goals(id),
  title TEXT NOT NULL,
  explanation TEXT,
  created_at TEXT NOT NULL,
  deleted_at TEXT
);
CREATE TABLE IF NOT EXISTS checklist_checks (
  item_id TEXT NOT NULL REFERENCES checklist_items(id),
  actor_id TEXT NOT NULL REFERENCES accounts(id),
  checked INTEGER NOT NULL,
  changed_at TEXT NOT NULL,
  PRIMARY KEY(item_id,actor_id)
);
CREATE TABLE IF NOT EXISTS idempotency (
  actor_id TEXT NOT NULL,
  key TEXT NOT NULL,
  response TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(actor_id,key)
);
CREATE INDEX IF NOT EXISTS goals_group ON goals(group_id);
CREATE INDEX IF NOT EXISTS goals_owner ON goals(owner_id);
CREATE INDEX IF NOT EXISTS progress_goal ON progress(goal_id);
CREATE INDEX IF NOT EXISTS checklist_items_goal ON checklist_items(goal_id);
