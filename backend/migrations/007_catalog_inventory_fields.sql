BEGIN;

ALTER TABLE catalog_products_shared
  ADD COLUMN IF NOT EXISTS content_per_unit REAL NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS content_unit TEXT;

INSERT INTO schema_migrations (version)
VALUES (7)
ON CONFLICT (version) DO NOTHING;

COMMIT;
