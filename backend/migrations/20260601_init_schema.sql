-- +goose Up
-- +goose StatementBegin

-- ============================================================
-- EXTENSION
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- FUNCTIONS
-- ============================================================
CREATE OR REPLACE FUNCTION cents_to_rub(cents BIGINT)
RETURNS NUMERIC AS $$
	SELECT ROUND((cents::NUMERIC / 100), 2);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION rub_to_cents(amount NUMERIC)
RETURNS BIGINT AS $$
	SELECT ROUND(amount * 100)::BIGINT;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION update_driver_rating_stats() RETURNS TRIGGER AS $$
BEGIN
    UPDATE drivers
    SET
        rating_average = COALESCE((
            SELECT ROUND(AVG(stars)::numeric, 2)
            FROM driver_reviews
            WHERE driver_id = COALESCE(NEW.driver_id, OLD.driver_id)
        ), 0.00),
        rating_count = COALESCE((
            SELECT COUNT(*)
            FROM driver_reviews
            WHERE driver_id = COALESCE(NEW.driver_id, OLD.driver_id)
        ), 0),
        total_orders = COALESCE((
            SELECT COUNT(*)
            FROM orders
            WHERE driver_id = COALESCE(NEW.driver_id, OLD.driver_id)
            AND status = 'completed'
        ), 0)
    WHERE user_id = COALESCE(NEW.driver_id, OLD.driver_id);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_driver_vehicle_data() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
        UPDATE drivers
        SET
            vehicle_plate = NEW.vehicle_plate,
            vehicle_model = NEW.vehicle_model,
            vehicle_type = NEW.vehicle_type
        WHERE user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- TABLES (ordered by FK dependencies)
-- ============================================================

-- 1. users
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    phone TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL,
    password_hash TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    fns_full_name TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- 2. user_refresh_sessions
CREATE TABLE IF NOT EXISTS user_refresh_sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- 3. phone_otps
CREATE TABLE IF NOT EXISTS phone_otps (
    id TEXT PRIMARY KEY,
    phone TEXT NOT NULL,
    role TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL
);

