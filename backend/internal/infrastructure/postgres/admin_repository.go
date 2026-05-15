package postgres

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"

	admindomain "evik/backend/internal/domain/admin"
	httptransport "evik/backend/internal/transport/http"
)

type AdminRepository struct {
	db *sql.DB
}

func NewAdminRepository(db *sql.DB) *AdminRepository {
	return &AdminRepository{db: db}
}

func (r *AdminRepository) Overview(ctx context.Context) (admindomain.Overview, error) {
	const query = `
WITH clients AS (
	SELECT COUNT(DISTINCT user_id) AS count FROM orders
),
drivers_count AS (
	SELECT COUNT(*) AS count FROM drivers
),
online_drivers AS (
	SELECT COUNT(*) AS count FROM drivers WHERE status IN ('online', 'busy')
),
active_drivers AS (
	SELECT COUNT(*) AS count FROM drivers WHERE status IN ('online', 'busy')
),
pending_moderations AS (
	SELECT COUNT(*) AS count FROM driver_verifications WHERE status = 'pending'
),
avg_reviews AS (
	SELECT COALESCE(AVG(stars), 0) AS value FROM driver_reviews
),
reviews_today AS (
	SELECT COUNT(*) AS count FROM driver_reviews WHERE created_at >= DATE_TRUNC('day', NOW())
),
active_orders AS (
	SELECT COUNT(*) AS count FROM orders WHERE status IN ('searching', 'accepted', 'arrived', 'in_progress')
),
-- Finance KPI. All money in kopecks (rub_to_cents).
gmv_today AS (
	SELECT COALESCE(SUM(rub_to_cents(price_total)), 0) AS amount
	FROM orders WHERE status = 'completed' AND created_at >= DATE_TRUNC('day', NOW())
),
gmv_month AS (
	SELECT COALESCE(SUM(rub_to_cents(price_total)), 0) AS amount
	FROM orders WHERE status = 'completed' AND created_at >= DATE_TRUNC('month', NOW())
),
commission_today AS (
	SELECT COALESCE(SUM(rub_to_cents(amount)), 0) AS amount
	FROM wallet_transactions
	WHERE type IN ('commission','cash_commission_debt')
	AND created_at >= DATE_TRUNC('day', NOW())
),
commission_month AS (
	SELECT COALESCE(SUM(rub_to_cents(amount)), 0) AS amount
	FROM wallet_transactions
	WHERE type IN ('commission','cash_commission_debt')
	AND created_at >= DATE_TRUNC('month', NOW())
),
payouts_today AS (
	SELECT COALESCE(SUM(rub_to_cents(amount)), 0) AS amount
	FROM payouts WHERE status = 'paid' AND created_at >= DATE_TRUNC('day', NOW())
),
payouts_month AS (
	SELECT COALESCE(SUM(rub_to_cents(amount)), 0) AS amount
	FROM payouts WHERE status = 'paid' AND created_at >= DATE_TRUNC('month', NOW())
),
payouts_pending AS (
	SELECT COALESCE(SUM(rub_to_cents(amount)), 0) AS amount
	FROM payouts WHERE status IN ('created','processing','manual_review')
),
failed_payments AS (
	SELECT COUNT(*) AS count FROM payments WHERE status IN ('failed','canceled')
),
failed_payouts AS (
	SELECT COUNT(*) AS count FROM payouts WHERE status = 'failed'
),
subs_today AS (
	SELECT COALESCE(SUM(rub_to_cents(amount)), 0) AS amount
	FROM subscriptions WHERE status = 'active' AND created_at >= DATE_TRUNC('day', NOW())
),
subs_month AS (
	SELECT COALESCE(SUM(rub_to_cents(amount)), 0) AS amount
	FROM subscriptions WHERE status = 'active' AND created_at >= DATE_TRUNC('month', NOW())
),
cash_debt_total AS (
	SELECT COALESCE(SUM(rub_to_cents(debt_balance)), 0) AS amount FROM driver_wallets
)
SELECT
	(SELECT count FROM clients) + (SELECT count FROM drivers_count) AS total_users,
	(SELECT count FROM clients) AS clients,
	(SELECT count FROM drivers_count) AS drivers,
	(SELECT count FROM online_drivers) AS online_drivers,
	(SELECT count FROM pending_moderations) AS pending_moderations,
	(SELECT value FROM avg_reviews) AS average_driver_stars,
	(SELECT count FROM reviews_today) AS reviews_today,
	(SELECT count FROM active_orders) AS active_orders,
	(SELECT amount FROM gmv_today)              AS gmv_today,
	(SELECT amount FROM gmv_month)              AS gmv_month,
	(SELECT amount FROM commission_today)       AS commission_today,
	(SELECT amount FROM commission_month)       AS commission_month,
	(SELECT amount FROM payouts_today)          AS payouts_today,
	(SELECT amount FROM payouts_month)          AS payouts_month,
	(SELECT amount FROM payouts_pending)        AS payouts_pending,
	(SELECT count FROM failed_payments)         AS failed_payments,
	(SELECT count FROM failed_payouts)          AS failed_payouts,
	(SELECT amount FROM subs_today)             AS subs_today,
	(SELECT amount FROM subs_month)             AS subs_month,
	(SELECT amount FROM cash_debt_total)        AS cash_debt_total,
	(SELECT count FROM active_drivers)          AS active_drivers,
	(SELECT count FROM pending_moderations)     AS pending_verifications`

	var out admindomain.Overview
	err := r.db.QueryRowContext(ctx, query).Scan(
		&out.TotalUsers,
		&out.Clients,
		&out.Drivers,
		&out.OnlineDrivers,
		&out.PendingModerations,
		&out.AverageDriverStars,
		&out.ReviewsToday,
		&out.ActiveOrders,
		&out.GMVToday,
		&out.GMVMonth,
		&out.CommissionToday,
		&out.CommissionMonth,
		&out.PayoutsToday,
		&out.PayoutsMonth,
		&out.PayoutsPending,
		&out.FailedPayments,
		&out.FailedPayouts,
		&out.SubscriptionsRevenueToday,
		&out.SubscriptionsRevenueMonth,
		&out.CashDebtTotal,
		&out.ActiveDrivers,
		&out.PendingVerifications,
	)
	if err != nil {
		return out, err
	}

	out.GMVByDay, err = r.kpiDailySeries(ctx, `
SELECT to_char(d::date, 'YYYY-MM-DD') AS day,
	COALESCE(SUM(rub_to_cents(o.price_total)), 0) AS amount
FROM generate_series(DATE_TRUNC('day', NOW()) - INTERVAL '29 days', DATE_TRUNC('day', NOW()), INTERVAL '1 day') d
LEFT JOIN orders o
	ON o.status = 'completed' AND DATE_TRUNC('day', o.created_at) = d
GROUP BY d
ORDER BY d`)
	if err != nil {
		return out, err
	}
	out.CommissionByDay, err = r.kpiDailySeries(ctx, `
SELECT to_char(d::date, 'YYYY-MM-DD') AS day,
	COALESCE(SUM(rub_to_cents(wt.amount)), 0) AS amount
FROM generate_series(DATE_TRUNC('day', NOW()) - INTERVAL '29 days', DATE_TRUNC('day', NOW()), INTERVAL '1 day') d
LEFT JOIN wallet_transactions wt
	ON wt.type IN ('commission','cash_commission_debt') AND DATE_TRUNC('day', wt.created_at) = d
GROUP BY d
ORDER BY d`)
	return out, err
}

