-- Migration to add tow_truck_type column to orders table
-- Run this on your PostgreSQL database

-- Add the tow_truck_type column
ALTER TABLE orders ADD COLUMN tow_truck_type VARCHAR(20) NOT NULL DEFAULT 'winch';

-- Add check constraint for valid values
ALTER TABLE orders ADD CONSTRAINT orders_tow_truck_type_check
    CHECK (tow_truck_type IN ('winch', 'platform', 'manipulator'));

-- Create index for performance
CREATE INDEX idx_orders_tow_truck_type ON orders(tow_truck_type);

-- Update existing records (optional - set default)
UPDATE orders SET tow_truck_type = 'winch' WHERE tow_truck_type IS NULL;