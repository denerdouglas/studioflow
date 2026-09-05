BEGIN;

-- Fonte de verdade: sync_records. O aplicativo mantém tabelas SQLite tipadas;
-- o backend persiste estas entidades pela camada genérica e sua RLS existente.
-- Não criar tabelas físicas homônimas evita duas fontes independentes.

CREATE INDEX IF NOT EXISTS idx_sync_records_accounts_payable_due
  ON sync_records (business_id, (payload->>'due_date'), (payload->>'status'))
  WHERE entity = 'accounts_payable' AND deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_sync_records_notification_preferences
  ON sync_records (business_id, (payload->>'category'), (payload->>'channel'))
  WHERE entity = 'notification_preferences' AND deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_sync_records_notification_events_schedule
  ON sync_records (
    business_id,
    (payload->>'status'),
    (payload->>'scheduled_at')
  )
  WHERE entity = 'notification_events' AND deleted = FALSE;

INSERT INTO schema_migrations(version)
VALUES (20)
ON CONFLICT (version) DO NOTHING;

COMMIT;
