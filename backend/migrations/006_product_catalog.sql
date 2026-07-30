BEGIN;

CREATE TABLE IF NOT EXISTS catalog_products_shared (
  barcode TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  brand TEXT,
  description TEXT,
  category TEXT,
  image_url TEXT,
  unit TEXT,
  source TEXT NOT NULL CHECK (source IN ('manual','studioflow','external')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','review','inactive')),
  contributed_by_business_id TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  contributed_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_catalog_products_shared_name
  ON catalog_products_shared (lower(name), lower(COALESCE(brand, '')));

INSERT INTO schema_migrations (version)
VALUES (6)
ON CONFLICT (version) DO NOTHING;

COMMIT;