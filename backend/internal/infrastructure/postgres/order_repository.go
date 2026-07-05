package postgres

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

type OrderRepository struct {
	db *sql.DB
}

func NewOrderRepository(db *sql.DB) *OrderRepository {
	return &OrderRepository{db: db}
}

func (r *OrderRepository) Create(ctx context.Context, ord *orderdomain.Order) error {
	const query = `
INSERT INTO orders (id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, price_total, is_cross_city, surcharge_amount, surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, payment_method)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, cents_to_rub($12), $13, cents_to_rub($14), $15, $16, $17, $18, $19, $20, $21, $22)`
	_, err := r.db.ExecContext(
		ctx,
		query,
		ord.ID,
		ord.UserID,
		ord.DriverID,
		ord.Pickup.Lat,
		ord.Pickup.Lng,
		ord.Dropoff.Lat,
		ord.Dropoff.Lng,
		toNullString(ord.PickupAddress),
		toNullString(ord.DropoffAddress),
		string(ord.TowTruckType),
		string(ord.Status),
		ord.PriceTotal,
		ord.IsCrossCity,
		ord.SurchargeAmount,
		ord.SurchargePercent,
		ord.CreatedAt,
		ord.UpdatedAt,
		ord.CancelledAt,
		ord.CityID,
		ord.IsExpanded,
		ord.ExpandedAt,
		ord.PaymentMethod,
	)
	return err
}

func toNullString(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

func scanNullableString(ns sql.NullString) string {
	if ns.Valid {
		return ns.String
	}
	return ""
}

func (r *OrderRepository) Update(ctx context.Context, ord *orderdomain.Order) error {
	const query = `
UPDATE orders
SET driver_id = $2, tow_truck_type = $3, status = $4, updated_at = $5, cancelled_at = $6, is_expanded = $7, expanded_at = $8, price_total = cents_to_rub($9), is_cross_city = $10, surcharge_amount = cents_to_rub($11), surcharge_percent = $12, cancel_reason = $13, payment_method = $14
WHERE id = $1`
	_, err := r.db.ExecContext(ctx, query, ord.ID, ord.DriverID, string(ord.TowTruckType), string(ord.Status), ord.UpdatedAt, ord.CancelledAt, ord.IsExpanded, ord.ExpandedAt, ord.PriceTotal, ord.IsCrossCity, ord.SurchargeAmount, ord.SurchargePercent, toNullString(ord.CancelReason), ord.PaymentMethod)
	return err
}

// AcceptOrder atomically claims an order for driverID using a single
// UPDATE...RETURNING. The WHERE clause ensures only one driver can win:
// the row must still be in 'searching' status with no driver_id assigned.
// If no row is updated, ErrOrderAlreadyTaken is returned.
func (r *OrderRepository) AcceptOrder(ctx context.Context, orderID, driverID string) (*orderdomain.Order, error) {
	const query = `
UPDATE orders
SET driver_id  = $2,
    status     = 'accepted',
    updated_at = NOW()
WHERE id        = $1
  AND status    = 'searching'
  AND driver_id IS NULL
RETURNING id, user_id, driver_id,
          pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
          pickup_address, dropoff_address,
          tow_truck_type, status, rub_to_cents(price_total),
          is_cross_city, rub_to_cents(surcharge_amount), surcharge_percent,
          created_at, updated_at, cancelled_at,
          city_id, is_expanded, expanded_at,
          payment_method`

	var (
		ord            orderdomain.Order
		pickupAddress  sql.NullString
		dropoffAddress sql.NullString
		cityID         sql.NullString
		towTruckType   string
		status         string
		expandedAt     sql.NullTime
		paymentMethod  sql.NullString
	)
	err := r.db.QueryRowContext(ctx, query, orderID, driverID).Scan(
		&ord.ID,
		&ord.UserID,
		&ord.DriverID,
		&ord.Pickup.Lat,
		&ord.Pickup.Lng,
		&ord.Dropoff.Lat,
		&ord.Dropoff.Lng,
		&pickupAddress,
		&dropoffAddress,
		&towTruckType,
		&status,
		&ord.PriceTotal,
		&ord.IsCrossCity,
		&ord.SurchargeAmount,
		&ord.SurchargePercent,
		&ord.CreatedAt,
		&ord.UpdatedAt,
		&ord.CancelledAt,
		&cityID,
		&ord.IsExpanded,
		&expandedAt,
		&paymentMethod,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, orderdomain.ErrOrderAlreadyTaken
		}
		return nil, err
	}
	ord.TowTruckType = orderdomain.TowTruckType(towTruckType)
	ord.Status = orderdomain.Status(status)
	ord.PickupAddress = scanNullableString(pickupAddress)
	ord.DropoffAddress = scanNullableString(dropoffAddress)
	ord.PaymentMethod = scanNullableString(paymentMethod)
	if cityID.Valid {
		ord.CityID = &cityID.String
	}
	if expandedAt.Valid {
		t := expandedAt.Time
		ord.ExpandedAt = &t
	}
	return &ord, nil
}

