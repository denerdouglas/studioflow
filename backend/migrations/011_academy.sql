BEGIN;

CREATE TABLE IF NOT EXISTS academy_partners (
    id UUID PRIMARY KEY,
    slug VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending_configuration',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS academy_categories (
    id UUID PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS academy_courses (
    id UUID PRIMARY KEY,
    external_id VARCHAR(100),
    title VARCHAR(200) NOT NULL,
    short_description TEXT,
    instructor VARCHAR(100),
    image_url VARCHAR(255),
    price_cents INTEGER,
    currency VARCHAR(3),
    partner_id UUID REFERENCES academy_partners(id),
    category_id UUID REFERENCES academy_categories(id),
    source_type VARCHAR(50) NOT NULL,
    publication_status VARCHAR(50) NOT NULL DEFAULT 'draft',
    rating NUMERIC(3,2),
    reviews_count INTEGER,
    redirect_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS academy_campaigns (
    id UUID PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    partner_id UUID NOT NULL REFERENCES academy_partners(id),
    course_id UUID REFERENCES academy_courses(id),
    base_url TEXT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS academy_clicks (
    click_id VARCHAR(100) PRIMARY KEY,
    course_id UUID NOT NULL REFERENCES academy_courses(id),
    partner_id UUID NOT NULL REFERENCES academy_partners(id),
    campaign_id UUID REFERENCES academy_campaigns(id),
    destination_url TEXT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'created',
    failure_reason TEXT,
    origin VARCHAR(100),
    business_id UUID,
    user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    redirected_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS academy_search_logs (
    id UUID PRIMARY KEY,
    query VARCHAR(200),
    category_id UUID REFERENCES academy_categories(id),
    results_count INTEGER NOT NULL,
    business_id UUID,
    user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS academy_admin_audit (
    id UUID PRIMARY KEY,
    admin_user_id UUID NOT NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(100) NOT NULL,
    resource_id UUID NOT NULL,
    old_data JSONB,
    new_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_academy_courses_partner_id
    ON academy_courses(partner_id);

CREATE INDEX IF NOT EXISTS idx_academy_courses_category_id
    ON academy_courses(category_id);

CREATE INDEX IF NOT EXISTS idx_academy_courses_publication_status
    ON academy_courses(publication_status);

CREATE INDEX IF NOT EXISTS idx_academy_courses_source_type
    ON academy_courses(source_type);

CREATE INDEX IF NOT EXISTS idx_academy_clicks_course_id
    ON academy_clicks(course_id);

CREATE INDEX IF NOT EXISTS idx_academy_clicks_partner_id
    ON academy_clicks(partner_id);

CREATE INDEX IF NOT EXISTS idx_academy_clicks_created_at
    ON academy_clicks(created_at);

CREATE INDEX IF NOT EXISTS idx_academy_search_logs_created_at
    ON academy_search_logs(created_at);

INSERT INTO schema_migrations (version)
VALUES (11)
ON CONFLICT (version) DO NOTHING;

COMMIT;