CREATE TABLE IF NOT EXISTS catalog_search_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gtin TEXT NOT NULL,
    provider TEXT NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    latency_ms INT NOT NULL,
    cache_hit BOOLEAN NOT NULL DEFAULT FALSE,
    found BOOLEAN NOT NULL DEFAULT FALSE,
    results_count INT NOT NULL DEFAULT 0,
    http_status INT,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_catalog_search_logs_gtin ON catalog_search_logs(gtin);
CREATE INDEX IF NOT EXISTS idx_catalog_search_logs_provider ON catalog_search_logs(provider);
INSERT INTO schema_migrations (version)
VALUES (8)
ON CONFLICT DO NOTHING;
