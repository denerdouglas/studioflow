BEGIN;

-- IDs de usuários do StudioFlow são TEXT. Corrige a definição histórica da
-- tabela administrativa sem provisionar ou promover qualquer conta.
ALTER TABLE platform_admins ALTER COLUMN user_id TYPE TEXT USING user_id::text;
ALTER TABLE platform_admins ALTER COLUMN created_by TYPE TEXT USING created_by::text;

CREATE TABLE global_products (
  id TEXT PRIMARY KEY,
  barcode TEXT NOT NULL UNIQUE CHECK (barcode ~ '^[0-9]{8,14}$'),
  brand TEXT NOT NULL,
  name TEXT NOT NULL,
  variant TEXT,
  category TEXT NOT NULL,
  description TEXT,
  image_url TEXT CHECK (image_url IS NULL OR image_url ~ '^https://'),
  size TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  search_keywords TEXT[] NOT NULL DEFAULT '{}',
  verified BOOLEAN NOT NULL DEFAULT TRUE,
  created_by TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE global_product_suggestions (
  id TEXT PRIMARY KEY,
  barcode TEXT NOT NULL CHECK (barcode ~ '^[0-9]{8,14}$'),
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  brand TEXT,
  variant TEXT,
  category TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected')),
  reviewed_by TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE global_courses (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  provider TEXT NOT NULL,
  description TEXT NOT NULL,
  image_url TEXT CHECK (image_url IS NULL OR image_url ~ '^https://'),
  category TEXT NOT NULL,
  search_keywords TEXT[] NOT NULL DEFAULT '{}',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE commercial_campaigns
  ADD COLUMN global_product_id TEXT REFERENCES global_products(id),
  ADD COLUMN course_id TEXT REFERENCES global_courses(id);

CREATE INDEX idx_global_products_search ON global_products
  USING GIN (to_tsvector('simple'::regconfig,
    brand || ' ' || name || ' ' || COALESCE(variant,'') || ' ' ||
    category || ' ' || COALESCE(description,'') || ' ' || COALESCE(size,'')));
CREATE INDEX idx_global_products_search_keywords ON global_products
  USING GIN (search_keywords);
CREATE INDEX idx_global_product_suggestions_status
  ON global_product_suggestions(status, created_at);
CREATE UNIQUE INDEX uq_global_product_suggestions_pending
  ON global_product_suggestions(business_id, barcode)
  WHERE status = 'pending';
CREATE INDEX idx_global_courses_search ON global_courses
  USING GIN (to_tsvector('simple'::regconfig,
    title || ' ' || provider || ' ' || description || ' ' || category));
CREATE INDEX idx_global_courses_search_keywords ON global_courses
  USING GIN (search_keywords);
CREATE INDEX idx_campaign_global_product ON commercial_campaigns(global_product_id);
CREATE INDEX idx_campaign_course ON commercial_campaigns(course_id);

INSERT INTO schema_migrations(version) VALUES (22)
ON CONFLICT(version) DO NOTHING;

COMMIT;
