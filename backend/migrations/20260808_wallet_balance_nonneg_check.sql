-- +goose Up
ALTER TABLE driver_wallets ADD CONSTRAINT driver_wallets_available_nonneg CHECK (available_balance >= 0);
ALTER TABLE driver_wallets ADD CONSTRAINT driver_wallets_pending_nonneg CHECK (pending_balance >= 0);
ALTER TABLE driver_wallets ADD CONSTRAINT driver_wallets_debt_nonneg CHECK (debt_balance >= 0);

-- +goose Down
ALTER TABLE driver_wallets DROP CONSTRAINT IF EXISTS driver_wallets_available_nonneg;
ALTER TABLE driver_wallets DROP CONSTRAINT IF EXISTS driver_wallets_pending_nonneg;
ALTER TABLE driver_wallets DROP CONSTRAINT IF EXISTS driver_wallets_debt_nonneg;