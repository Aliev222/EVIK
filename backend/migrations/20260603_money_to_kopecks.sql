-- +goose Up
-- +goose StatementBegin

-- Convert all monetary columns from NUMERIC(12,2) rubles to BIGINT kopecks.
-- pricing_tariffs was already BIGINT (correct).
-- commission_rules.percent stays NUMERIC(5,2) — it's a percentage, not money.

ALTER TABLE orders
    ALTER COLUMN price_total      TYPE BIGINT USING ROUND(price_total * 100)::BIGINT,
    ALTER COLUMN surcharge_amount TYPE BIGINT USING ROUND(surcharge_amount * 100)::BIGINT;
ALTER TABLE orders ALTER COLUMN price_total      SET DEFAULT 0;
ALTER TABLE orders ALTER COLUMN surcharge_amount SET DEFAULT 0;

ALTER TABLE payments
    ALTER COLUMN amount TYPE BIGINT USING ROUND(amount * 100)::BIGINT;

ALTER TABLE driver_wallets
    ALTER COLUMN available_balance TYPE BIGINT USING ROUND(available_balance * 100)::BIGINT,
    ALTER COLUMN pending_balance   TYPE BIGINT USING ROUND(pending_balance * 100)::BIGINT,
    ALTER COLUMN debt_balance      TYPE BIGINT USING ROUND(debt_balance * 100)::BIGINT;
ALTER TABLE driver_wallets ALTER COLUMN available_balance SET DEFAULT 0;
ALTER TABLE driver_wallets ALTER COLUMN pending_balance   SET DEFAULT 0;
ALTER TABLE driver_wallets ALTER COLUMN debt_balance      SET DEFAULT 0;

ALTER TABLE wallet_transactions
    ALTER COLUMN amount TYPE BIGINT USING ROUND(amount * 100)::BIGINT;

ALTER TABLE payouts
    ALTER COLUMN amount TYPE BIGINT USING ROUND(amount * 100)::BIGINT;

ALTER TABLE subscriptions
    ALTER COLUMN amount TYPE BIGINT USING ROUND(amount * 100)::BIGINT;

ALTER TABLE refunds
    ALTER COLUMN amount TYPE BIGINT USING ROUND(amount * 100)::BIGINT;

-- Remove conversion functions — no longer needed when all money is in kopecks.
DROP FUNCTION IF EXISTS cents_to_rub(BIGINT);
DROP FUNCTION IF EXISTS rub_to_cents(NUMERIC);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

CREATE OR REPLACE FUNCTION cents_to_rub(cents BIGINT)
RETURNS NUMERIC AS $$
	SELECT ROUND((cents::NUMERIC / 100), 2);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION rub_to_cents(amount NUMERIC)
RETURNS BIGINT AS $$
	SELECT ROUND(amount * 100)::BIGINT;
$$ LANGUAGE SQL IMMUTABLE;

ALTER TABLE orders
    ALTER COLUMN price_total      TYPE NUMERIC(12,2) USING ROUND(price_total::NUMERIC / 100, 2),
    ALTER COLUMN surcharge_amount TYPE NUMERIC(12,2) USING ROUND(surcharge_amount::NUMERIC / 100, 2);
ALTER TABLE orders ALTER COLUMN price_total      SET DEFAULT 0;
ALTER TABLE orders ALTER COLUMN surcharge_amount SET DEFAULT 0;

ALTER TABLE payments
    ALTER COLUMN amount TYPE NUMERIC(12,2) USING ROUND(amount::NUMERIC / 100, 2);

ALTER TABLE driver_wallets
    ALTER COLUMN available_balance TYPE NUMERIC(12,2) USING ROUND(available_balance::NUMERIC / 100, 2),
    ALTER COLUMN pending_balance   TYPE NUMERIC(12,2) USING ROUND(pending_balance::NUMERIC / 100, 2),
    ALTER COLUMN debt_balance      TYPE NUMERIC(12,2) USING ROUND(debt_balance::NUMERIC / 100, 2);
ALTER TABLE driver_wallets ALTER COLUMN available_balance SET DEFAULT 0;
ALTER TABLE driver_wallets ALTER COLUMN pending_balance   SET DEFAULT 0;
ALTER TABLE driver_wallets ALTER COLUMN debt_balance      SET DEFAULT 0;

ALTER TABLE wallet_transactions
    ALTER COLUMN amount TYPE NUMERIC(12,2) USING ROUND(amount::NUMERIC / 100, 2);

ALTER TABLE payouts
    ALTER COLUMN amount TYPE NUMERIC(12,2) USING ROUND(amount::NUMERIC / 100, 2);

ALTER TABLE subscriptions
    ALTER COLUMN amount TYPE NUMERIC(12,2) USING ROUND(amount::NUMERIC / 100, 2);

ALTER TABLE refunds
    ALTER COLUMN amount TYPE NUMERIC(12,2) USING ROUND(amount::NUMERIC / 100, 2);

-- +goose StatementEnd
