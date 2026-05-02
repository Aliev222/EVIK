package postgres

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"

	admindomain "evik/backend/internal/domain/admin"
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
)
SELECT
	(SELECT count FROM clients) + (SELECT count FROM drivers_count) AS total_users,
	(SELECT count FROM clients) AS clients,
	(SELECT count FROM drivers_count) AS drivers,
	(SELECT count FROM online_drivers) AS online_drivers,
	(SELECT count FROM pending_moderations) AS pending_moderations,
	(SELECT value FROM avg_reviews) AS average_driver_stars,
	(SELECT count FROM reviews_today) AS reviews_today,
	(SELECT count FROM active_orders) AS active_orders`

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
	)
	return out, err
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
	id string,
	status string,
	reason string,
	moderatorID string,
	auditID string,
	now time.Time,
) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	result, err := tx.ExecContext(ctx, `
UPDATE driver_verifications
SET status = $2, decision_reason = $3, reviewed_by = $4, reviewed_at = $5, updated_at = $5
WHERE id = $1`,
		id,
		status,
		reason,
		moderatorID,
		now,
	)
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
		auditID,
		id,
		status,
		reason,
		moderatorID,
		now,
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
