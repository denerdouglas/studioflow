ALTER TABLE marketplace_offers
  ADD COLUMN IF NOT EXISTS brand text,
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS keywords text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS gtin text,
  ADD COLUMN IF NOT EXISTS product_code text,
  ADD COLUMN IF NOT EXISTS priority integer NOT NULL DEFAULT 0;

ALTER TABLE marketplace_offers ALTER COLUMN price_cents DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_marketplace_offers_lookup
  ON marketplace_offers(active, priority DESC, verified_at DESC);
CREATE INDEX IF NOT EXISTS idx_marketplace_offers_gtin
  ON marketplace_offers(gtin) WHERE gtin IS NOT NULL;

ALTER TABLE marketplace_offers
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS original_url text,
  ADD COLUMN IF NOT EXISTS affiliate_url text,
  ADD COLUMN IF NOT EXISTS valid_until timestamptz,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_checked_at timestamptz;

CREATE TABLE IF NOT EXISTS affiliate_link_checks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id text NOT NULL REFERENCES marketplace_offers(id) ON DELETE CASCADE,
  http_status integer,
  valid boolean NOT NULL,
  error text,
  checked_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS affiliate_search_demands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid,
  query text NOT NULL,
  normalized_query text NOT NULL,
  search_count integer NOT NULL DEFAULT 1,
  first_searched_at timestamptz NOT NULL DEFAULT now(),
  last_searched_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(business_id, normalized_query)
);

INSERT INTO schema_migrations (version)
VALUES ('014_affiliate_catalog') ON CONFLICT (version) DO NOTHING;