// HasActiveOrderWithDriver returns true if clientID has an active order
// (accepted, arrived, or in_progress) currently assigned to driverID.
func (r *OrderRepository) HasActiveOrderWithDriver(ctx context.Context, clientID, driverID string) (bool, error) {
	const query = `
SELECT 1 FROM orders
WHERE user_id   = $1
  AND driver_id = $2
  AND status    IN ('accepted','arrived','in_progress')
LIMIT 1`
	var dummy int
	err := r.db.QueryRowContext(ctx, query, clientID, driverID).Scan(&dummy)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// MarkExpanded sets is_expanded=TRUE and expanded_at on a single order atomically.
func (r *OrderRepository) MarkExpanded(ctx context.Context, orderID string, now time.Time) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE orders SET is_expanded = TRUE, expanded_at = $2 WHERE id = $1`,
		orderID, now)
	return err
}

func (r *OrderRepository) GetByID(ctx context.Context, id string) (*orderdomain.Order, error) {
	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, rub_to_cents(price_total), is_cross_city, rub_to_cents(surcharge_amount), surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, cancel_reason, payment_method
FROM orders
WHERE id = $1`

	var (
		ord            orderdomain.Order
		pickupAddress  sql.NullString
		dropoffAddress sql.NullString
		cityID         sql.NullString
		towTruckType   string
		status         string
		expandedAt     sql.NullTime
		cancelReason   sql.NullString
		paymentMethod  sql.NullString
	)
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&ord.ID,
		&ord.UserID,
		&ord.DriverID,
		&ord.Pickup.Lat,
		&ord.Pickup.Lng,
		&ord.Dropoff.Lat,
		&ord.Dropoff.Lng,
		&pickupAddress,
		&dropoffAddress,
		&towTruckType,
		&status,
		&ord.PriceTotal,
		&ord.IsCrossCity,
		&ord.SurchargeAmount,
		&ord.SurchargePercent,
		&ord.CreatedAt,
		&ord.UpdatedAt,
		&ord.CancelledAt,
		&cityID,
		&ord.IsExpanded,
		&expandedAt,
		&cancelReason,
		&paymentMethod,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, orderdomain.ErrOrderNotFound
		}
		return nil, err
	}
	ord.TowTruckType = orderdomain.TowTruckType(towTruckType)
	ord.Status = orderdomain.Status(status)
	ord.PickupAddress = scanNullableString(pickupAddress)
	ord.DropoffAddress = scanNullableString(dropoffAddress)
	ord.PaymentMethod = scanNullableString(paymentMethod)
	if cityID.Valid {
		ord.CityID = &cityID.String
	}
	if expandedAt.Valid {
		t := expandedAt.Time
		ord.ExpandedAt = &t
	}
	ord.CancelReason = scanNullableString(cancelReason)
	return &ord, nil
}

