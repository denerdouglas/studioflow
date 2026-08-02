-- Migration 010: Marketplace Admin & V2 Architecture

-- 1. Criação da estrutura de Platform Admin
CREATE TABLE IF NOT EXISTS platform_admins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid UNIQUE NOT NULL, -- references users(id) in logic (cross-tenant)
  role text NOT NULL, -- 'platform_super_admin', 'marketplace_admin', 'marketplace_analyst', 'support_admin'
  active boolean NOT NULL DEFAULT true,
  permissions jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  created_by uuid,
  last_login_at timestamptz
);

-- 2. Evolução de affiliate_programs para marketplace_partners
ALTER TABLE affiliate_programs RENAME TO marketplace_partners;
ALTER INDEX affiliate_programs_pkey RENAME TO marketplace_partners_pkey;

ALTER TABLE marketplace_partners 
  ADD COLUMN IF NOT EXISTS slug text UNIQUE,
  ADD COLUMN IF NOT EXISTS logo text,
  ADD COLUMN IF NOT EXISTS partner_type text NOT NULL DEFAULT 'retailer',
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'draft',
  ADD COLUMN IF NOT EXISTS priority integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS affiliate_identifier text,
  ADD COLUMN IF NOT EXISTS url_template text,
  ADD COLUMN IF NOT EXISTS supports_search boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS supports_deep_link boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS supports_conversion boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS secret_encrypted text,
  ADD COLUMN IF NOT EXISTS secret_key_version text,
  ADD COLUMN IF NOT EXISTS public_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS notes text;

-- Atualização dos dados herdados
UPDATE marketplace_partners 
SET status = CASE WHEN enabled THEN 'active' ELSE 'suspended' END,
    slug = lower(regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g')),
    affiliate_identifier = partner_id;

-- Podemos remover as antigas para forçar a migração de tipo, ou manter.
-- Removemos enabled e partner_id pois foram migrados
ALTER TABLE marketplace_partners DROP COLUMN IF EXISTS enabled;
ALTER TABLE marketplace_partners DROP COLUMN IF EXISTS partner_id;

-- 3. Criação da tabela de domínios validados
CREATE TABLE IF NOT EXISTS marketplace_partner_domains (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id text NOT NULL REFERENCES marketplace_partners(id) ON DELETE CASCADE,
  hostname text NOT NULL,
  allow_subdomains boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_marketplace_partner_domains ON marketplace_partner_domains(hostname);

-- Migração de allowed_domains (jsonb) da antiga tabela
DO \$\$
DECLARE 
  rec RECORD;
  domain_val text;
BEGIN
  FOR rec IN SELECT id, allowed_domains FROM marketplace_partners WHERE allowed_domains IS NOT NULL AND jsonb_typeof(allowed_domains) = 'array'
  LOOP
    FOR domain_val IN SELECT jsonb_array_elements_text(rec.allowed_domains)
    LOOP
      INSERT INTO marketplace_partner_domains (partner_id, hostname, allow_subdomains)
      VALUES (rec.id, domain_val, true)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END LOOP;
END \$\$;

ALTER TABLE marketplace_partners DROP COLUMN IF EXISTS allowed_domains;

-- 4. Evolução de marketplace_offers
-- Já existe e está associada a program_id, vamos renomear a fk se necessário, mas para manter compatibilidade:
ALTER TABLE marketplace_offers RENAME COLUMN program_id TO partner_id;
-- Nota: A constraint antiga ainda se chamará marketplace_offers_program_id_fkey, deixaremos assim para evitar falhas ou podemos recriar.

-- 5. Evolução de affiliate_clicks para marketplace_clicks
ALTER TABLE affiliate_clicks RENAME TO marketplace_clicks;
ALTER INDEX affiliate_clicks_pkey RENAME TO marketplace_clicks_pkey;
ALTER INDEX idx_affiliate_click_business RENAME TO idx_marketplace_click_business;

-- Remover policy antiga e aplicar nova
DROP POLICY IF EXISTS affiliate_click_tenant ON marketplace_clicks;
ALTER TABLE marketplace_clicks ENABLE ROW LEVEL SECURITY;
CREATE POLICY marketplace_click_tenant ON marketplace_clicks
  USING (business_id = nullif(current_setting('app.business_id', true), '')::uuid)
  WITH CHECK (business_id = nullif(current_setting('app.business_id', true), '')::uuid);

ALTER TABLE marketplace_clicks
  RENAME COLUMN program_id TO partner_id;
  
ALTER TABLE marketplace_clicks
  ADD COLUMN IF NOT EXISTS click_status text NOT NULL DEFAULT 'created', -- 'created', 'redirected', 'expired', 'blocked', 'failed'
  ADD COLUMN IF NOT EXISTS source text,
  ADD COLUMN IF NOT EXISTS campaign_id text,
  ADD COLUMN IF NOT EXISTS user_agent_hash text,
  ADD COLUMN IF NOT EXISTS ip_hash text,
  ADD COLUMN IF NOT EXISTS ranking_position integer,
  ADD COLUMN IF NOT EXISTS ranking_reason text,
  ADD COLUMN IF NOT EXISTS redirected_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

CREATE INDEX idx_marketplace_clicks_status ON marketplace_clicks(click_status);

-- 6. Evolução de affiliate_conversions para marketplace_conversion_events
ALTER TABLE affiliate_conversions RENAME TO marketplace_conversion_events;
ALTER INDEX affiliate_conversions_pkey RENAME TO marketplace_conversion_events_pkey;
ALTER TABLE marketplace_conversion_events RENAME COLUMN program_id TO partner_id;
-- Unique constraint antiga ainda valerá

-- 7. Criação de Cache, Buscas, Campanhas e Auditoria
CREATE TABLE IF NOT EXISTS marketplace_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id uuid REFERENCES marketplace_categories(id),
  slug text UNIQUE NOT NULL,
  name text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS marketplace_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id text NOT NULL REFERENCES marketplace_partners(id),
  name text NOT NULL,
  slug text UNIQUE NOT NULL,
  type text NOT NULL, -- 'discount', 'coupon', 'special_commission'
  coupon_code text,
  active boolean NOT NULL DEFAULT true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS marketplace_products_cache (
  id text PRIMARY KEY, -- 'partner_id:external_id'
  partner_id text NOT NULL REFERENCES marketplace_partners(id),
  external_id text NOT NULL,
  payload jsonb NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_marketplace_cache_expire ON marketplace_products_cache(expires_at);

CREATE TABLE IF NOT EXISTS marketplace_search_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), -- Pode usar v7 na inserção
  business_id uuid, -- Opcional, log de quem buscou
  user_id uuid,
  query text NOT NULL,
  category_id uuid REFERENCES marketplace_categories(id),
  source text NOT NULL,
  cache_hit boolean NOT NULL,
  results_count integer NOT NULL,
  response_time_ms integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS marketplace_admin_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform_admin_id uuid NOT NULL REFERENCES platform_admins(id),
  action text NOT NULL,
  entity text NOT NULL,
  entity_id text NOT NULL,
  before_state jsonb,
  after_state jsonb,
  reason text,
  ip_address_hash text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Inserir registros na schema_migrations
INSERT INTO schema_migrations (version)
VALUES ('010_marketplace_admin')
ON CONFLICT (version) DO NOTHING;

-- Views de compatibilidade não serão necessárias pois renomeamos e os códigos que acessavam 'affiliate_programs' 
-- deverão ser refatorados na etapa 3B.2 (nenhuma interface os consumia ainda em prod de forma forte).
