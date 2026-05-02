package postgres

import (
	"context"
	"database/sql"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	pricingdomain "evik/backend/internal/domain/pricing"
)

type PricingRepository struct {
	db *sql.DB
}

func NewPricingRepository(db *sql.DB) pricingdomain.Repository {
	return &PricingRepository{db: db}
}

func (r *PricingRepository) GetByTowTruckType(ctx context.Context, truckType orderdomain.TowTruckType) (*pricingdomain.Tariff, error) {
	const query = `
		SELECT id, tow_truck_type, base_price, price_per_km, minimum_price, is_active, created_at, updated_at
		FROM pricing_tariffs
		WHERE tow_truck_type = $1 AND is_active = true
		LIMIT 1
	`

	var tariff pricingdomain.Tariff
	var truckTypeStr string

	err := r.db.QueryRowContext(ctx, query, string(truckType)).Scan(
		&tariff.ID,
		&truckTypeStr,
		&tariff.BasePrice,
		&tariff.PricePerKm,
		&tariff.MinimumPrice,
		&tariff.IsActive,
		&tariff.CreatedAt,
		&tariff.UpdatedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, pricingdomain.ErrTariffNotFound
		}
		return nil, err
	}

	tariff.TowTruckType = orderdomain.TowTruckType(truckTypeStr)
	return &tariff, nil
}

func (r *PricingRepository) GetAll(ctx context.Context) ([]*pricingdomain.Tariff, error) {
	const query = `
		SELECT id, tow_truck_type, base_price, price_per_km, minimum_price, is_active, created_at, updated_at
		FROM pricing_tariffs
		WHERE is_active = true
		ORDER BY tow_truck_type
	`

	rows, err := r.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tariffs []*pricingdomain.Tariff
	for rows.Next() {
		var tariff pricingdomain.Tariff
		var truckTypeStr string

		err := rows.Scan(
			&tariff.ID,
			&truckTypeStr,
			&tariff.BasePrice,
			&tariff.PricePerKm,
			&tariff.MinimumPrice,
			&tariff.IsActive,
			&tariff.CreatedAt,
			&tariff.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}

		tariff.TowTruckType = orderdomain.TowTruckType(truckTypeStr)
		tariffs = append(tariffs, &tariff)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return tariffs, nil
}

func (r *PricingRepository) GetByID(ctx context.Context, id string) (*pricingdomain.Tariff, error) {
	const query = `
		SELECT id, tow_truck_type, base_price, price_per_km, minimum_price, is_active, created_at, updated_at
		FROM pricing_tariffs
		WHERE id = $1
		LIMIT 1
	`

	var tariff pricingdomain.Tariff
	var truckTypeStr string

	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&tariff.ID,
		&truckTypeStr,
		&tariff.BasePrice,
		&tariff.PricePerKm,
		&tariff.MinimumPrice,
		&tariff.IsActive,
		&tariff.CreatedAt,
		&tariff.UpdatedAt,
	)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, pricingdomain.ErrTariffNotFound
		}
		return nil, err
	}

	tariff.TowTruckType = orderdomain.TowTruckType(truckTypeStr)
	return &tariff, nil
}

func (r *PricingRepository) Create(ctx context.Context, tariff *pricingdomain.Tariff) error {
	const query = `
		INSERT INTO pricing_tariffs (id, tow_truck_type, base_price, price_per_km, minimum_price, is_active, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`

	_, err := r.db.ExecContext(ctx, query,
		tariff.ID,
		string(tariff.TowTruckType),
		tariff.BasePrice,
		tariff.PricePerKm,
		tariff.MinimumPrice,
		tariff.IsActive,
		tariff.CreatedAt,
		tariff.UpdatedAt,
	)

	return err
}

func (r *PricingRepository) Update(ctx context.Context, tariff *pricingdomain.Tariff) error {
	const query = `
		UPDATE pricing_tariffs
		SET base_price = $2, price_per_km = $3, minimum_price = $4, is_active = $5, updated_at = $6
		WHERE id = $1
	`

	tariff.UpdatedAt = time.Now().UTC()
	result, err := r.db.ExecContext(ctx, query,
		tariff.ID,
		tariff.BasePrice,
		tariff.PricePerKm,
		tariff.MinimumPrice,
		tariff.IsActive,
		tariff.UpdatedAt,
	)

	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if rowsAffected == 0 {
		return pricingdomain.ErrTariffNotFound
	}

	return nil
}

func (r *PricingRepository) Delete(ctx context.Context, id string) error {
	const query = `
		UPDATE pricing_tariffs
		SET is_active = false, updated_at = $2
		WHERE id = $1 AND is_active = true
	`

	result, err := r.db.ExecContext(ctx, query, id, time.Now().UTC())
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if rowsAffected == 0 {
		return pricingdomain.ErrTariffNotFound
	}

	return nil
}