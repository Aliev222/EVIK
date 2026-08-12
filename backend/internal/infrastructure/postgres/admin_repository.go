package postgres

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	admindomain "evik/backend/internal/domain/admin"
	orderdomain "evik/backend/internal/domain/order"
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
-- Finance KPI. All money in kopecks (BIGINT).
gmv_today AS (
	SELECT COALESCE(SUM(price_total), 0) AS amount
	FROM orders WHERE status = 'completed' AND created_at >= DATE_TRUNC('day', NOW())
),
gmv_month AS (
	SELECT COALESCE(SUM(price_total), 0) AS amount
	FROM orders WHERE status = 'completed' AND created_at >= DATE_TRUNC('month', NOW())
),
commission_today AS (
	SELECT COALESCE(SUM(amount), 0) AS amount
	FROM wallet_transactions
	WHERE type IN ('commission','cash_commission_debt')
	AND created_at >= DATE_TRUNC('day', NOW())
),
commission_month AS (
	SELECT COALESCE(SUM(amount), 0) AS amount
	FROM wallet_transactions
	WHERE type IN ('commission','cash_commission_debt')
	AND created_at >= DATE_TRUNC('month', NOW())
),
payouts_today AS (
	SELECT COALESCE(SUM(amount), 0) AS amount
	FROM payouts WHERE status = 'paid' AND created_at >= DATE_TRUNC('day', NOW())
),
payouts_month AS (
	SELECT COALESCE(SUM(amount), 0) AS amount
	FROM payouts WHERE status = 'paid' AND created_at >= DATE_TRUNC('month', NOW())
),
payouts_pending AS (
	SELECT COALESCE(SUM(amount), 0) AS amount
	FROM payouts WHERE status IN ('created','processing','manual_review')
),
failed_payments AS (
	SELECT COUNT(*) AS count FROM payments WHERE status IN ('failed','canceled')
),
failed_payouts AS (
	SELECT COUNT(*) AS count FROM payouts WHERE status = 'failed'
),
subs_today AS (
	SELECT COALESCE(SUM(amount), 0) AS amount
	FROM subscriptions WHERE status = 'active' AND created_at >= DATE_TRUNC('day', NOW())
),
subs_month AS (
	SELECT COALESCE(SUM(amount), 0) AS amount
	FROM subscriptions WHERE status = 'active' AND created_at >= DATE_TRUNC('month', NOW())
),
cash_debt_total AS (
	SELECT COALESCE(SUM(debt_balance), 0) AS amount FROM driver_wallets
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
	COALESCE(SUM(o.price_total), 0) AS amount
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
	COALESCE(SUM(wt.amount), 0) AS amount
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
	// Shared guard so the single- and batch-moderation flows enforce exactly
	// the same rules no matter how the admin UI is rebuilt.
	if err := decision.Validate(); err != nil {
		return err
	}
	decision.VehiclePlate = strings.ToUpper(strings.TrimSpace(decision.VehiclePlate))
	decision.VehicleModel = strings.TrimSpace(decision.VehicleModel)
	decision.VehicleType = strings.TrimSpace(decision.VehicleType)

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Approvals are only meaningful from an open verification round. Rejecting
	// a re-approve of an approved / rejected / blocked record loudly (instead
	// of silently overwriting a terminal state).
	if decision.Status == admindomain.VerificationStatusApproved {
		var currentStatus string
		err := tx.QueryRowContext(ctx,
			`SELECT status FROM driver_verifications WHERE id = $1`,
			decision.ID,
		).Scan(&currentStatus)
		if err != nil {
			return err // sql.ErrNoRows → 404 at the API layer
		}
		if !admindomain.ApprovalAllowedFrom(currentStatus) {
			return admindomain.ErrInvalidDecisionStatus
		}
	}

	// When approving, overwrite vehicle columns with the values the admin
	// entered in the approval form. For other status transitions we leave
	// them alone — they may have been set by an earlier approval.
	var result sql.Result
	if decision.Status == admindomain.VerificationStatusApproved && decision.VehiclePlate != "" {
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

func (r *AdminRepository) ListReviews(ctx context.Context, limit int, offset int, stars int, driverQuery string) ([]admindomain.Review, int64, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	args := make([]any, 0, 4)
	conditions := make([]string, 0, 3)
	argIdx := 1

	if stars > 0 {
		conditions = append(conditions, fmt.Sprintf("r.stars = $%d", argIdx))
		args = append(args, stars)
		argIdx++
	}
	if driverQuery != "" {
		conditions = append(conditions, fmt.Sprintf("(r.driver_id ILIKE $%d OR COALESCE(v.full_name, '') ILIKE $%d)", argIdx, argIdx))
		args = append(args, "%"+driverQuery+"%")
		argIdx++
	}

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = "WHERE " + strings.Join(conditions, " AND ")
	}

	// Count query
	countQuery := fmt.Sprintf(`
SELECT COUNT(*)
FROM driver_reviews r
LEFT JOIN driver_verifications v ON v.user_id = r.driver_id
%s`, whereClause)

	var total int64
	if err := r.db.QueryRowContext(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	// Data query
	dataQuery := fmt.Sprintf(`
SELECT
	r.id,
	r.order_id,
	r.driver_id,
	COALESCE(v.full_name, r.driver_id) AS driver_name,
	r.client_id,
	r.client_id AS client_name,
	r.stars,
	r.comment,
	r.is_hidden,
	r.created_at
FROM driver_reviews r
LEFT JOIN driver_verifications v ON v.user_id = r.driver_id
%s
ORDER BY r.created_at DESC
LIMIT $%d OFFSET $%d`, whereClause, argIdx, argIdx+1)

	args = append(args, limit, offset)

	rows, err := r.db.QueryContext(ctx, dataQuery, args...)
	if err != nil {
		return nil, 0, err
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
			&item.IsHidden,
			&item.CreatedAt,
		); err != nil {
			return nil, 0, err
		}
		items = append(items, item)
	}
	return items, total, rows.Err()
}

func (r *AdminRepository) CreateReview(ctx context.Context, item admindomain.Review) error {
	const query = `
INSERT INTO driver_reviews (id, order_id, driver_id, client_id, stars, comment, created_at)
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

func (r *AdminRepository) HideReview(ctx context.Context, id string) error {
	result, err := r.db.ExecContext(ctx, `UPDATE driver_reviews SET is_hidden = true WHERE id = $1`, id)
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
	return nil
}

func (r *AdminRepository) ShowReview(ctx context.Context, id string) error {
	result, err := r.db.ExecContext(ctx, `UPDATE driver_reviews SET is_hidden = false WHERE id = $1`, id)
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
	return nil
}

func (r *AdminRepository) DeleteReview(ctx context.Context, id string) error {
	result, err := r.db.ExecContext(ctx, `DELETE FROM driver_reviews WHERE id = $1`, id)
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
	return nil
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
			COALESCE(dr.comment, '') as comment,
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

	items := make([]admindomain.Review, 0)
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
			COALESCE(dr.comment, '') as comment,
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

func (r *AdminRepository) ListAdminPayments(ctx context.Context, limit, offset int) ([]httptransport.AdminListPayment, int64, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	var total int64
	if err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM payments`).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT id, order_id, user_id, provider, COALESCE(provider_payment_id,''), payment_method, amount, currency, status, created_at
FROM payments ORDER BY created_at DESC LIMIT $1 OFFSET $2`, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]httptransport.AdminListPayment, 0, limit)
	for rows.Next() {
		var item httptransport.AdminListPayment
		var createdAt time.Time
		if err := rows.Scan(&item.ID, &item.OrderID, &item.UserID, &item.Provider, &item.ProviderPayment, &item.PaymentMethod, &item.Amount, &item.Currency, &item.Status, &createdAt); err != nil {
			return nil, 0, err
		}
		item.CreatedAt = createdAt.Format(time.RFC3339)
		items = append(items, item)
	}
	return items, total, rows.Err()
}

func (r *AdminRepository) ListAdminWallets(ctx context.Context, limit, offset int, search string) ([]httptransport.AdminListWallet, int64, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	args := []any{limit, offset}
	where := ""
	argIdx := 3
	if search != "" {
		where = fmt.Sprintf("WHERE driver_id::text ILIKE $%d", argIdx)
		args = append(args, "%"+search+"%")
	}
	var total int64
	countQuery := fmt.Sprintf(`SELECT COUNT(*) FROM driver_wallets %s`, where)
	if err := r.db.QueryRowContext(ctx, countQuery, args[2:]...).Scan(&total); err != nil {
		return nil, 0, err
	}
	// balances stored in kopecks (BIGINT) since migration 20260603
	query := fmt.Sprintf(`
SELECT id, driver_id, available_balance, pending_balance, debt_balance, currency, updated_at
FROM driver_wallets %s ORDER BY updated_at DESC NULLS LAST LIMIT $1 OFFSET $2`, where)
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]httptransport.AdminListWallet, 0, limit)
	for rows.Next() {
		var item httptransport.AdminListWallet
		var updatedAt sql.NullTime
		if err := rows.Scan(&item.ID, &item.DriverID, &item.Available, &item.Pending, &item.Debt, &item.Currency, &updatedAt); err != nil {
			return nil, 0, err
		}
		if updatedAt.Valid {
			item.UpdatedAt = updatedAt.Time.Format(time.RFC3339)
		}
		items = append(items, item)
	}
	return items, total, rows.Err()
}

func (r *AdminRepository) ListAdminTransactions(ctx context.Context, limit, offset int, txType, driverID string) ([]httptransport.AdminListTransaction, int64, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	args := []any{limit, offset}
	conditions := []string{}
	argIdx := 3
	if txType != "" {
		conditions = append(conditions, fmt.Sprintf("type = $%d", argIdx))
		args = append(args, txType)
		argIdx++
	}
	if driverID != "" {
		conditions = append(conditions, fmt.Sprintf("driver_id = $%d", argIdx))
		args = append(args, driverID)
		argIdx++
	}
	where := ""
	if len(conditions) > 0 {
		where = "WHERE " + strings.Join(conditions, " AND ")
	}
	var total int64
	countQuery := fmt.Sprintf(`SELECT COUNT(*) FROM wallet_transactions %s`, where)
	if err := r.db.QueryRowContext(ctx, countQuery, args[2:]...).Scan(&total); err != nil {
		return nil, 0, err
	}
	query := fmt.Sprintf(`
SELECT COALESCE(id,''), COALESCE(wallet_id,''), COALESCE(driver_id,''), COALESCE(order_id,''), COALESCE(payment_id,''), COALESCE(payout_id,''),
	type, direction, amount, currency, status, COALESCE(description,''), created_at
FROM wallet_transactions %s ORDER BY created_at DESC LIMIT $1 OFFSET $2`, where)
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]httptransport.AdminListTransaction, 0, limit)
	for rows.Next() {
		var item httptransport.AdminListTransaction
		var createdAt time.Time
		if err := rows.Scan(&item.ID, &item.WalletID, &item.DriverID, &item.OrderID, &item.PaymentID, &item.PayoutID, &item.Type, &item.Direction, &item.Amount, &item.Currency, &item.Status, &item.Description, &createdAt); err != nil {
			return nil, 0, err
		}
		item.CreatedAt = createdAt.Format(time.RFC3339)
		items = append(items, item)
	}
	return items, total, rows.Err()
}

func (r *AdminRepository) ListAdminSubscriptions(ctx context.Context, limit, offset int, status string) ([]httptransport.AdminListSubscription, int64, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	args := []any{limit, offset}
	where := ""
	if status != "" {
		where = "WHERE status = $3"
		args = append(args, status)
	}
	var total int64
	countQuery := fmt.Sprintf(`SELECT COUNT(*) FROM subscriptions %s`, where)
	if err := r.db.QueryRowContext(ctx, countQuery, args[2:]...).Scan(&total); err != nil {
		return nil, 0, err
	}
	query := fmt.Sprintf(`
SELECT COALESCE(id,''), COALESCE(driver_id,''), COALESCE(plan_id,''), COALESCE(payment_id,''), amount, currency, status, created_at
FROM subscriptions %s ORDER BY created_at DESC LIMIT $1 OFFSET $2`, where)
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]httptransport.AdminListSubscription, 0, limit)
	for rows.Next() {
		var item httptransport.AdminListSubscription
		var createdAt time.Time
		if err := rows.Scan(&item.ID, &item.DriverID, &item.PlanID, &item.PaymentID, &item.Amount, &item.Currency, &item.Status, &createdAt); err != nil {
			return nil, 0, err
		}
		item.CreatedAt = createdAt.Format(time.RFC3339)
		items = append(items, item)
	}
	return items, total, rows.Err()
}

func (r *AdminRepository) ListAuditLog(ctx context.Context, limit, offset int, entityType, action string) ([]httptransport.AdminAuditLogEntry, int64, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	args := []any{limit, offset}
	conditions := []string{}
	argIdx := 3
	if entityType != "" {
		conditions = append(conditions, fmt.Sprintf("entity_type = $%d", argIdx))
		args = append(args, entityType)
		argIdx++
	}
	if action != "" {
		conditions = append(conditions, fmt.Sprintf("action = $%d", argIdx))
		args = append(args, action)
		argIdx++
	}
	where := ""
	if len(conditions) > 0 {
		where = "WHERE " + strings.Join(conditions, " AND ")
	}
	var total int64
	countQuery := fmt.Sprintf(`SELECT COUNT(*) FROM moderation_audit_log %s`, where)
	if err := r.db.QueryRowContext(ctx, countQuery, args[2:]...).Scan(&total); err != nil {
		return nil, 0, err
	}
	query := fmt.Sprintf(`
SELECT id, entity_type, entity_id, action, COALESCE(reason,'') as reason, COALESCE(moderator_id,'') as moderator_id, created_at
FROM moderation_audit_log %s ORDER BY created_at DESC LIMIT $1 OFFSET $2`, where)
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]httptransport.AdminAuditLogEntry, 0, limit)
	for rows.Next() {
		var item httptransport.AdminAuditLogEntry
		var createdAt time.Time
		if err := rows.Scan(&item.ID, &item.EntityType, &item.EntityID, &item.Action, &item.Reason, &item.ModeratorID, &createdAt); err != nil {
			return nil, 0, err
		}
		item.CreatedAt = createdAt.Format(time.RFC3339)
		items = append(items, item)
	}
	return items, total, rows.Err()
}

func (r *AdminRepository) GetDriverDetail(ctx context.Context, driverID string) (*httptransport.AdminDriverDetail, error) {
	// Get basic info + verification
	var detail httptransport.AdminDriverDetail

	// Try to find driver by driver_id or user_id
	const driverQuery = `
SELECT
	COALESCE(d.id, '') AS driver_id,
	COALESCE(d.user_id, '') AS user_id,
	COALESCE(v.full_name, '') AS full_name,
	COALESCE(v.phone, '') AS phone,
	COALESCE(d.status, 'offline') AS status,
	COALESCE((SELECT COUNT(*) FROM orders o WHERE o.driver_id = $1), 0) AS orders_count
FROM drivers d
LEFT JOIN driver_verifications v ON v.user_id = d.id OR v.user_id = d.user_id
WHERE d.id = $1 OR d.user_id = $1
LIMIT 1`

	err := r.db.QueryRowContext(ctx, driverQuery, driverID).Scan(
		&detail.DriverID,
		&detail.UserID,
		&detail.FullName,
		&detail.Phone,
		&detail.Status,
		&detail.OrdersCount,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}

	// Verification info
	const verifQuery = `
SELECT id, vehicle_model, vehicle_plate, vehicle_type, status, risk, submitted_at, documents_json, decision_reason
FROM driver_verifications
WHERE user_id = $1
LIMIT 1`
	var verifID, vehicle, plate, vtype, vstatus, risk string
	var submittedAt sql.NullTime
	var documentsJSON sql.NullString
	var decisionReason *string
	err = r.db.QueryRowContext(ctx, verifQuery, driverID).Scan(
		&verifID, &vehicle, &plate, &vtype, &vstatus, &risk, &submittedAt, &documentsJSON, &decisionReason,
	)
	if err == nil {
		docs := []string{}
		if documentsJSON.Valid && documentsJSON.String != "" {
			docs = decodeStringList(documentsJSON.String)
		}
		submitted := ""
		if submittedAt.Valid {
			submitted = submittedAt.Time.Format(time.RFC3339)
		}
		detail.Verification = &httptransport.AdminVerificationInfo{
			ID:             verifID,
			Vehicle:        vehicle,
			Plate:          plate,
			VehicleType:    vtype,
			Status:         vstatus,
			Risk:           risk,
			SubmittedAt:    submitted,
			Documents:      docs,
			DecisionReason: decisionReason,
		}
	}

	// Tax profile
	const taxQuery = `
SELECT COALESCE(inn, ''), COALESCE(taxpayer_type, ''), COALESCE(verification_status, ''), created_at
FROM driver_tax_profiles WHERE driver_id = $1 LIMIT 1`
	var inn, taxpayerType, taxStatus string
	var taxCreatedAt sql.NullTime
	err = r.db.QueryRowContext(ctx, taxQuery, driverID).Scan(&inn, &taxpayerType, &taxStatus, &taxCreatedAt)
	if err == nil {
		created := ""
		if taxCreatedAt.Valid {
			created = taxCreatedAt.Time.Format(time.RFC3339)
		}
		detail.TaxProfile = &httptransport.AdminTaxProfileInfo{
			INN:                inn,
			TaxpayerType:       taxpayerType,
			VerificationStatus: taxStatus,
			CreatedAt:          created,
		}
	}

	// Wallet
	// balances stored in kopecks (BIGINT) since migration 20260603
	const walletQuery = `
SELECT COALESCE(available_balance, 0), COALESCE(pending_balance, 0), COALESCE(debt_balance, 0), COALESCE(currency, 'RUB'), updated_at
FROM driver_wallets WHERE driver_id = $1 LIMIT 1`
	var avail, pending, debt int64
	var currency string
	var walletUpdatedAt sql.NullTime
	err = r.db.QueryRowContext(ctx, walletQuery, driverID).Scan(&avail, &pending, &debt, &currency, &walletUpdatedAt)
	if err == nil {
		updated := ""
		if walletUpdatedAt.Valid {
			updated = walletUpdatedAt.Time.Format(time.RFC3339)
		}
		detail.Wallet = &httptransport.AdminWalletInfo{
			Available: avail,
			Pending:   pending,
			Debt:      debt,
			Currency:  currency,
			UpdatedAt: updated,
		}
	}

	// Reviews summary
	const reviewStatsQuery = `
SELECT COUNT(*), COALESCE(AVG(stars), 0), COUNT(*)
FROM driver_reviews WHERE driver_id = $1 AND is_hidden = false`
	var revTotal int
	var revAvg float64
	var revCount int
	err = r.db.QueryRowContext(ctx, reviewStatsQuery, driverID).Scan(&revTotal, &revAvg, &revCount)
	if err == nil {
		detail.Reviews = &httptransport.AdminReviewsSummary{
			Total:         revTotal,
			RatingAverage: revAvg,
			RatingCount:   revCount,
		}
	}

	// If no phone was found in verification, try users table
	if detail.Phone == "" {
		_ = r.db.QueryRowContext(ctx, `SELECT COALESCE(phone, '') FROM users WHERE id = $1 LIMIT 1`, driverID).Scan(&detail.Phone)
	}

	return &detail, nil
}

func (r *AdminRepository) ListDriverOrders(ctx context.Context, driverID string, limit int, offset int) ([]orderdomain.AdminOrderListItem, int64, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	var total int64
	err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM orders WHERE driver_id = $1`, driverID).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	const query = `
SELECT
	o.id, o.user_id, '', '', o.driver_id, '', '',
	o.status, o.payment_method, '',
	o.price_total, o.commission_amount, o.driver_amount,
	o.created_at, o.financially_completed_at, o.cancelled_at
FROM orders o
WHERE o.driver_id = $1
ORDER BY o.created_at DESC
LIMIT $2 OFFSET $3`

	rows, err := r.db.QueryContext(ctx, query, driverID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]orderdomain.AdminOrderListItem, 0, limit)
	for rows.Next() {
		var item orderdomain.AdminOrderListItem
		if err := rows.Scan(
			&item.OrderID, &item.ClientID, &item.ClientName, &item.ClientPhone,
			&item.DriverID, &item.DriverName, &item.DriverPhone,
			&item.Status, &item.PaymentMethod, &item.PaymentStatus,
			&item.PriceTotal, &item.CommissionAmount, &item.DriverAmount,
			&item.CreatedAt, &item.CompletedAt, &item.CancelledAt,
		); err != nil {
			return nil, 0, err
		}
		item.FinancialStatus = ""
		items = append(items, item)
	}
	return items, total, rows.Err()
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
