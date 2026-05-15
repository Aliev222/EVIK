-- +goose Up
-- Driver Reviews and Ratings System
-- Creates table to store client reviews for drivers and supports rating aggregation
-- This addresses P0.2 Real Driver Data Binding requirement

-- Driver reviews: stores individual reviews from clients for completed orders
CREATE TABLE IF NOT EXISTS driver_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id TEXT NOT NULL,
    driver_id TEXT NOT NULL,
    client_id TEXT NOT NULL,
    stars INTEGER NOT NULL CHECK (stars >= 1 AND stars <= 5),
    comment TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (driver_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (client_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

-- Ensure only one review per order
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_reviews_order_id
    ON driver_reviews (order_id);

-- Index for aggregating ratings by driver
CREATE INDEX IF NOT EXISTS idx_driver_reviews_driver_stars
    ON driver_reviews (driver_id, stars);

-- Index for querying recent reviews
CREATE INDEX IF NOT EXISTS idx_driver_reviews_created
    ON driver_reviews (created_at DESC);

-- Add vehicle data fields to drivers table for denormalized quick access
-- This avoids complex joins for common driver profile queries
ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS vehicle_plate TEXT,
    ADD COLUMN IF NOT EXISTS vehicle_model TEXT,
    ADD COLUMN IF NOT EXISTS vehicle_type TEXT,
    ADD COLUMN IF NOT EXISTS rating_average DECIMAL(3,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS rating_count INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_orders INTEGER DEFAULT 0;

-- Create index for driver profile queries
CREATE INDEX IF NOT EXISTS idx_drivers_rating_orders
    ON drivers (rating_average DESC, total_orders DESC);

-- Add constraint for vehicle types
ALTER TABLE drivers
    DROP CONSTRAINT IF EXISTS drivers_vehicle_type_check;

ALTER TABLE drivers
    ADD CONSTRAINT drivers_vehicle_type_check
    CHECK (vehicle_type IS NULL OR vehicle_type IN ('winch', 'platform', 'manipulator'));

-- Function to update driver rating aggregation when reviews are added/updated
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION update_driver_rating_stats() RETURNS TRIGGER AS $$
BEGIN
    -- Update rating statistics for the affected driver
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
-- +goose StatementEnd

-- Trigger to automatically update driver stats when reviews change
DROP TRIGGER IF EXISTS trigger_update_driver_rating_stats ON driver_reviews;
CREATE TRIGGER trigger_update_driver_rating_stats
    AFTER INSERT OR UPDATE OR DELETE ON driver_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_driver_rating_stats();

-- Function to sync vehicle data from verifications to drivers table
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION sync_driver_vehicle_data() RETURNS TRIGGER AS $$
BEGIN
    -- When a driver verification is approved, sync vehicle data to drivers table
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
-- +goose StatementEnd

-- Trigger to sync vehicle data when verification is approved
-- Note: This assumes driver_verifications view has vehicle fields
DROP TRIGGER IF EXISTS trigger_sync_driver_vehicle_data ON driver_verifications;
CREATE TRIGGER trigger_sync_driver_vehicle_data
    AFTER UPDATE ON driver_verifications
    FOR EACH ROW
    WHEN (NEW.status = 'approved')
    EXECUTE FUNCTION sync_driver_vehicle_data();

-- Initialize rating stats for existing drivers (run once)
UPDATE drivers
SET
    rating_average = COALESCE((
        SELECT ROUND(AVG(stars)::numeric, 2)
        FROM driver_reviews
        WHERE driver_id = drivers.user_id
    ), 0.00),
    rating_count = COALESCE((
        SELECT COUNT(*)
        FROM driver_reviews
        WHERE driver_id = drivers.user_id
    ), 0),
    total_orders = COALESCE((
        SELECT COUNT(*)
        FROM orders
        WHERE driver_id = drivers.user_id
        AND status = 'completed'
    ), 0)
WHERE rating_average IS NULL;

-- +goose Down
-- not implemented (forward-only migration)
SELECT 1;