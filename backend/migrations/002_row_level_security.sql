BEGIN;

-- O backend define `SET LOCAL app.business_id = '<id>'` em transações
-- autenticadas. O usuário de runtime não deve ser proprietário das tabelas.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE uploads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_tenant_policy ON users;
CREATE POLICY users_tenant_policy ON users
  USING (
    business_id = current_setting('app.business_id', true)
    OR current_setting('app.auth_lookup', true) = '1'
  )
  WITH CHECK (business_id = current_setting('app.business_id', true));

DROP POLICY IF EXISTS sessions_tenant_policy ON sessions;
CREATE POLICY sessions_tenant_policy ON sessions
  USING (
    business_id = current_setting('app.business_id', true)
    OR current_setting('app.auth_lookup', true) = '1'
  )
  WITH CHECK (business_id = current_setting('app.business_id', true));

DROP POLICY IF EXISTS sync_records_tenant_policy ON sync_records;
CREATE POLICY sync_records_tenant_policy ON sync_records
  USING (business_id = current_setting('app.business_id', true))
  WITH CHECK (business_id = current_setting('app.business_id', true));

DROP POLICY IF EXISTS sync_changes_tenant_policy ON sync_changes;
CREATE POLICY sync_changes_tenant_policy ON sync_changes
  USING (business_id = current_setting('app.business_id', true))
  WITH CHECK (business_id = current_setting('app.business_id', true));

DROP POLICY IF EXISTS sync_operations_tenant_policy ON sync_operations;
CREATE POLICY sync_operations_tenant_policy ON sync_operations
  USING (business_id = current_setting('app.business_id', true))
  WITH CHECK (business_id = current_setting('app.business_id', true));

DROP POLICY IF EXISTS uploads_tenant_policy ON uploads;
CREATE POLICY uploads_tenant_policy ON uploads
  USING (business_id = current_setting('app.business_id', true))
  WITH CHECK (business_id = current_setting('app.business_id', true));

INSERT INTO schema_migrations (version)
VALUES (2)
ON CONFLICT (version) DO NOTHING;

COMMIT;