func (r *OrderRepository) ListByStatus(ctx context.Context, status orderdomain.Status, limit int) ([]*orderdomain.Order, error) {
	if limit <= 0 {
		limit = 20
	}

	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, rub_to_cents(price_total), is_cross_city, rub_to_cents(surcharge_amount), surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, payment_method
FROM orders
WHERE status = $1
ORDER BY created_at ASC
LIMIT $2`

	rows, err := r.db.QueryContext(ctx, query, string(status), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	orders := make([]*orderdomain.Order, 0, limit)
	for rows.Next() {
		var (
			ord            orderdomain.Order
			pickupAddress  sql.NullString
			dropoffAddress sql.NullString
			cityID         sql.NullString
			towTruckType   string
			rowStatus      string
			expandedAt     sql.NullTime
			paymentMethod  sql.NullString
		)
		if err := rows.Scan(
			&ord.ID,
			&ord.UserID,
			&ord.DriverID,
			&ord.Pickup.Lat,
			&ord.Pickup.Lng,
			&ord.Dropoff.Lat,
			&ord.Dropoff.Lng,
			&pickupAddress,
			&dropoffAddress,
			&towTruckType,
			&rowStatus,
			&ord.PriceTotal,
			&ord.IsCrossCity,
			&ord.SurchargeAmount,
			&ord.SurchargePercent,
			&ord.CreatedAt,
			&ord.UpdatedAt,
			&ord.CancelledAt,
			&cityID,
			&ord.IsExpanded,
			&expandedAt,
			&paymentMethod,
		); err != nil {
			return nil, err
		}
		ord.TowTruckType = orderdomain.TowTruckType(towTruckType)
		ord.Status = orderdomain.Status(rowStatus)
		ord.PickupAddress = scanNullableString(pickupAddress)
		ord.DropoffAddress = scanNullableString(dropoffAddress)
		ord.PaymentMethod = scanNullableString(paymentMethod)
		if cityID.Valid {
			ord.CityID = &cityID.String
		}
		if expandedAt.Valid {
			t := expandedAt.Time
			ord.ExpandedAt = &t
		}
		orders = append(orders, &ord)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return orders, nil
}

func (r *OrderRepository) ListByStatusAndCity(ctx context.Context, status orderdomain.Status, cityID string, limit int) ([]*orderdomain.Order, error) {
	if limit <= 0 {
		limit = 20
	}
	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, rub_to_cents(price_total), is_cross_city, rub_to_cents(surcharge_amount), 	surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, payment_method
FROM orders
WHERE status = $1 AND city_id = $2
ORDER BY created_at ASC
LIMIT $3`
	return r.queryOrders(ctx, query, string(status), cityID, limit)
}

func (r *OrderRepository) ListByUserID(ctx context.Context, userID string, status orderdomain.Status, limit int) ([]*orderdomain.Order, error) {
	if limit <= 0 {
		limit = 20
	}
	query := `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, rub_to_cents(price_total), is_cross_city, rub_to_cents(surcharge_amount), 	surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, payment_method
FROM orders
WHERE user_id = $1`
	args := []any{userID}
	if status != "" {
		query += ` AND status = $2 ORDER BY created_at DESC LIMIT $3`
		args = append(args, string(status), limit)
	} else {
		query += ` ORDER BY created_at DESC LIMIT $2`
		args = append(args, limit)
	}
	return r.listOrders(ctx, query, args...)
}

func (r *OrderRepository) ListByDriverID(ctx context.Context, driverID string, status orderdomain.Status, limit int) ([]*orderdomain.Order, error) {
	if limit <= 0 {
		limit = 20
	}
	query := `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, rub_to_cents(price_total), is_cross_city, rub_to_cents(surcharge_amount), 	surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, payment_method
FROM orders
WHERE driver_id = $1`
	args := []any{driverID}
	if status != "" {
		query += ` AND status = $2 ORDER BY created_at DESC LIMIT $3`
		args = append(args, string(status), limit)
	} else {
		query += ` ORDER BY created_at DESC LIMIT $2`
		args = append(args, limit)
	}
	return r.listOrders(ctx, query, args...)
}

