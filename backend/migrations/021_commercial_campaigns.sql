BEGIN;

CREATE TABLE IF NOT EXISTS commercial_campaigns (
  id TEXT PRIMARY KEY,
  title VARCHAR(200) NOT NULL,
  subtitle VARCHAR(300),
  description TEXT NOT NULL,
  image_url TEXT,
  destination_url TEXT NOT NULL CHECK (destination_url ~ '^https://'),
  category VARCHAR(80) NOT NULL,
  source_type VARCHAR(30) NOT NULL CHECK (source_type IN ('rolg_academy', 'affiliate', 'partner', 'internal')),
  price_cents INTEGER CHECK (price_cents IS NULL OR price_cents >= 0),
  original_price_cents INTEGER CHECK (original_price_cents IS NULL OR original_price_cents >= 0),
  badge VARCHAR(80),
  cta_text VARCHAR(80) NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT FALSE,
  segments TEXT[] NOT NULL DEFAULT '{}',
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS commercial_campaign_events (
  id TEXT PRIMARY KEY,
  campaign_id TEXT NOT NULL REFERENCES commercial_campaigns(id) ON DELETE CASCADE,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id TEXT,
  event_type VARCHAR(20) NOT NULL CHECK (event_type IN ('impression', 'click')),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_commercial_campaigns_available
  ON commercial_campaigns (active, priority DESC, starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_commercial_campaigns_segments
  ON commercial_campaigns USING GIN (segments);
CREATE INDEX IF NOT EXISTS idx_commercial_campaign_events_metrics
  ON commercial_campaign_events (campaign_id, event_type, occurred_at);
CREATE INDEX IF NOT EXISTS idx_commercial_campaign_events_business
  ON commercial_campaign_events (business_id, occurred_at);

INSERT INTO schema_migrations (version) VALUES (21)
ON CONFLICT (version) DO NOTHING;

COMMIT;
