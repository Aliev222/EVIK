-- +goose Up
ALTER TABLE orders
    ALTER COLUMN surcharge_amount TYPE NUMERIC(12,2)
    USING ROUND(surcharge_amount / 100.0, 2);

-- +goose Down
ALTER TABLE orders
    ALTER COLUMN surcharge_amount TYPE INTEGER
    USING ROUND(surcharge_amount * 100)::INTEGER;
