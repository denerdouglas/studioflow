BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS businesses (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  display_name TEXT NOT NULL,
  segment TEXT NOT NULL DEFAULT 'salao',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  login TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('dono', 'gerente', 'colaborador', 'rolg_admin')),
  permissions JSONB NOT NULL DEFAULT '{}'::jsonb,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_business_login
  ON users (business_id, lower(login));
CREATE INDEX IF NOT EXISTS idx_users_global_login
  ON users (lower(login), active);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  refresh_token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_agent TEXT,
  ip_address TEXT
);
CREATE INDEX IF NOT EXISTS idx_sessions_user_active
  ON sessions (user_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGSERIAL PRIMARY KEY,
  event TEXT NOT NULL,
  business_id TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  session_id TEXT,
  success BOOLEAN NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_business_created
  ON audit_logs (business_id, created_at DESC);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  channel TEXT NOT NULL CHECK (channel IN ('email', 'sms')),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sync_records (
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  server_version INTEGER NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  updated_by TEXT NOT NULL REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, entity, entity_id)
);

CREATE TABLE IF NOT EXISTS sync_changes (
  cursor BIGSERIAL PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  server_version INTEGER NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  deleted BOOLEAN NOT NULL,
  updated_by TEXT NOT NULL REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sync_changes_business_cursor
  ON sync_changes (business_id, cursor);

CREATE TABLE IF NOT EXISTS sync_operations (
  operation_id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id),
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('applied', 'conflict')),
  server_version INTEGER NOT NULL,
  server_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS uploads (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id),
  object_key TEXT NOT NULL UNIQUE,
  content_type TEXT NOT NULL,
  byte_length BIGINT NOT NULL,
  sha256 TEXT NOT NULL,
  provider TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_uploads_business
  ON uploads (business_id, created_at DESC);

CREATE TABLE IF NOT EXISTS webhook_events (
  provider TEXT NOT NULL,
  external_id TEXT NOT NULL,
  business_id TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  payload JSONB NOT NULL,
  processed_at TIMESTAMPTZ,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (provider, external_id)
);

INSERT INTO schema_migrations (version)
VALUES (1)
ON CONFLICT (version) DO NOTHING;

COMMIT;
