PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY, entitlement_until INTEGER NOT NULL, disabled INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, account_id TEXT NOT NULL REFERENCES accounts(id), expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS installations (
  id TEXT PRIMARY KEY, account_id TEXT REFERENCES accounts(id), public_key TEXT NOT NULL, label TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('pending','approved','revoked')), created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS pairings (
  code_hash TEXT PRIMARY KEY, installation_id TEXT NOT NULL UNIQUE REFERENCES installations(id), expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS leases (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id), installation_id TEXT NOT NULL REFERENCES installations(id),
  session_id TEXT NOT NULL REFERENCES sessions(id), generation TEXT NOT NULL, expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id), installation_id TEXT NOT NULL REFERENCES installations(id),
  generation TEXT NOT NULL, idempotency_key TEXT NOT NULL, request_json TEXT NOT NULL, configuration_hash TEXT NOT NULL, request_hash TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('queued','running','completed','failed','cancelled')), attempt_id TEXT, claim_until INTEGER,
  progress_json TEXT, result_json TEXT, failure_code TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  UNIQUE(account_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS jobs_dispatch ON jobs(installation_id, generation, state, created_at);
CREATE TABLE IF NOT EXISTS device_nonces (
  installation_id TEXT NOT NULL REFERENCES installations(id), nonce TEXT NOT NULL, expires_at INTEGER NOT NULL,
  PRIMARY KEY(installation_id, nonce)
);
CREATE TABLE IF NOT EXISTS audit_events (
  id INTEGER PRIMARY KEY, at INTEGER NOT NULL, account_id TEXT, event TEXT NOT NULL, details_json TEXT NOT NULL
);
PRAGMA user_version = 1;
CREATE TABLE IF NOT EXISTS identities (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id), email TEXT NOT NULL UNIQUE,
  salt TEXT NOT NULL, password_hash TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS strategies (
  account_id TEXT NOT NULL REFERENCES accounts(id), name TEXT NOT NULL,
  configuration_json TEXT NOT NULL, updated_at INTEGER NOT NULL,
  PRIMARY KEY(account_id,name)
);
CREATE TABLE IF NOT EXISTS terminal_status (
  installation_id TEXT PRIMARY KEY REFERENCES installations(id), status_json TEXT NOT NULL, at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS trading (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id), installation_id TEXT NOT NULL,
  generation TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 0, job_id TEXT,
  revision INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS billing_events (id TEXT PRIMARY KEY, at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS ea_sequences (
  installation_id TEXT PRIMARY KEY REFERENCES installations(id), sequence INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS agent_sessions (
  installation_id TEXT PRIMARY KEY REFERENCES installations(id), agent_id TEXT NOT NULL,
  generation TEXT NOT NULL, expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS account_profiles (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id), display_name TEXT NOT NULL
);
-- A demo is issued only by registration, never by login, download or billing.
CREATE TABLE IF NOT EXISTS account_trials (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id), starts_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL CHECK(expires_at > starts_at)
);
CREATE TABLE IF NOT EXISTS enrollment_tickets (
  token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
  expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS supabase_accounts (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id), email TEXT NOT NULL,
  authority_until INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS supabase_sessions (
  session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
  provider_session_id TEXT NOT NULL, sealed_tokens TEXT NOT NULL,
  checked_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS conversations (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  id TEXT NOT NULL, title TEXT NOT NULL, provider TEXT NOT NULL, locale TEXT NOT NULL,
  messages_json TEXT NOT NULL, message_count INTEGER NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  PRIMARY KEY(account_id,id)
);
CREATE INDEX IF NOT EXISTS conversations_history ON conversations(account_id,updated_at DESC,id);
