-- Driver onboarding state and explicit offer acceptance.
CREATE TABLE IF NOT EXISTS driver_offers (
    id TEXT PRIMARY KEY,
    version TEXT NOT NULL UNIQUE,
    document_hash TEXT NOT NULL,
    document_url TEXT NOT NULL,
    is_current BOOLEAN NOT NULL DEFAULT FALSE,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL,
    published_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS driver_offer_acceptances (
    id TEXT PRIMARY KEY,
    driver_id TEXT NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    offer_id TEXT NOT NULL REFERENCES driver_offers(id),
    version TEXT NOT NULL,
    document_hash TEXT NOT NULL,
    accepted_at TIMESTAMPTZ NOT NULL,
    acceptance_method TEXT NOT NULL,
    UNIQUE (driver_id, offer_id)
);

CREATE TABLE IF NOT EXISTS driver_settlement_connections (
    driver_id TEXT PRIMARY KEY REFERENCES drivers(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'not_started'
        CHECK (status IN ('not_started', 'pending', 'approved', 'rejected', 'suspended')),
    external_executor_id TEXT,
    external_account_id TEXT,
    checked_at TIMESTAMPTZ,
    rejection_reason TEXT,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_offers_current ON driver_offers (is_current, is_required, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_offer_acceptances_driver ON driver_offer_acceptances (driver_id, accepted_at DESC);

ALTER TABLE driver_tax_profiles
    ADD COLUMN IF NOT EXISTS verification_source TEXT NOT NULL DEFAULT 'driver_declared'
        CHECK (verification_source IN ('driver_declared', 'manual_admin', 'provider_verified')),
    ADD COLUMN IF NOT EXISTS verified_by TEXT,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verification_reason TEXT;
