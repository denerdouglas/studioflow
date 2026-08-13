BEGIN;

CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  login TEXT NOT NULL,
  password_hash TEXT,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_accounts_login ON accounts(lower(login));

INSERT INTO accounts(id, login, password_hash, name, phone)
SELECT
  'acc_' || md5(lower(login)),
  lower(login),
  CASE
    WHEN COUNT(*) = 1 THEN MIN(password_hash)
    ELSE NULL
  END,
  MIN(name),
  MIN(phone)
FROM users
GROUP BY lower(login)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS business_memberships (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  business_id TEXT NOT NULL REFERENCES businesses(id),
  legacy_user_id TEXT REFERENCES users(id),
  professional_id TEXT,
  role TEXT NOT NULL CHECK(role IN ('owner','manager','collaborator')),
  permissions JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'active',
  principal BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(account_id,business_id)
);
INSERT INTO business_memberships(
  id,account_id,business_id,legacy_user_id,role,permissions,status,principal)
SELECT 'mem_' || id, 'acc_' || md5(lower(login)), business_id, id,
  CASE role WHEN 'dono' THEN 'owner' WHEN 'gerente' THEN 'manager'
       ELSE 'collaborator' END,
  permissions, CASE WHEN active THEN 'active' ELSE 'inactive' END,
  role='dono'
FROM users ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS business_public_codes (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id),
  code TEXT NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  rotated_at TIMESTAMPTZ
);
INSERT INTO business_public_codes(id,business_id,code)
SELECT 'code_' || id, id,
       'SF-' || upper(substr(md5(id),1,6)) FROM businesses
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS business_membership_requests (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  business_id TEXT NOT NULL REFERENCES businesses(id),
  status TEXT NOT NULL DEFAULT 'pending',
  reviewed_by_account_id TEXT REFERENCES accounts(id),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  UNIQUE(account_id,business_id,status)
);

CREATE TABLE IF NOT EXISTS account_subscriptions (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id),
  plan_id TEXT NOT NULL DEFAULT 'base',
  status TEXT NOT NULL DEFAULT 'inactive',
  included_units INTEGER NOT NULL DEFAULT 1,
  contracted_units INTEGER NOT NULL DEFAULT 1,
  included_collaborators INTEGER NOT NULL DEFAULT 3,
  contracted_collaborator_capacity INTEGER NOT NULL DEFAULT 3,
  base_price_micros BIGINT NOT NULL DEFAULT 0,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'BRL',
  version INTEGER NOT NULL DEFAULT 1,
  valid_until TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE subscriptions ALTER COLUMN user_id TYPE TEXT USING user_id::text;
ALTER TABLE subscriptions ALTER COLUMN business_id TYPE TEXT USING business_id::text;

INSERT INTO schema_migrations(version) VALUES(17) ON CONFLICT DO NOTHING;
COMMIT;
