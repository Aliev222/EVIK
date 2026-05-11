package postgres

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"evik/backend/internal/auth"
	userdomain "evik/backend/internal/domain/user"
)

type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(ctx context.Context, user *userdomain.User) error {
	const query = `
INSERT INTO users (id, phone, full_name, role, password_hash, status, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
	_, err := r.db.ExecContext(ctx, query, user.ID, user.Phone, user.Name, string(user.Role), user.PasswordHash, string(user.Status), user.CreatedAt, user.UpdatedAt)
	if err != nil && isUniqueViolation(err) {
		return userdomain.ErrUserAlreadyExists
	}
	return err
}

func (r *UserRepository) GetByID(ctx context.Context, id string) (*userdomain.User, error) {
	const query = `
SELECT id, phone, full_name, role, password_hash, status, created_at, updated_at
FROM users
WHERE id = $1`
	return r.scanUser(r.db.QueryRowContext(ctx, query, id))
}

func (r *UserRepository) GetByPhoneAndRole(ctx context.Context, phone string, role string) (*userdomain.User, error) {
	const query = `
SELECT id, phone, full_name, role, password_hash, status, created_at, updated_at
FROM users
WHERE phone = $1 AND role = $2`
	return r.scanUser(r.db.QueryRowContext(ctx, query, phone, role))
}

func (r *UserRepository) UpdatePasswordHash(ctx context.Context, userID string, passwordHash string) error {
	res, err := r.db.ExecContext(ctx, `UPDATE users SET password_hash = $2, updated_at = NOW() WHERE id = $1`, userID, passwordHash)
	if err != nil {
		return err
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		return userdomain.ErrUserNotFound
	}
	return nil
}

func (r *UserRepository) CreateRefreshSession(ctx context.Context, session *userdomain.RefreshSession) error {
	const query = `
INSERT INTO user_refresh_sessions (id, user_id, role, token_hash, expires_at, revoked_at, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7)`
	_, err := r.db.ExecContext(ctx, query, session.ID, session.UserID, string(session.Role), session.TokenHash, session.ExpiresAt, session.RevokedAt, session.CreatedAt)
	return err
}

func (r *UserRepository) GetActiveRefreshSessionByHash(ctx context.Context, tokenHash string) (*userdomain.RefreshSession, error) {
	const query = `
SELECT id, user_id, role, token_hash, expires_at, revoked_at, created_at
FROM user_refresh_sessions
WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > NOW()`
	var session userdomain.RefreshSession
	var role string
	err := r.db.QueryRowContext(ctx, query, tokenHash).Scan(&session.ID, &session.UserID, &role, &session.TokenHash, &session.ExpiresAt, &session.RevokedAt, &session.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, userdomain.ErrSessionNotFound
		}
		return nil, err
	}
	session.Role = auth.Role(role)
	return &session, nil
}

func (r *UserRepository) RevokeRefreshSession(ctx context.Context, sessionID string, revokedAt time.Time) error {
	_, err := r.db.ExecContext(ctx, `UPDATE user_refresh_sessions SET revoked_at = $2 WHERE id = $1`, sessionID, revokedAt)
	return err
}

func (r *UserRepository) CreatePhoneOTP(ctx context.Context, otp *userdomain.PhoneOTP) error {
	const query = `
INSERT INTO phone_otps (id, phone, role, code_hash, expires_at, consumed_at, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7)`
	_, err := r.db.ExecContext(ctx, query, otp.ID, otp.Phone, string(otp.Role), otp.CodeHash, otp.ExpiresAt, otp.ConsumedAt, otp.CreatedAt)
	return err
}

func (r *UserRepository) ConsumePhoneOTP(ctx context.Context, phone string, role string, codeHash string, now time.Time) (*userdomain.PhoneOTP, error) {
	const query = `
UPDATE phone_otps
SET consumed_at = $5
WHERE id = (
	SELECT id FROM phone_otps
	WHERE phone = $1 AND role = $2 AND code_hash = $3 AND consumed_at IS NULL AND expires_at > $4
	ORDER BY created_at DESC
	LIMIT 1
)
RETURNING id, phone, role, code_hash, expires_at, consumed_at, created_at`
	var otp userdomain.PhoneOTP
	var rawRole string
	err := r.db.QueryRowContext(ctx, query, phone, role, codeHash, now, now).Scan(&otp.ID, &otp.Phone, &rawRole, &otp.CodeHash, &otp.ExpiresAt, &otp.ConsumedAt, &otp.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, userdomain.ErrOTPNotFound
		}
		return nil, err
	}
	otp.Role = auth.Role(rawRole)
	return &otp, nil
}

func (r *UserRepository) UpsertTaxProfile(ctx context.Context, profile *userdomain.TaxProfile) error {
	const query = `
INSERT INTO driver_tax_profiles (driver_id, inn, taxpayer_type, verification_status, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (driver_id) DO UPDATE SET
	inn = EXCLUDED.inn,
	taxpayer_type = EXCLUDED.taxpayer_type,
	verification_status = EXCLUDED.verification_status,
	updated_at = EXCLUDED.updated_at`
	_, err := r.db.ExecContext(ctx, query, profile.DriverID, profile.INN, profile.TaxpayerType, profile.VerificationStatus, profile.CreatedAt, profile.UpdatedAt)
	return err
}

func (r *UserRepository) GetTaxProfile(ctx context.Context, driverID string) (*userdomain.TaxProfile, error) {
	const query = `
SELECT driver_id, inn, taxpayer_type, verification_status, created_at, updated_at,
       COALESCE(npd_access_token, ''),
       COALESCE(npd_refresh_token, ''),
       npd_token_expires_at,
       npd_connected_at,
       npd_revoked_at,
       COALESCE(npd_connection_status, 'not_connected')
FROM driver_tax_profiles
WHERE driver_id = $1`
	var profile userdomain.TaxProfile
	err := r.db.QueryRowContext(ctx, query, driverID).Scan(
		&profile.DriverID, &profile.INN, &profile.TaxpayerType, &profile.VerificationStatus,
		&profile.CreatedAt, &profile.UpdatedAt,
		&profile.NPDAccessToken, &profile.NPDRefreshToken,
		&profile.NPDTokenExpiresAt, &profile.NPDConnectedAt, &profile.NPDRevokedAt,
		&profile.NPDConnectionStatus,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, userdomain.ErrTaxProfileNotFound
		}
		return nil, err
	}
	return &profile, nil
}

// UpdateNPDConnection writes Moy Nalog OAuth2 tokens into the existing
// driver_tax_profiles row. The row must already exist (the driver had to
// submit their INN via UpsertTaxProfile before connecting Moy Nalog).
// Also mirrors the FNS full name into users.fns_full_name so the admin
// can later see the official name from FNS alongside whatever was typed
// during onboarding.
func (r *UserRepository) UpdateNPDConnection(ctx context.Context, driverID string, result userdomain.NPDConnectionResult, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(ctx, `
UPDATE driver_tax_profiles
SET inn = $2,
    npd_access_token = $3,
    npd_refresh_token = $4,
    npd_token_expires_at = $5,
    npd_connected_at = $6,
    npd_revoked_at = NULL,
    npd_connection_status = 'connected',
    updated_at = $6
WHERE driver_id = $1`,
		driverID, result.INN, result.AccessToken, result.RefreshToken, result.ExpiresAt, now,
	)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return userdomain.ErrTaxProfileNotFound
	}

	if strings.TrimSpace(result.FullName) != "" {
		if _, err := tx.ExecContext(ctx, `UPDATE users SET fns_full_name = $2, updated_at = $3 WHERE id = $1`, driverID, result.FullName, now); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// MarkNPDRevoked flips the profile to "revoked" — tokens are wiped so
// stale auth attempts don't keep firing at FNS. Called when the driver
// disconnects from their side or when FNS rejects the refresh token.
func (r *UserRepository) MarkNPDRevoked(ctx context.Context, driverID string, now time.Time) error {
	res, err := r.db.ExecContext(ctx, `
UPDATE driver_tax_profiles
SET npd_access_token = NULL,
    npd_refresh_token = NULL,
    npd_token_expires_at = NULL,
    npd_revoked_at = $2,
    npd_connection_status = 'revoked',
    updated_at = $2
WHERE driver_id = $1`, driverID, now)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return userdomain.ErrTaxProfileNotFound
	}
	return nil
}

func (r *UserRepository) IsDriverTaxVerified(ctx context.Context, driverID string) (bool, error) {
	var ok bool
	err := r.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM driver_tax_profiles WHERE driver_id = $1 AND verification_status = 'verified')`, driverID).Scan(&ok)
	return ok, err
}

