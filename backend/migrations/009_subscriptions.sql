BEGIN;

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_product_id VARCHAR NOT NULL,
    base_plan_id VARCHAR NOT NULL,
    offer_id VARCHAR,
    purchase_token_hash VARCHAR UNIQUE NOT NULL,
    purchase_token_encrypted TEXT NOT NULL,
    linked_purchase_token_hash VARCHAR,
    package_name VARCHAR NOT NULL,
    user_id UUID NOT NULL,
    business_id UUID NOT NULL,
    platform VARCHAR NOT NULL,
    state VARCHAR NOT NULL,
    trial_end_at TIMESTAMPTZ,
    current_period_end_at TIMESTAMPTZ,
    auto_renew_enabled BOOLEAN NOT NULL DEFAULT false,
    founder_price_locked BOOLEAN NOT NULL DEFAULT false,
    acquired_price_micros BIGINT,
    currency_code VARCHAR(3),
    last_verified_at TIMESTAMPTZ,
    verification_source VARCHAR NOT NULL,
    acknowledged_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexing for frequent searches
CREATE INDEX idx_subscriptions_business_id ON subscriptions(business_id);
CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_state ON subscriptions(state);
CREATE INDEX idx_subscriptions_current_period_end_at ON subscriptions(current_period_end_at);
CREATE INDEX idx_subscriptions_purchase_token_hash ON subscriptions(purchase_token_hash);

-- Ensure a business doesn't have multiple overlapping 'active', 'trial', or 'grace_period' subscriptions
-- EXCLUDE constraints require btree_gist extension for partial exclusion based on text, 
-- or we can use a partial unique index. A partial UNIQUE index on business_id where state is active is simpler:
-- Wait, a business can have multiple active if one is being replaced, but linkedPurchaseToken handles that.
-- "Garantir no banco que não existam duas assinaturas simultaneamente concedendo entitlement ativo ao mesmo business_id"
CREATE UNIQUE INDEX idx_unique_active_subscription_per_business 
ON subscriptions(business_id) 
WHERE state IN ('active', 'trial', 'grace_period');

-- Create subscription events table
CREATE TABLE subscription_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id VARCHAR UNIQUE, -- Used to deduplicate RTDN
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    event_type VARCHAR NOT NULL,
    payload JSONB NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subscription_events_sub_id ON subscription_events(subscription_id);

-- Update schema_migrations
INSERT INTO schema_migrations (version, applied_at) VALUES ('009_subscriptions', NOW());

COMMIT;
