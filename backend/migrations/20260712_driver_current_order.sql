-- +goose Up
ALTER TABLE drivers ADD CONSTRAINT fk_drivers_current_order
    FOREIGN KEY (current_order_id) REFERENCES orders(id);

-- +goose Down
ALTER TABLE drivers DROP CONSTRAINT IF EXISTS fk_drivers_current_order;