func (r *UserRepository) IsDriverDocumentsApproved(ctx context.Context, driverID string) (bool, error) {
	var ok bool
	err := r.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM driver_verifications WHERE user_id = $1 AND status = 'approved')`, driverID).Scan(&ok)
	return ok, err
}

func (r *UserRepository) IsDriverSubscriptionActive(ctx context.Context, driverID string, now time.Time) (bool, error) {
	var ok bool
	err := r.db.QueryRowContext(ctx, `
SELECT EXISTS(
	SELECT 1 FROM subscriptions
	WHERE driver_id = $1 AND status = 'active' AND (ends_at IS NULL OR ends_at > $2)
)`, driverID, now).Scan(&ok)
	return ok, err
}

func (r *UserRepository) scanUser(row *sql.Row) (*userdomain.User, error) {
	var user userdomain.User
	var role string
	var status string
	err := row.Scan(&user.ID, &user.Phone, &user.Name, &role, &user.PasswordHash, &status, &user.CreatedAt, &user.UpdatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, userdomain.ErrUserNotFound
		}
		return nil, err
	}
	user.Role = auth.Role(role)
	user.Status = userdomain.Status(status)
	return &user, nil
}

func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	text := strings.ToLower(err.Error())
	return strings.Contains(text, "23505") || strings.Contains(text, "unique")
}
