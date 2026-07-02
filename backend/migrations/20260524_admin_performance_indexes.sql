-- +goose Up

-- Fix admin dashboard performance: COUNT(DISTINCT user_id)
-- from orders scans entire table
CREATE INDEX IF NOT EXISTS idx_orders_user_id
  ON orders (user_id);

-- Subscriptions table has NO indexes at all
-- Admin filters by status frequently
CREATE INDEX IF NOT EXISTS idx_subscriptions_status_created
  ON subscriptions (status, created_at);

-- Payouts filtered by status with no index
CREATE INDEX IF NOT EXISTS idx_payouts_status_created
  ON payouts (status, created_at);

-- wallet_transactions KPI query needs (type, created_at)
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type_created
  ON wallet_transactions (type, created_at);

-- +goose Down
DROP INDEX IF EXISTS idx_orders_user_id;
DROP INDEX IF EXISTS idx_subscriptions_status_created;
DROP INDEX IF EXISTS idx_payouts_status_created;
DROP INDEX IF EXISTS idx_wallet_transactions_type_created;