-- 4. service_areas
CREATE TABLE IF NOT EXISTS service_areas (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    slug VARCHAR(255) NOT NULL UNIQUE,
    min_lat DOUBLE PRECISION NOT NULL,
    min_lng DOUBLE PRECISION NOT NULL,
    max_lat DOUBLE PRECISION NOT NULL,
    max_lng DOUBLE PRECISION NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- 5. drivers
CREATE TABLE IF NOT EXISTS drivers (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    status TEXT NOT NULL,
    current_order_id TEXT,
    last_seen_at TIMESTAMPTZ NOT NULL,
    vehicle_plate TEXT,
    vehicle_model TEXT,
    vehicle_type TEXT,
    rating_average DECIMAL(3,2) DEFAULT 0.00,
    rating_count INTEGER DEFAULT 0,
    total_orders INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- 6. driver_tax_profiles
CREATE TABLE IF NOT EXISTS driver_tax_profiles (
    driver_id TEXT PRIMARY KEY REFERENCES drivers(id),
    inn TEXT NOT NULL,
    taxpayer_type TEXT NOT NULL,
    verification_status TEXT NOT NULL DEFAULT 'pending',
    npd_access_token TEXT,
    npd_refresh_token TEXT,
    npd_token_expires_at TIMESTAMPTZ,
    npd_connected_at TIMESTAMPTZ,
    npd_revoked_at TIMESTAMPTZ,
    npd_connection_status TEXT NOT NULL DEFAULT 'not_connected',
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT driver_tax_profiles_inn_format CHECK (inn ~ '^[0-9]{10}([0-9]{2})?$'),
    CONSTRAINT driver_tax_profiles_taxpayer_type CHECK (taxpayer_type IN ('self_employed', 'ip')),
    CONSTRAINT driver_tax_profiles_status CHECK (verification_status IN ('pending', 'verified', 'rejected')),
    CONSTRAINT driver_tax_profiles_npd_status CHECK (npd_connection_status IN ('not_connected', 'connected', 'revoked', 'error'))
);

-- 7. user_device_tokens
CREATE TABLE IF NOT EXISTS user_device_tokens (
    fcm_token TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('client', 'driver', 'admin')),
    platform TEXT NOT NULL DEFAULT '',
    app_version TEXT NOT NULL DEFAULT '',
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- 8. orders
CREATE TABLE IF NOT EXISTS orders (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    driver_id TEXT,
    pickup_lat DOUBLE PRECISION NOT NULL,
    pickup_lng DOUBLE PRECISION NOT NULL,
    dropoff_lat DOUBLE PRECISION NOT NULL,
    dropoff_lng DOUBLE PRECISION NOT NULL,
    tow_truck_type TEXT NOT NULL DEFAULT 'standard',
    status TEXT NOT NULL,
    price_total NUMERIC(12,2) NOT NULL DEFAULT 0,
    payment_method TEXT NOT NULL DEFAULT 'cash',
    financial_status TEXT NOT NULL DEFAULT 'pending',
    financially_completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    cancelled_at TIMESTAMPTZ,
    is_expanded BOOLEAN NOT NULL DEFAULT FALSE,
    expanded_at TIMESTAMPTZ,
    cancel_reason TEXT,
    is_cross_city BOOLEAN NOT NULL DEFAULT FALSE,
    surcharge_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    surcharge_percent INTEGER NOT NULL DEFAULT 0,
    pickup_address TEXT,
    dropoff_address TEXT,
    city_id TEXT REFERENCES service_areas(id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE SET NULL
);

-- 9. driver_reviews
CREATE TABLE IF NOT EXISTS driver_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id TEXT NOT NULL,
    driver_id TEXT NOT NULL,
    client_id TEXT NOT NULL,
    stars INTEGER NOT NULL CHECK (stars >= 1 AND stars <= 5),
    comment TEXT DEFAULT '',
    is_hidden BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (driver_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (client_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

-- 10. payment_methods
CREATE TABLE IF NOT EXISTS payment_methods (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'yookassa',
    provider_payment_method_id TEXT,
    provider_payment_id TEXT,
    brand TEXT NOT NULL,
    last4 TEXT NOT NULL,
    exp_month INTEGER NOT NULL,
    exp_year INTEGER NOT NULL,
    holder TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL
);

-- 11. payments
CREATE TABLE IF NOT EXISTS payments (
    id TEXT PRIMARY KEY,
    order_id TEXT,
    driver_id TEXT,
    user_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_payment_id TEXT,
    payment_method TEXT NOT NULL,
    purpose TEXT NOT NULL DEFAULT 'order',
    amount NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'RUB',
    status TEXT NOT NULL,
    confirmation_url TEXT,
    idempotency_key TEXT NOT NULL UNIQUE,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

-- 12. driver_wallets
CREATE TABLE IF NOT EXISTS driver_wallets (
    id TEXT PRIMARY KEY,
    driver_id TEXT NOT NULL UNIQUE,
    available_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
    pending_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
    debt_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'RUB',
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE CASCADE
);

-- 13. payouts
CREATE TABLE IF NOT EXISTS payouts (
    id TEXT PRIMARY KEY,
    driver_id TEXT NOT NULL,
    wallet_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_payout_id TEXT,
    amount NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'RUB',
    status TEXT NOT NULL,
    failure_reason TEXT,
    idempotency_key TEXT NOT NULL DEFAULT '',
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (wallet_id) REFERENCES driver_wallets(id),
    FOREIGN KEY (driver_id) REFERENCES drivers(id)
);

-- 14. wallet_transactions
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id TEXT PRIMARY KEY,
    wallet_id TEXT NOT NULL,
    driver_id TEXT NOT NULL,
    order_id TEXT,
    payment_id TEXT,
    payout_id TEXT,
    type TEXT NOT NULL,
    direction TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'RUB',
    status TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    idempotency_key TEXT NOT NULL UNIQUE,
    available_after TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (wallet_id) REFERENCES driver_wallets(id),
    FOREIGN KEY (order_id) REFERENCES orders(id),
    FOREIGN KEY (payment_id) REFERENCES payments(id),
    FOREIGN KEY (payout_id) REFERENCES payouts(id)
);

-- 15. driver_payout_methods
CREATE TABLE IF NOT EXISTS driver_payout_methods (
    id TEXT PRIMARY KEY,
    driver_id TEXT NOT NULL,
    provider_recipient_id TEXT NOT NULL,
    type TEXT NOT NULL,
    masked_value TEXT NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (driver_id) REFERENCES drivers(id)
);

-- 16. subscriptions
CREATE TABLE IF NOT EXISTS subscriptions (
    id TEXT PRIMARY KEY,
    driver_id TEXT NOT NULL,
    plan_id TEXT NOT NULL,
    payment_id TEXT NOT NULL UNIQUE,
    amount NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'RUB',
    status TEXT NOT NULL,
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (payment_id) REFERENCES payments(id),
    FOREIGN KEY (driver_id) REFERENCES drivers(id)
);

-- 17. refunds
CREATE TABLE IF NOT EXISTS refunds (
    id TEXT PRIMARY KEY,
    payment_id TEXT NOT NULL,
    provider_refund_id TEXT,
    amount NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'RUB',
    reason TEXT NOT NULL,
    status TEXT NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (payment_id) REFERENCES payments(id)
);

-- 18. payment_webhooks
CREATE TABLE IF NOT EXISTS payment_webhooks (
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL,
    processed_at TIMESTAMPTZ
);

-- 19. finance_reports_exports
CREATE TABLE IF NOT EXISTS finance_reports_exports (
    id TEXT PRIMARY KEY,
    report_type TEXT NOT NULL,
    status TEXT NOT NULL,
    file_url TEXT,
    requested_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ
);

-- 20. wallet_transaction_locks
CREATE TABLE IF NOT EXISTS wallet_transaction_locks (
    idempotency_key TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL
);

-- 21. pricing_tariffs
CREATE TABLE IF NOT EXISTS pricing_tariffs (
    id TEXT PRIMARY KEY,
    tow_truck_type TEXT NOT NULL,
    base_price BIGINT NOT NULL,
    price_per_km BIGINT NOT NULL,
    minimum_price BIGINT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- 22. driver_verifications
CREATE TABLE IF NOT EXISTS driver_verifications (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT NOT NULL DEFAULT '',
    city TEXT NOT NULL DEFAULT '',
    vehicle_model TEXT NOT NULL,
    vehicle_plate TEXT NOT NULL,
    vehicle_type TEXT NOT NULL,
    status TEXT NOT NULL,
    risk TEXT NOT NULL DEFAULT 'low',
    documents_json TEXT NOT NULL DEFAULT '[]',
    signals_json TEXT NOT NULL DEFAULT '[]',
    decision_reason TEXT,
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    admin_comments TEXT NOT NULL DEFAULT '',
    submitted_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

-- 23. driver_documents
CREATE TABLE IF NOT EXISTS driver_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    verification_id TEXT NOT NULL,
    document_type TEXT NOT NULL,
    storage_key TEXT NOT NULL,
    public_url TEXT NOT NULL,
    content_type TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (verification_id) REFERENCES driver_verifications(id) ON DELETE CASCADE
);

-- 24. moderation_audit_log
CREATE TABLE IF NOT EXISTS moderation_audit_log (
    id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    action TEXT NOT NULL,
    reason TEXT NOT NULL DEFAULT '',
    moderator_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);

-- 25. commission_rules
CREATE TABLE IF NOT EXISTS commission_rules (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    percent NUMERIC(5,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'RUB',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL
);

-- 26. platform_settings
CREATE TABLE IF NOT EXISTS platform_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ADDITIONAL INDEXES
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_role ON users (phone, role);
CREATE INDEX IF NOT EXISTS idx_users_role_status ON users (role, status);

CREATE INDEX IF NOT EXISTS idx_user_refresh_sessions_user_created ON user_refresh_sessions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_refresh_sessions_active_hash ON user_refresh_sessions (token_hash) WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_phone_otps_lookup ON phone_otps (phone, role, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_service_areas_active_bounds ON service_areas (is_active, min_lat, max_lat, min_lng, max_lng);
CREATE INDEX IF NOT EXISTS idx_service_areas_slug ON service_areas(slug);

CREATE INDEX IF NOT EXISTS idx_orders_status_updated_at ON orders (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_user_id_updated_at ON orders (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_driver_id_updated_at ON orders (driver_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_city_status ON orders (city_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_expansion_check ON orders (created_at) WHERE status = 'searching' AND is_expanded = FALSE;

CREATE INDEX IF NOT EXISTS idx_drivers_status_updated_at ON drivers (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_drivers_current_order_id ON drivers (current_order_id);
CREATE INDEX IF NOT EXISTS idx_drivers_rating_orders ON drivers (rating_average DESC, total_orders DESC);

CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user_role ON user_device_tokens (user_id, role) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_device_tokens_role_active ON user_device_tokens (role) WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_payment_methods_user_id ON payment_methods (user_id, is_default DESC, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_methods_provider_method_id ON payment_methods (provider, provider_payment_method_id) WHERE provider_payment_method_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_methods_provider_payment_id ON payment_methods (provider_payment_id) WHERE provider_payment_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_provider_payment_id ON payments (provider, provider_payment_id) WHERE provider_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payments_order_id_created_at ON payments (order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_user_id_created_at ON payments (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status_created_at ON payments (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_order_status ON payments (order_id, status);

CREATE INDEX IF NOT EXISTS idx_driver_wallets_driver_id ON driver_wallets (driver_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_wallets_driver_id_unique ON driver_wallets (driver_id);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_driver_created_at ON wallet_transactions (driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_pending_release ON wallet_transactions (type, status, available_after) WHERE type = 'order_income' AND status = 'pending';
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_order_id ON wallet_transactions (order_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type_created ON wallet_transactions (type, created_at);

CREATE INDEX IF NOT EXISTS idx_payouts_driver_created_at ON payouts (driver_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_provider_payout_id ON payouts (provider, provider_payout_id) WHERE provider_payout_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_idempotency_key ON payouts (idempotency_key) WHERE idempotency_key <> '';
CREATE INDEX IF NOT EXISTS idx_payouts_status_created ON payouts (status, created_at);

CREATE INDEX IF NOT EXISTS idx_driver_payout_methods_driver_default ON driver_payout_methods (driver_id, is_default DESC, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_subscriptions_driver_status ON subscriptions (driver_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status_created ON subscriptions (status, created_at);

CREATE INDEX IF NOT EXISTS idx_refunds_payment_id ON refunds (payment_id);

CREATE INDEX IF NOT EXISTS idx_pricing_tariffs_type_active ON pricing_tariffs (tow_truck_type, is_active);

CREATE INDEX IF NOT EXISTS idx_driver_verifications_status_submitted_at ON driver_verifications (status, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_verifications_user_id ON driver_verifications (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_verifications_user_id_unique ON driver_verifications (user_id);

CREATE INDEX IF NOT EXISTS idx_driver_documents_verification_type ON driver_documents (verification_id, document_type);

CREATE INDEX IF NOT EXISTS idx_moderation_audit_entity_created_at ON moderation_audit_log (entity_type, entity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_driver_tax_profiles_status ON driver_tax_profiles (verification_status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_tax_profiles_npd_status ON driver_tax_profiles (npd_connection_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_driver_reviews_order_id ON driver_reviews (order_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_reviews_order_id_unique ON driver_reviews (order_id);
CREATE INDEX IF NOT EXISTS idx_driver_reviews_driver_stars ON driver_reviews (driver_id, stars);
CREATE INDEX IF NOT EXISTS idx_driver_reviews_created ON driver_reviews (created_at DESC);

-- ============================================================
-- TRIGGERS (after tables and functions)
-- ============================================================
DROP TRIGGER IF EXISTS trigger_update_driver_rating_stats ON driver_reviews;
CREATE TRIGGER trigger_update_driver_rating_stats
    AFTER INSERT OR UPDATE OR DELETE ON driver_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_driver_rating_stats();

DROP TRIGGER IF EXISTS trigger_sync_driver_vehicle_data ON driver_verifications;
CREATE TRIGGER trigger_sync_driver_vehicle_data
    AFTER UPDATE ON driver_verifications
    FOR EACH ROW
    WHEN (NEW.status = 'approved')
    EXECUTE FUNCTION sync_driver_vehicle_data();

-- +goose StatementEnd

-- +goose Down
-- ВНИМАНИЕ: деструктивно. Не запускать в проде.
-- TODO: перед запуском заменить на явные DROP TABLE или запретить откат.
-- +goose StatementBegin
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
-- +goose StatementEnd
