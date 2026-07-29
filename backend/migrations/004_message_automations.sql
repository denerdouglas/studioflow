BEGIN;

CREATE TABLE IF NOT EXISTS outbound_messages (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  dedupe_key TEXT NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('whatsapp','email','app')),
  destination TEXT NOT NULL,
  body TEXT NOT NULL,
  scheduled_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN (
      'queued','sending','retry','sent','delivered','read','error','cancelled'
    )),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ,
  external_id TEXT,
  appointment_id TEXT,
  client_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_error TEXT,
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (business_id, dedupe_key)
);

CREATE INDEX IF NOT EXISTS idx_outbound_due
  ON outbound_messages(status, scheduled_at, next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_outbound_business_history
  ON outbound_messages(business_id, scheduled_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_outbound_external
  ON outbound_messages(external_id) WHERE external_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS message_delivery_attempts (
  id BIGSERIAL PRIMARY KEY,
  message_id TEXT NOT NULL REFERENCES outbound_messages(id) ON DELETE CASCADE,
  attempt_number INTEGER NOT NULL,
  status TEXT NOT NULL,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_delivery_attempt_message
  ON message_delivery_attempts(message_id, attempt_number);

DROP POLICY IF EXISTS sync_records_tenant_policy ON sync_records;
CREATE POLICY sync_records_tenant_policy ON sync_records
  USING (
    business_id = current_setting('app.business_id', true)
    OR current_setting('app.automation_worker', true) = '1'
  )
  WITH CHECK (
    business_id = current_setting('app.business_id', true)
    OR current_setting('app.automation_worker', true) = '1'
  );
ALTER TABLE outbound_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_delivery_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS outbound_messages_tenant_policy ON outbound_messages;
CREATE POLICY outbound_messages_tenant_policy ON outbound_messages
  USING (
    business_id = current_setting('app.business_id', true)
    OR current_setting('app.automation_worker', true) = '1'
  )
  WITH CHECK (
    business_id = current_setting('app.business_id', true)
    OR current_setting('app.automation_worker', true) = '1'
  );

DROP POLICY IF EXISTS delivery_attempts_tenant_policy
  ON message_delivery_attempts;
CREATE POLICY delivery_attempts_tenant_policy ON message_delivery_attempts
  USING (
    EXISTS (
      SELECT 1 FROM outbound_messages m
      WHERE m.id = message_id
        AND (
          m.business_id = current_setting('app.business_id', true)
          OR current_setting('app.automation_worker', true) = '1'
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM outbound_messages m
      WHERE m.id = message_id
        AND (
          m.business_id = current_setting('app.business_id', true)
          OR current_setting('app.automation_worker', true) = '1'
        )
    )
  );

INSERT INTO schema_migrations(version)
VALUES (4)
ON CONFLICT(version) DO NOTHING;

COMMIT;