// kpiDailySeries returns a 30-day series of {date, amount}. amount is in kopecks.
func (r *AdminRepository) kpiDailySeries(ctx context.Context, query string) ([]admindomain.KPIDailyPoint, error) {
	rows, err := r.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	points := make([]admindomain.KPIDailyPoint, 0, 30)
	for rows.Next() {
		var point admindomain.KPIDailyPoint
		if err := rows.Scan(&point.Date, &point.Amount); err != nil {
			return nil, err
		}
		points = append(points, point)
	}
	return points, rows.Err()
}

func (r *AdminRepository) ListDriverVerifications(ctx context.Context, limit int) ([]admindomain.DriverVerification, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	const query = `
SELECT
	v.id,
	v.user_id,
	v.full_name,
	v.phone,
	v.city,
	v.vehicle_model,
	v.vehicle_plate,
	v.vehicle_type,
	v.status,
	v.risk,
	COALESCE(AVG(rv.stars), 0) AS stars,
	COUNT(DISTINCT o.id) AS orders,
	v.submitted_at,
	v.documents_json,
	v.signals_json,
	v.decision_reason
FROM driver_verifications v
LEFT JOIN orders o ON o.driver_id = v.user_id
LEFT JOIN driver_reviews rv ON rv.driver_id = v.user_id
GROUP BY v.id
ORDER BY
	CASE WHEN v.status = 'pending' THEN 0 ELSE 1 END,
	v.submitted_at DESC
LIMIT $1`

	rows, err := r.db.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]admindomain.DriverVerification, 0, limit)
	for rows.Next() {
		var (
			item          admindomain.DriverVerification
			documentsJSON string
			signalsJSON   string
		)
		if err := rows.Scan(
			&item.ID,
			&item.UserID,
			&item.DriverName,
			&item.Phone,
			&item.City,
			&item.Vehicle,
			&item.Plate,
			&item.VehicleType,
			&item.Status,
			&item.Risk,
			&item.Stars,
			&item.Orders,
			&item.SubmittedAt,
			&documentsJSON,
			&signalsJSON,
			&item.DecisionReason,
		); err != nil {
			return nil, err
		}
		item.Documents = decodeStringList(documentsJSON)
		item.Signals = decodeStringList(signalsJSON)
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *AdminRepository) UpsertDriverVerification(ctx context.Context, item admindomain.DriverVerification) error {
	documentsJSON, err := json.Marshal(item.Documents)
	if err != nil {
		return err
	}
	signalsJSON, err := json.Marshal(item.Signals)
	if err != nil {
		return err
	}
	if item.Status == "" {
		item.Status = "pending"
	}
	if item.Risk == "" {
		item.Risk = "low"
	}

	const query = `
INSERT INTO driver_verifications (
	id, user_id, full_name, phone, city, vehicle_model, vehicle_plate, vehicle_type,
	status, risk, documents_json, signals_json, submitted_at, updated_at
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $13)
ON CONFLICT (id) DO UPDATE SET
	user_id = EXCLUDED.user_id,
	full_name = EXCLUDED.full_name,
	phone = EXCLUDED.phone,
	city = EXCLUDED.city,
	vehicle_model = EXCLUDED.vehicle_model,
	vehicle_plate = EXCLUDED.vehicle_plate,
	vehicle_type = EXCLUDED.vehicle_type,
	status = EXCLUDED.status,
	risk = EXCLUDED.risk,
	documents_json = EXCLUDED.documents_json,
	signals_json = EXCLUDED.signals_json,
	decision_reason = NULL,
	reviewed_by = NULL,
	reviewed_at = NULL,
	updated_at = EXCLUDED.updated_at`

	_, err = r.db.ExecContext(
		ctx,
		query,
		item.ID,
		item.UserID,
		item.DriverName,
		item.Phone,
		item.City,
		item.Vehicle,
		item.Plate,
		item.VehicleType,
		item.Status,
		item.Risk,
		string(documentsJSON),
		string(signalsJSON),
		item.SubmittedAt,
	)
	return err
}

