-- +goose Up
-- Add foreign key constraints for core tables.
-- All orphan checks returned 0, so all constraints are safe to add.

ALTER TABLE orders
    ADD CONSTRAINT fk_orders_user_id
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE orders
    ADD CONSTRAINT fk_orders_driver_id
        FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE SET NULL;

ALTER TABLE payments
    ADD CONSTRAINT fk_payments_user_id
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE payments
    ADD CONSTRAINT fk_payments_order_id
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;

ALTER TABLE drivers
    ADD CONSTRAINT fk_drivers_user_id
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE driver_wallets
    ADD CONSTRAINT fk_driver_wallets_driver_id
        FOREIGN KEY (driver_id) REFERENCES drivers(id) ON DELETE CASCADE;

-- +goose Down
ALTER TABLE orders DROP CONSTRAINT IF EXISTS fk_orders_user_id;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS fk_orders_driver_id;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS fk_payments_user_id;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS fk_payments_order_id;
ALTER TABLE drivers DROP CONSTRAINT IF EXISTS fk_drivers_user_id;
ALTER TABLE driver_wallets DROP CONSTRAINT IF EXISTS fk_driver_wallets_driver_id;
