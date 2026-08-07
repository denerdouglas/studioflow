-- UP
BEGIN;

-- Ajustes na tabela sync_records se necessário (PostgreSQL lida com os dados dinâmicos das novas entidades através de sync_records)
-- A maioria das novas tabelas no backend não requer schema físico estruturado se usarem a infra de sync, 
-- MAS, se houver tabelas relacionais dedicadas, adicionaremos as colunas aqui.

-- Como a arquitetura do StudioFlow no backend depende majoritariamente da generic 'sync_records' (com payload JSONB),
-- vamos garantir que a constraint de schema permita as novas keys, se houver schemas rígidos validados via plpgsql.

-- Criando tabelas auxiliares estruturadas (quando aplicável no backend):
CREATE TABLE IF NOT EXISTS schema_migrations_backend (
    version INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    checksum VARCHAR(255),
    applied_at TIMESTAMP DEFAULT NOW()
);

-- Exemplo: Adicionando colunas de rastreamento no backend para outbound_messages (WhatsApp fila)
-- Se outbound_messages existir:
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'outbound_messages') THEN
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS status_real VARCHAR(50);
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS provider_message_id VARCHAR(255);
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS conversation_id VARCHAR(255);
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS template_id VARCHAR(255);
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS attempt SMALLINT DEFAULT 0;
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS latencia INTEGER;
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS erro TEXT;
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS timestamp_meta TIMESTAMP;
        ALTER TABLE outbound_messages ADD COLUMN IF NOT EXISTS timestamp_local TIMESTAMP;
    END IF;
END
$$;

COMMIT;

-- DOWN
-- Rollback deve ser apenas logico ou revertivel em homologacao
-- BEGIN;
-- DO $$
-- BEGIN
--     IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'outbound_messages') THEN
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS status_real;
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS provider_message_id;
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS conversation_id;
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS template_id;
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS attempt;
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS latencia;
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS erro;
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS timestamp_meta;
--         ALTER TABLE outbound_messages DROP COLUMN IF EXISTS timestamp_local;
--     END IF;
-- END
-- $$;
-- COMMIT;
