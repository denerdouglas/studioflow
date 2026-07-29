CREATE TABLE IF NOT EXISTS affiliate_programs (
  id text PRIMARY KEY,
  name text NOT NULL,
  enabled boolean NOT NULL DEFAULT false,
  partner_id text,
  secret_reference text,
  allowed_domains jsonb NOT NULL DEFAULT '[]'::jsonb,
  disclosure text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS marketplace_offers (
  id text PRIMARY KEY,
  program_id text NOT NULL REFERENCES affiliate_programs(id),
  title text NOT NULL,
  seller text NOT NULL,
  destination_url text NOT NULL,
  price_cents integer NOT NULL CHECK (price_cents >= 0),
  shipping_cents integer NOT NULL DEFAULT 0 CHECK (shipping_cents >= 0),
  delivery_days integer CHECK (delivery_days >= 0),
  currency char(3) NOT NULL DEFAULT 'BRL',
  active boolean NOT NULL DEFAULT true,
  verified_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS affiliate_clicks (
  id uuid PRIMARY KEY,
  business_id uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  offer_id text NOT NULL REFERENCES marketplace_offers(id),
  program_id text NOT NULL REFERENCES affiliate_programs(id),
  destination_url text NOT NULL,
  clicked_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS affiliate_conversions (
  id uuid PRIMARY KEY,
  program_id text NOT NULL REFERENCES affiliate_programs(id),
  external_id text NOT NULL,
  click_id uuid REFERENCES affiliate_clicks(id),
  sale_cents integer NOT NULL CHECK (sale_cents >= 0),
  commission_cents integer NOT NULL CHECK (commission_cents >= 0),
  status text NOT NULL CHECK (status IN ('estimada', 'confirmada', 'cancelada')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(program_id, external_id)
);

CREATE INDEX IF NOT EXISTS idx_marketplace_offer_search
  ON marketplace_offers(active, verified_at);
CREATE INDEX IF NOT EXISTS idx_affiliate_click_business
  ON affiliate_clicks(business_id, clicked_at);
CREATE INDEX IF NOT EXISTS idx_affiliate_conversion_status
  ON affiliate_conversions(status, created_at);

ALTER TABLE affiliate_clicks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS affiliate_click_tenant ON affiliate_clicks;
CREATE POLICY affiliate_click_tenant ON affiliate_clicks
  USING (business_id = nullif(current_setting('app.business_id', true), '')::uuid)
  WITH CHECK (business_id = nullif(current_setting('app.business_id', true), '')::uuid);

INSERT INTO schema_migrations (version)
VALUES ('003_marketplace_affiliates')
ON CONFLICT (version) DO NOTHING;
