BEGIN;

-- Migration 016: Ativos Imobilizados
-- Sem FK para estoque, dado que o sincronismo de `estoque` ocorre de forma generica via `sync_records`.

CREATE TABLE IF NOT EXISTS ativos_imobilizados (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    estoque_id TEXT NOT NULL,
    data_aquisicao TIMESTAMP WITH TIME ZONE,
    valor_aquisicao NUMERIC(15,4) DEFAULT 0 CHECK (valor_aquisicao >= 0),
    numero_serie VARCHAR(255),
    patrimonio VARCHAR(255),
    localizacao VARCHAR(255),
    condicao VARCHAR(100),
    garantia_ate TIMESTAMP WITH TIME ZONE,
    observacoes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    created_by TEXT,
    updated_by TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ativos_imob_estoque_uniq 
ON ativos_imobilizados (business_id, estoque_id) 
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_ativos_imob_business 
ON ativos_imobilizados (business_id);

INSERT INTO schema_migrations(version) VALUES (16) ON CONFLICT DO NOTHING;

COMMIT;
