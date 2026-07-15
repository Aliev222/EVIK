-- +goose Up
CREATE TABLE order_offers (
    id          TEXT PRIMARY KEY,
    order_id    TEXT NOT NULL REFERENCES orders(id),
    driver_id   TEXT NOT NULL REFERENCES drivers(id),
    round       INT  NOT NULL DEFAULT 1,
    distance_km NUMERIC(6,2),
    offered_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL,
    outcome     TEXT,
    resolved_at TIMESTAMPTZ,
    UNIQUE (order_id, driver_id, round)
);

CREATE INDEX idx_offers_pending
    ON order_offers (expires_at) WHERE outcome IS NULL;
CREATE INDEX idx_offers_driver_pending
    ON order_offers (driver_id) WHERE outcome IS NULL;
CREATE UNIQUE INDEX idx_offers_one_per_order
    ON order_offers (order_id) WHERE outcome IS NULL;
CREATE UNIQUE INDEX idx_offers_one_per_driver
    ON order_offers (driver_id) WHERE outcome IS NULL;

-- +goose Down
DROP TABLE IF EXISTS order_offers;
