BEGIN;

ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS booking_slug TEXT,
  ADD COLUMN IF NOT EXISTS booking_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS booking_public_url TEXT,
  ADD COLUMN IF NOT EXISTS booking_created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS booking_updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS booking_settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS old_booking_slugs JSONB NOT NULL DEFAULT '[]'::jsonb;

WITH normalized AS (
  SELECT id,
    trim(both '-' from regexp_replace(
      translate(lower(display_name), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
      '[^a-z0-9]+', '-', 'g')) AS base
  FROM businesses WHERE booking_slug IS NULL
), ranked AS (
  SELECT id, CASE WHEN base = '' OR base IN ('api','admin','privacy','politica-de-privacidade','excluir-conta','termos-de-uso','contato','login','suporte','agendar','assets') THEN 'studio-' || left(id, 8) ELSE left(base, 60) END AS base,
    row_number() OVER (PARTITION BY base ORDER BY id) AS position
  FROM normalized
)
UPDATE businesses b SET
  booking_slug = r.base || CASE WHEN r.position = 1 THEN '' ELSE '-' || r.position::text END,
  booking_public_url = 'https://studioflowapp.com.br/agendar/' || r.base || CASE WHEN r.position = 1 THEN '' ELSE '-' || r.position::text END,
  booking_created_at = COALESCE(b.booking_created_at, now()), booking_updated_at = now()
FROM ranked r WHERE b.id = r.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_businesses_booking_slug ON businesses(booking_slug);

CREATE TABLE IF NOT EXISTS public_appointments (
  id TEXT PRIMARY KEY, public_token_hash TEXT NOT NULL UNIQUE,
  idempotency_key TEXT NOT NULL, business_id TEXT NOT NULL REFERENCES businesses(id),
  unit_id TEXT, service_id TEXT NOT NULL, professional_id TEXT,
  client_id TEXT NOT NULL, appointment_id TEXT NOT NULL UNIQUE,
  client_name TEXT NOT NULL, client_phone TEXT NOT NULL, notes TEXT,
  starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'agendado', created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(business_id, idempotency_key)
);
ALTER TABLE public_appointments ADD COLUMN IF NOT EXISTS client_id TEXT;
ALTER TABLE public_appointments ADD COLUMN IF NOT EXISTS appointment_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_public_appointments_main ON public_appointments(appointment_id);

CREATE INDEX IF NOT EXISTS idx_public_appointments_slot ON public_appointments(business_id, professional_id, starts_at, ends_at) WHERE status NOT IN ('cancelado','rejeitado');

CREATE TABLE IF NOT EXISTS store_commands (
  id TEXT PRIMARY KEY, number TEXT NOT NULL, business_id TEXT NOT NULL REFERENCES businesses(id),
  unit_id TEXT, client_id TEXT NOT NULL, professional_id TEXT, status TEXT NOT NULL,
  subtotal NUMERIC(14,2) NOT NULL DEFAULT 0, discount NUMERIC(14,2) NOT NULL DEFAULT 0,
  total NUMERIC(14,2) NOT NULL DEFAULT 0, paid NUMERIC(14,2) NOT NULL DEFAULT 0,
  due_at DATE, sale_id TEXT, payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(business_id, number)
);

INSERT INTO schema_migrations(version) VALUES (13) ON CONFLICT DO NOTHING;
COMMIT;