// ListSearchingForExpansion returns orders that have been in "searching" status
// for longer than olderThan and have not yet been expanded.
func (r *OrderRepository) ListSearchingForExpansion(ctx context.Context, olderThan time.Time, limit int) ([]*orderdomain.Order, error) {
	if limit <= 0 {
		limit = 100
	}
	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, rub_to_cents(price_total), is_cross_city, rub_to_cents(surcharge_amount), 	surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, payment_method
FROM orders
WHERE status = 'searching' AND is_expanded = FALSE AND created_at < $1
ORDER BY created_at ASC
LIMIT $2`
	return r.queryOrders(ctx, query, olderThan, limit)
}

// ListExpandedSearching returns orders in "searching" status that have already
// been expanded to the wider radius.
func (r *OrderRepository) ListExpandedSearching(ctx context.Context, limit int) ([]*orderdomain.Order, error) {
	if limit <= 0 {
		limit = 100
	}
	const query = `
SELECT id, user_id, driver_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address, dropoff_address, tow_truck_type, status, rub_to_cents(price_total), is_cross_city, rub_to_cents(surcharge_amount), 	surcharge_percent, created_at, updated_at, cancelled_at, city_id, is_expanded, expanded_at, payment_method
FROM orders
WHERE status = 'searching' AND is_expanded = TRUE
ORDER BY created_at ASC
LIMIT $1`
	return r.queryOrders(ctx, query, limit)
}

// queryOrders runs any SELECT query whose columns match the standard order projection.
func (r *OrderRepository) queryOrders(ctx context.Context, query string, args ...any) ([]*orderdomain.Order, error) {
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return r.scanOrders(rows)
}

func (r *OrderRepository) listOrders(ctx context.Context, query string, args ...any) ([]*orderdomain.Order, error) {
	return r.queryOrders(ctx, query, args...)
}

func (r *OrderRepository) scanOrders(rows *sql.Rows) ([]*orderdomain.Order, error) {
	orders := make([]*orderdomain.Order, 0)
	for rows.Next() {
		var (
			ord            orderdomain.Order
			pickupAddress  sql.NullString
			dropoffAddress sql.NullString
			cityID         sql.NullString
			towTruckType   string
			rowStatus      string
			expandedAt     sql.NullTime
			paymentMethod  sql.NullString
		)
		if err := rows.Scan(
			&ord.ID,
			&ord.UserID,
			&ord.DriverID,
			&ord.Pickup.Lat,
			&ord.Pickup.Lng,
			&ord.Dropoff.Lat,
			&ord.Dropoff.Lng,
			&pickupAddress,
			&dropoffAddress,
			&towTruckType,
			&rowStatus,
			&ord.PriceTotal,
			&ord.IsCrossCity,
			&ord.SurchargeAmount,
			&ord.SurchargePercent,
			&ord.CreatedAt,
			&ord.UpdatedAt,
			&ord.CancelledAt,
			&cityID,
			&ord.IsExpanded,
			&expandedAt,
			&paymentMethod,
		); err != nil {
			return nil, err
		}
		ord.TowTruckType = orderdomain.TowTruckType(towTruckType)
		ord.Status = orderdomain.Status(rowStatus)
		ord.PickupAddress = scanNullableString(pickupAddress)
		ord.DropoffAddress = scanNullableString(dropoffAddress)
		ord.PaymentMethod = scanNullableString(paymentMethod)
		if cityID.Valid {
			ord.CityID = &cityID.String
		}
		if expandedAt.Valid {
			t := expandedAt.Time
			ord.ExpandedAt = &t
		}
		orders = append(orders, &ord)
	}
	return orders, rows.Err()
}

// ListAdminOrders returns paginated denormalized orders for the admin panel.
// All money values (price_total, commission, driver_amount) are returned in
// kopecks (minor units). Filters are AND-combined; empty fields are skipped.
// completed_at is approximated by financially_completed_at (if present) or
// by updated_at when status='completed'.
func (r *OrderRepository) ListAdminOrders(ctx context.Context, filter orderdomain.AdminOrderFilter) ([]orderdomain.AdminOrderListItem, int64, error) {
	limit := filter.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	offset := filter.Offset
	if offset < 0 {
		offset = 0
	}

	conds := make([]string, 0, 8)
	args := make([]any, 0, 8)
	add := func(cond string, value any) {
		args = append(args, value)
		conds = append(conds, strings.ReplaceAll(cond, "?", argRef(len(args))))
	}
	if s := strings.TrimSpace(filter.Status); s != "" {
		add("o.status = ?", s)
	}
	if s := strings.TrimSpace(filter.PaymentMethod); s != "" {
		add("o.payment_method = ?", s)
	}
	if s := strings.TrimSpace(filter.FinancialStatus); s != "" {
		add("o.financial_status = ?", s)
	}
	if s := strings.TrimSpace(filter.DriverID); s != "" {
		add("o.driver_id = ?", s)
	}
	if s := strings.TrimSpace(filter.ClientID); s != "" {
		add("o.user_id = ?", s)
	}
	if filter.From != nil {
		add("o.created_at >= ?", *filter.From)
	}
	if filter.To != nil {
		add("o.created_at <= ?", *filter.To)
	}

	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	// Total count for pagination metadata.
	var total int64
	countQuery := "SELECT COUNT(*) FROM orders o " + where
	if err := r.db.QueryRowContext(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	// Aggregated commission and driver_amount per order from wallet_transactions.
	// commission: sum of 'commission' and 'cash_commission_debt' (driver pays platform).
	// driver_amount: sum of 'order_income' (positive direction for driver).
	// payment status: latest payment row for the order, if present.
	listQuery := `
SELECT
	o.id,
	o.user_id,
	o.driver_id,
	COALESCE(cv.full_name, '') AS client_name,
	COALESCE(cv.phone, '') AS client_phone,
	COALESCE(dv.full_name, '') AS driver_name,
	COALESCE(dv.phone, '') AS driver_phone,
	o.status,
	o.payment_method,
	COALESCE(p.status, '') AS payment_status,
	o.financial_status,
	rub_to_cents(o.price_total) AS price_total,
	COALESCE((
		SELECT SUM(rub_to_cents(wt.amount))
		FROM wallet_transactions wt
		WHERE wt.order_id = o.id AND wt.type IN ('commission','cash_commission_debt')
	), 0) AS commission_amount,
	COALESCE((
		SELECT SUM(rub_to_cents(wt.amount))
		FROM wallet_transactions wt
		WHERE wt.order_id = o.id AND wt.type = 'order_income'
	), 0) AS driver_amount,
	o.created_at,
	o.financially_completed_at AS completed_at,
	o.cancelled_at
FROM orders o
LEFT JOIN driver_verifications cv ON cv.user_id = o.user_id
LEFT JOIN drivers d ON d.id = o.driver_id
LEFT JOIN driver_verifications dv ON dv.user_id = d.user_id OR dv.user_id = o.driver_id
LEFT JOIN LATERAL (
	SELECT status FROM payments WHERE order_id = o.id ORDER BY created_at DESC LIMIT 1
) p ON TRUE
` + where + `
ORDER BY o.created_at DESC
LIMIT ` + argRef(len(args)+1) + ` OFFSET ` + argRef(len(args)+2)

	args = append(args, limit, offset)
	rows, err := r.db.QueryContext(ctx, listQuery, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]orderdomain.AdminOrderListItem, 0, limit)
	for rows.Next() {
		var (
			item        orderdomain.AdminOrderListItem
			driverID    sql.NullString
			completedAt sql.NullTime
			cancelledAt sql.NullTime
		)
		if err := rows.Scan(
			&item.OrderID,
			&item.ClientID,
			&driverID,
			&item.ClientName,
			&item.ClientPhone,
			&item.DriverName,
			&item.DriverPhone,
			&item.Status,
			&item.PaymentMethod,
			&item.PaymentStatus,
			&item.FinancialStatus,
			&item.PriceTotal,
			&item.CommissionAmount,
			&item.DriverAmount,
			&item.CreatedAt,
			&completedAt,
			&cancelledAt,
		); err != nil {
			return nil, 0, err
		}
		if driverID.Valid {
			item.DriverID = driverID.String
		}
		if completedAt.Valid {
			t := completedAt.Time
			item.CompletedAt = &t
		}
		if cancelledAt.Valid {
			t := cancelledAt.Time
			item.CancelledAt = &t
		}
		items = append(items, item)
	}
	return items, total, rows.Err()
}

// GetAdminOrderDetails returns full denormalized details for a single order
// for the admin panel: client, driver, route, timeline (best-effort from the
// orders row), payment, wallet transactions, payouts linked via wallet
// transactions, refunds and a financial breakdown.
func (r *OrderRepository) GetAdminOrderDetails(ctx context.Context, orderID string) (*orderdomain.AdminOrderDetails, error) {
	const orderQuery = `
SELECT
	o.id,
	o.user_id,
	o.driver_id,
	COALESCE(cv.full_name, '') AS client_name,
	COALESCE(cv.phone, '') AS client_phone,
	COALESCE(dv.full_name, '') AS driver_name,
	COALESCE(dv.phone, '') AS driver_phone,
	o.status,
	o.payment_method,
	COALESCE(p.status, '') AS payment_status,
	o.financial_status,
	rub_to_cents(o.price_total) AS price_total,
	COALESCE((
		SELECT SUM(rub_to_cents(wt.amount))
		FROM wallet_transactions wt
		WHERE wt.order_id = o.id AND wt.type IN ('commission','cash_commission_debt')
	), 0) AS commission_amount,
	COALESCE((
		SELECT SUM(rub_to_cents(wt.amount))
		FROM wallet_transactions wt
		WHERE wt.order_id = o.id AND wt.type = 'order_income'
	), 0) AS driver_amount,
	COALESCE((
		SELECT SUM(rub_to_cents(wt.amount))
		FROM wallet_transactions wt
		WHERE wt.order_id = o.id AND wt.type = 'cash_commission_debt'
	), 0) AS cash_commission_hold,
	o.created_at,
	o.updated_at,
	o.financially_completed_at,
	o.cancelled_at,
	o.pickup_lat, o.pickup_lng, o.dropoff_lat, o.dropoff_lng, o.tow_truck_type
FROM orders o
LEFT JOIN driver_verifications cv ON cv.user_id = o.user_id
LEFT JOIN drivers d ON d.id = o.driver_id
LEFT JOIN driver_verifications dv ON dv.user_id = d.user_id OR dv.user_id = o.driver_id
LEFT JOIN LATERAL (
	SELECT status FROM payments WHERE order_id = o.id ORDER BY created_at DESC LIMIT 1
) p ON TRUE
WHERE o.id = $1`

	var (
		details     orderdomain.AdminOrderDetails
		item        orderdomain.AdminOrderListItem
		driverID    sql.NullString
		updatedAt   sql.NullTime
		completedAt sql.NullTime
		cancelledAt sql.NullTime
		cashHold    int64
	)
	err := r.db.QueryRowContext(ctx, orderQuery, orderID).Scan(
		&item.OrderID,
		&item.ClientID,
		&driverID,
		&item.ClientName,
		&item.ClientPhone,
		&item.DriverName,
		&item.DriverPhone,
		&item.Status,
		&item.PaymentMethod,
		&item.PaymentStatus,
		&item.FinancialStatus,
		&item.PriceTotal,
		&item.CommissionAmount,
		&item.DriverAmount,
		&cashHold,
		&item.CreatedAt,
		&updatedAt,
		&completedAt,
		&cancelledAt,
		&details.Pickup.Lat, &details.Pickup.Lng,
		&details.Dropoff.Lat, &details.Dropoff.Lng,
		&details.TowTruckType,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, orderdomain.ErrOrderNotFound
		}
		return nil, err
	}
	if driverID.Valid {
		item.DriverID = driverID.String
	}
	if completedAt.Valid {
		t := completedAt.Time
		item.CompletedAt = &t
	}
	if cancelledAt.Valid {
		t := cancelledAt.Time
		item.CancelledAt = &t
	}
	details.Order = item

	// Timeline: best-effort using existing timestamps. A dedicated event log
	// table is out of scope for this iteration.
	details.Timeline = append(details.Timeline, orderdomain.AdminOrderTimelineEvent{
		At: item.CreatedAt, Status: "created",
	})
	if updatedAt.Valid && updatedAt.Time.After(item.CreatedAt) && item.Status != "created" {
		details.Timeline = append(details.Timeline, orderdomain.AdminOrderTimelineEvent{
			At: updatedAt.Time, Status: item.Status,
		})
	}
	if item.CompletedAt != nil {
		details.Timeline = append(details.Timeline, orderdomain.AdminOrderTimelineEvent{
			At: *item.CompletedAt, Status: "financially_completed",
		})
	}
	if item.CancelledAt != nil {
		details.Timeline = append(details.Timeline, orderdomain.AdminOrderTimelineEvent{
			At: *item.CancelledAt, Status: "cancelled",
		})
	}

	// Payment link.
	const paymentQuery = `
SELECT id, provider, COALESCE(provider_payment_id, ''), payment_method, rub_to_cents(amount), status, paid_at, created_at
FROM payments
WHERE order_id = $1
ORDER BY created_at DESC
LIMIT 1`
	var payment orderdomain.AdminOrderPaymentLink
	var paidAt sql.NullTime
	err = r.db.QueryRowContext(ctx, paymentQuery, orderID).Scan(
		&payment.ID,
		&payment.Provider,
		&payment.ProviderPaymentID,
		&payment.PaymentMethod,
		&payment.Amount,
		&payment.Status,
		&paidAt,
		&payment.CreatedAt,
	)
	if err == nil {
		if paidAt.Valid {
			t := paidAt.Time
			payment.PaidAt = &t
		}
		details.Payment = &payment
	} else if !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}

	// Wallet transactions linked to the order.
	const walletTxQuery = `
SELECT id, driver_id, type, direction, rub_to_cents(amount), status, description, created_at
FROM wallet_transactions
WHERE order_id = $1
ORDER BY created_at ASC`
	wtRows, err := r.db.QueryContext(ctx, walletTxQuery, orderID)
	if err != nil {
		return nil, err
	}
	defer wtRows.Close()
	payoutIDs := map[string]struct{}{}
	for wtRows.Next() {
		var link orderdomain.AdminOrderWalletTxLink
		if err := wtRows.Scan(&link.ID, &link.DriverID, &link.Type, &link.Direction, &link.Amount, &link.Status, &link.Description, &link.CreatedAt); err != nil {
			return nil, err
		}
		details.WalletTransactions = append(details.WalletTransactions, link)
	}
	if err := wtRows.Err(); err != nil {
		return nil, err
	}

	// Payouts that share the same driver in time window: we link payouts by
	// driver_id and a wallet_transaction payout entry that touches the same
	// order's driver. For first iteration we expose all payouts that share
	// payout_id with this order's wallet transactions (typically empty for now).
	if len(payoutIDs) == 0 {
		// Look up payout_id from wallet_transactions of this order:
		const payoutLookup = `
SELECT DISTINCT payout_id FROM wallet_transactions WHERE order_id = $1 AND payout_id IS NOT NULL`
		idRows, err := r.db.QueryContext(ctx, payoutLookup, orderID)
		if err != nil {
			return nil, err
		}
		defer idRows.Close()
		var ids []string
		for idRows.Next() {
			var id sql.NullString
			if err := idRows.Scan(&id); err != nil {
				return nil, err
			}
			if id.Valid && id.String != "" {
				ids = append(ids, id.String)
			}
		}
		if err := idRows.Err(); err != nil {
			return nil, err
		}
		for _, id := range ids {
			const q = `SELECT id, driver_id, rub_to_cents(amount), status, created_at FROM payouts WHERE id = $1`
			var link orderdomain.AdminOrderPayoutLink
			if err := r.db.QueryRowContext(ctx, q, id).Scan(&link.ID, &link.DriverID, &link.Amount, &link.Status, &link.CreatedAt); err == nil {
				details.Payouts = append(details.Payouts, link)
			} else if !errors.Is(err, sql.ErrNoRows) {
				return nil, err
			}
		}
	}

	// Refunds for the payment.
	if details.Payment != nil {
		const refundQuery = `
SELECT id, payment_id, rub_to_cents(amount), status, reason, created_at
FROM refunds
WHERE payment_id = $1
ORDER BY created_at ASC`
		rRows, err := r.db.QueryContext(ctx, refundQuery, details.Payment.ID)
		if err != nil {
			return nil, err
		}
		defer rRows.Close()
		for rRows.Next() {
			var link orderdomain.AdminOrderRefundLink
			if err := rRows.Scan(&link.ID, &link.PaymentID, &link.Amount, &link.Status, &link.Reason, &link.CreatedAt); err != nil {
				return nil, err
			}
			details.Refunds = append(details.Refunds, link)
		}
		if err := rRows.Err(); err != nil {
			return nil, err
		}
	}

	// Financial breakdown.
	details.FinancialBreakdown = orderdomain.AdminOrderFinancialBreakdown{
		TotalAmount:        item.PriceTotal,
		CommissionAmount:   item.CommissionAmount,
		DriverAmount:       item.DriverAmount,
		CashCommissionHold: cashHold,
		PlatformNetAmount:  item.CommissionAmount - cashHold,
	}
	return &details, nil
}

// argRef returns "$N" — used to build dynamic SQL with positional args.
func argRef(n int) string {
	switch n {
	case 1:
		return "$1"
	case 2:
		return "$2"
	case 3:
		return "$3"
	case 4:
		return "$4"
	case 5:
		return "$5"
	case 6:
		return "$6"
	case 7:
		return "$7"
	case 8:
		return "$8"
	case 9:
		return "$9"
	case 10:
		return "$10"
	}
	// Fallback (shouldn't be needed in our handlers).
	buf := []byte("$")
	for _, ch := range []byte{'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'} {
		_ = ch
	}
	// Build manually for n>10 to avoid importing strconv at top of file.
	digits := []byte{}
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	buf = append(buf, digits...)
	return string(buf)
}
