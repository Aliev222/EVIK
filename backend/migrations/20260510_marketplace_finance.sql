CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION cents_to_rub(cents BIGINT)
RETURNS NUMERIC AS $$
	SELECT ROUND((cents::NUMERIC / 100), 2);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION rub_to_cents(amount NUMERIC)
RETURNS BIGINT AS $$
	SELECT ROUND(amount * 100)::BIGINT;
$$ LANGUAGE SQL IMMUTABLE;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS price_total NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'cash';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS financial_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS financially_completed_at TIMESTAMPTZ;

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
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_provider_payment_id ON payments (provider, provider_payment_id) WHERE provider_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payments_order_id_created_at ON payments (order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_user_id_created_at ON payments (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status_created_at ON payments (status, created_at DESC);

CREATE TABLE IF NOT EXISTS payment_methods (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	brand TEXT NOT NULL,
	last4 TEXT NOT NULL,
	exp_month INTEGER NOT NULL,
	exp_year INTEGER NOT NULL,
	holder TEXT NOT NULL,
	is_default BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'yookassa';
ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS provider_payment_method_id TEXT;
ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS provider_payment_id TEXT;
ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
CREATE INDEX IF NOT EXISTS idx_payment_methods_user_id ON payment_methods (user_id, is_default DESC, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_methods_provider_method_id ON payment_methods (provider, provider_payment_method_id) WHERE provider_payment_method_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_payment_methods_provider_payment_id ON payment_methods (provider_payment_id) WHERE provider_payment_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS driver_wallets (
	id TEXT PRIMARY KEY,
	driver_id TEXT NOT NULL UNIQUE,
	available_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
	pending_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
	debt_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
	currency TEXT NOT NULL DEFAULT 'RUB',
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_wallets_driver_id_unique ON driver_wallets (driver_id);

CREATE TABLE IF NOT EXISTS wallet_transactions (
	id TEXT PRIMARY KEY,
	wallet_id TEXT NOT NULL REFERENCES driver_wallets(id),
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
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_driver_created_at ON wallet_transactions (driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_pending_release ON wallet_transactions (type, status, available_after) WHERE type = 'order_income' AND status = 'pending';
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_order_id ON wallet_transactions (order_id);

CREATE TABLE IF NOT EXISTS payouts (
	id TEXT PRIMARY KEY,
	driver_id TEXT NOT NULL,
	wallet_id TEXT NOT NULL REFERENCES driver_wallets(id),
	provider TEXT NOT NULL,
	provider_payout_id TEXT,
	amount NUMERIC(12,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	status TEXT NOT NULL,
	failure_reason TEXT,
	idempotency_key TEXT NOT NULL DEFAULT '',
	paid_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE payouts ADD COLUMN IF NOT EXISTS idempotency_key TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_payouts_driver_created_at ON payouts (driver_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_provider_payout_id ON payouts (provider, provider_payout_id) WHERE provider_payout_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_idempotency_key ON payouts (idempotency_key) WHERE idempotency_key <> '';

CREATE TABLE IF NOT EXISTS driver_payout_methods (
	id TEXT PRIMARY KEY,
	driver_id TEXT NOT NULL,
	provider_recipient_id TEXT NOT NULL,
	type TEXT NOT NULL,
	masked_value TEXT NOT NULL,
	is_default BOOLEAN NOT NULL DEFAULT FALSE,
	status TEXT NOT NULL DEFAULT 'active',
	created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_payout_methods_driver_default ON driver_payout_methods (driver_id, is_default DESC, created_at DESC);

CREATE TABLE IF NOT EXISTS subscriptions (
	id TEXT PRIMARY KEY,
	driver_id TEXT NOT NULL,
	plan_id TEXT NOT NULL,
	payment_id TEXT NOT NULL UNIQUE REFERENCES payments(id),
	amount NUMERIC(12,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	status TEXT NOT NULL,
	starts_at TIMESTAMPTZ,
	ends_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

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

CREATE TABLE IF NOT EXISTS refunds (
	id TEXT PRIMARY KEY,
	payment_id TEXT NOT NULL REFERENCES payments(id),
	provider_refund_id TEXT,
	amount NUMERIC(12,2) NOT NULL,
	currency TEXT NOT NULL DEFAULT 'RUB',
	reason TEXT NOT NULL,
	status TEXT NOT NULL,
	idempotency_key TEXT NOT NULL UNIQUE,
	created_at TIMESTAMPTZ NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS payment_webhooks (
	id TEXT PRIMARY KEY,
	provider TEXT NOT NULL,
	event_type TEXT NOT NULL,
	payload JSONB NOT NULL,
	processed BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL,
	processed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS finance_reports_exports (
	id TEXT PRIMARY KEY,
	report_type TEXT NOT NULL,
	status TEXT NOT NULL,
	file_url TEXT,
	requested_by TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS wallet_transaction_locks (
	idempotency_key TEXT PRIMARY KEY,
	created_at TIMESTAMPTZ NOT NULL
);

INSERT INTO commission_rules (id, name, percent, currency, is_active, starts_at, created_at)
VALUES ('tow-truck-default-commission', 'Tow Truck default marketplace commission', 15.00, 'RUB', TRUE, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET percent = EXCLUDED.percent, is_active = TRUE;
