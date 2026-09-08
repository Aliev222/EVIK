-- +goose Up
CREATE TABLE order_trip_meters (
    order_id TEXT PRIMARY KEY REFERENCES orders(id),
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    distance_meters DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (distance_meters >= 0),
    complete BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE order_route_quotes (
    id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL REFERENCES orders(id),
    user_id TEXT NOT NULL,
    snapshot_updated_at TIMESTAMPTZ NOT NULL,
    payload JSONB NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    applied_at TIMESTAMPTZ
);
CREATE INDEX order_route_quotes_order_idx ON order_route_quotes(order_id);

-- +goose Down
DROP TABLE order_route_quotes;
DROP TABLE order_trip_meters;
