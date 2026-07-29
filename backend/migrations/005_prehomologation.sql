BEGIN;

CREATE TABLE IF NOT EXISTS catalog_gtin_cache (
  gtin TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK (status IN ('found','not_found')),
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  source TEXT NOT NULL,
  source_license TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS catalog_gtin_logs (
  id BIGSERIAL PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gtin TEXT NOT NULL,
  result TEXT NOT NULL CHECK (result IN ('cache_hit','found','not_found','provider_error','invalid')),
  source TEXT,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  error_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_catalog_gtin_logs_business
  ON catalog_gtin_logs(business_id, created_at DESC);

CREATE TABLE IF NOT EXISTS whatsapp_templates (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  meta_name TEXT NOT NULL,
  language_code TEXT NOT NULL DEFAULT 'pt_BR',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','paused','disabled')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (business_id, kind)
);

ALTER TABLE catalog_gtin_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS catalog_gtin_logs_tenant_policy ON catalog_gtin_logs;
CREATE POLICY catalog_gtin_logs_tenant_policy ON catalog_gtin_logs
  USING (business_id = current_setting('app.business_id', true));
DROP POLICY IF EXISTS whatsapp_templates_tenant_policy ON whatsapp_templates;
CREATE POLICY whatsapp_templates_tenant_policy ON whatsapp_templates
  USING (business_id = current_setting('app.business_id', true))
  WITH CHECK (business_id = current_setting('app.business_id', true));

COMMIT;