func (r *AdminRepository) DecideDriverVerification(
	ctx context.Context,
	decision admindomain.DriverVerificationDecision,
) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// When approving, overwrite vehicle columns with the values the admin
	// entered in the approval form. For other status transitions we leave
	// them alone — they may have been set by an earlier approval.
	var result sql.Result
	if decision.Status == "approved" && decision.VehiclePlate != "" {
		result, err = tx.ExecContext(ctx, `
UPDATE driver_verifications
SET status = $2,
    decision_reason = $3,
    reviewed_by = $4,
    reviewed_at = $5,
    updated_at = $5,
    vehicle_plate = $6,
    vehicle_model = $7,
    vehicle_type = $8
WHERE id = $1`,
			decision.ID, decision.Status, decision.Reason, decision.ModeratorID, decision.Now,
			decision.VehiclePlate, decision.VehicleModel, decision.VehicleType,
		)
	} else {
		result, err = tx.ExecContext(ctx, `
UPDATE driver_verifications
SET status = $2, decision_reason = $3, reviewed_by = $4, reviewed_at = $5, updated_at = $5
WHERE id = $1`,
			decision.ID, decision.Status, decision.Reason, decision.ModeratorID, decision.Now,
		)
	}
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return sql.ErrNoRows
	}

	_, err = tx.ExecContext(ctx, `
INSERT INTO moderation_audit_log (id, entity_type, entity_id, action, reason, moderator_id, created_at)
VALUES ($1, 'driver_verification', $2, $3, $4, $5, $6)`,
		decision.AuditID,
		decision.ID,
		decision.Status,
		decision.Reason,
		decision.ModeratorID,
		decision.Now,
	)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (r *AdminRepository) ListUsers(ctx context.Context, limit int) ([]admindomain.User, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}

	const query = `
WITH driver_users AS (
	SELECT
		d.id AS id,
		COALESCE(v.full_name, d.user_id) AS name,
		'driver' AS role,
		COALESCE(v.phone, '') AS phone,
		COUNT(o.id) AS orders,
		CASE
			WHEN COALESCE(v.status, '') = 'blocked' THEN 'blocked'
			WHEN COALESCE(v.status, '') = 'pending' THEN 'moderation'
			WHEN d.status IN ('online', 'busy') THEN 'active'
			ELSE d.status
		END AS status
	FROM drivers d
	LEFT JOIN driver_verifications v ON v.user_id = d.user_id OR v.user_id = d.id
	LEFT JOIN orders o ON o.driver_id = d.id
	GROUP BY d.id, d.user_id, d.status, v.full_name, v.phone, v.status
),
client_users AS (
	SELECT
		o.user_id AS id,
		o.user_id AS name,
		'client' AS role,
		'' AS phone,
		COUNT(o.id) AS orders,
		'active' AS status
	FROM orders o
	GROUP BY o.user_id
)
SELECT id, name, role, phone, orders, status
FROM (
	SELECT * FROM driver_users
	UNION ALL
	SELECT * FROM client_users
) users
ORDER BY role DESC, orders DESC, id
LIMIT $1`

	rows, err := r.db.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]admindomain.User, 0, limit)
	for rows.Next() {
		var item admindomain.User
		if err := rows.Scan(&item.ID, &item.Name, &item.Role, &item.Phone, &item.Orders, &item.Status); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *AdminRepository) ListReviews(ctx context.Context, limit int) ([]admindomain.Review, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	const query = `
SELECT
	r.id,
	r.order_id,
	r.driver_id,
	COALESCE(v.full_name, r.driver_id) AS driver_name,
	r.client_id,
	r.client_id AS client_name,
	r.stars,
	r.text,
	r.created_at
FROM driver_reviews r
LEFT JOIN driver_verifications v ON v.user_id = r.driver_id
ORDER BY r.created_at DESC
LIMIT $1`

	rows, err := r.db.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]admindomain.Review, 0, limit)
	for rows.Next() {
		var item admindomain.Review
		if err := rows.Scan(
			&item.ID,
			&item.OrderID,
			&item.DriverID,
			&item.DriverName,
			&item.ClientID,
			&item.ClientName,
			&item.Stars,
			&item.Text,
			&item.CreatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *AdminRepository) CreateReview(ctx context.Context, item admindomain.Review) error {
	const query = `
INSERT INTO driver_reviews (id, order_id, driver_id, client_id, stars, text, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7)`

	_, err := r.db.ExecContext(
		ctx,
		query,
		item.ID,
		item.OrderID,
		item.DriverID,
		item.ClientID,
		item.Stars,
		item.Text,
		item.CreatedAt,
	)
	return err
}

func (r *AdminRepository) GetDriverReviews(ctx context.Context, driverID string, limit int) ([]admindomain.Review, httptransport.DriverReviewsStats, error) {
	// Get reviews
	const reviewQuery = `
		SELECT
			dr.id,
			dr.order_id,
			dr.driver_id,
			dr.client_id,
			dr.stars,
			COALESCE(dr.comment, dr.text, '') as text,
			dr.created_at,
			COALESCE(driver.full_name, '') as driver_name,
			COALESCE(client.full_name, '') as client_name
		FROM driver_reviews dr
		LEFT JOIN users driver ON dr.driver_id = driver.id
		LEFT JOIN users client ON dr.client_id = client.id
		WHERE dr.driver_id = $1
		ORDER BY dr.created_at DESC
		LIMIT $2`

	rows, err := r.db.QueryContext(ctx, reviewQuery, driverID, limit)
	if err != nil {
		return nil, httptransport.DriverReviewsStats{}, err
	}
	defer rows.Close()

	var items []admindomain.Review
	for rows.Next() {
		var item admindomain.Review
		if err := rows.Scan(
			&item.ID,
			&item.OrderID,
			&item.DriverID,
			&item.ClientID,
			&item.Stars,
			&item.Text,
			&item.CreatedAt,
			&item.DriverName,
			&item.ClientName,
		); err != nil {
			return nil, httptransport.DriverReviewsStats{}, err
		}
		items = append(items, item)
	}

	// Get stats
	const statsQuery = `
		SELECT
			COUNT(*) as total,
			COALESCE(AVG(stars), 0) as rating_average,
			COUNT(*) as rating_count
		FROM driver_reviews
		WHERE driver_id = $1`

	var stats httptransport.DriverReviewsStats
	err = r.db.QueryRowContext(ctx, statsQuery, driverID).Scan(
		&stats.Total,
		&stats.RatingAverage,
		&stats.RatingCount,
	)
	if err != nil {
		return nil, httptransport.DriverReviewsStats{}, err
	}

	return items, stats, rows.Err()
}

func (r *AdminRepository) GetOrderReview(ctx context.Context, orderID string) (*admindomain.Review, error) {
	const query = `
		SELECT
			dr.id,
			dr.order_id,
			dr.driver_id,
			dr.client_id,
			dr.stars,
			COALESCE(dr.comment, dr.text, '') as text,
			dr.created_at,
			COALESCE(driver.full_name, '') as driver_name,
			COALESCE(client.full_name, '') as client_name
		FROM driver_reviews dr
		LEFT JOIN users driver ON dr.driver_id = driver.id
		LEFT JOIN users client ON dr.client_id = client.id
		WHERE dr.order_id = $1`

	var item admindomain.Review
	err := r.db.QueryRowContext(ctx, query, orderID).Scan(
		&item.ID,
		&item.OrderID,
		&item.DriverID,
		&item.ClientID,
		&item.Stars,
		&item.Text,
		&item.CreatedAt,
		&item.DriverName,
		&item.ClientName,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}

	return &item, nil
}

func (r *AdminRepository) ListTaxProfiles(ctx context.Context, limit int) ([]httptransport.AdminTaxProfile, error) {
	query := `
		SELECT
			dtp.driver_id,
			dtp.inn,
			dtp.taxpayer_type,
			dtp.verification_status,
			dtp.created_at,
			dtp.updated_at,
			COALESCE(u.full_name, '') as full_name
		FROM driver_tax_profiles dtp
		LEFT JOIN users u ON dtp.driver_id = u.id
		ORDER BY dtp.created_at DESC
		LIMIT $1
	`

	rows, err := r.db.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []httptransport.AdminTaxProfile
	for rows.Next() {
		var profile httptransport.AdminTaxProfile
		if err := rows.Scan(
			&profile.DriverID,
			&profile.INN,
			&profile.TaxpayerType,
			&profile.VerificationStatus,
			&profile.CreatedAt,
			&profile.UpdatedAt,
			&profile.FullName,
		); err != nil {
			return nil, err
		}
		profiles = append(profiles, profile)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return profiles, nil
}

func (r *AdminRepository) UpdateTaxProfileStatus(ctx context.Context, driverID, status, adminComments string) error {
	query := `
		UPDATE driver_tax_profiles
		SET verification_status = $2, updated_at = NOW()
		WHERE driver_id = $1
	`

	result, err := r.db.ExecContext(ctx, query, driverID, status)
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if rowsAffected == 0 {
		return errors.New("tax profile not found")
	}

	return nil
}

func decodeStringList(raw string) []string {
	if raw == "" {
		return []string{}
	}
	var out []string
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return []string{}
	}
	if out == nil {
		return []string{}
	}
	return out
}

func IsNotFound(err error) bool {
	return errors.Is(err, sql.ErrNoRows)
}
