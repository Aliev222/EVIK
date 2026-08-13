package user

import (
	"context"
	"time"
)

type Repository interface {
	GetByID(ctx context.Context, id string) (*User, error)
	GetByPhoneAndRole(ctx context.Context, phone string, role string) (*User, error)
	Create(ctx context.Context, user *User) error
	UpdatePasswordHash(ctx context.Context, userID string, passwordHash string) error
	// IsUserActive reports whether the user row exists and is not deleted or
	// blocked. Unknown ids (e.g. a removed row) are treated as not active so
	// stale JWTs stop working; this is used by the auth middleware to reject
	// deleted accounts immediately.
	IsUserActive(ctx context.Context, userID string) (bool, error)
	CreateRefreshSession(ctx context.Context, session *RefreshSession) error
	GetActiveRefreshSessionByHash(ctx context.Context, tokenHash string) (*RefreshSession, error)
	RevokeRefreshSession(ctx context.Context, sessionID string, revokedAt time.Time) error
	CreatePhoneOTP(ctx context.Context, otp *PhoneOTP) error
	ConsumePhoneOTP(ctx context.Context, phone string, role string, codeHash string, now time.Time) (*PhoneOTP, error)
	UpsertDeviceToken(ctx context.Context, token *DeviceToken) error
	RevokeDeviceToken(ctx context.Context, userID string, role string, fcmToken string, revokedAt time.Time) error
	UpsertTaxProfile(ctx context.Context, profile *TaxProfile) error
	GetTaxProfile(ctx context.Context, driverID string) (*TaxProfile, error)
	// UpdateNPDConnection writes the Moy Nalog tokens + status returned by
	// the NPD provider after the driver connected our partner integration.
	// fnsFullName is mirrored into users.fns_full_name for audit.
	UpdateNPDConnection(ctx context.Context, driverID string, result NPDConnectionResult, now time.Time) error
	// MarkNPDRevoked is called when FNS notifies us that the driver revoked
	// access (or when our own auth attempt fails with a permanent error).
	MarkNPDRevoked(ctx context.Context, driverID string, now time.Time) error
	IsDriverTaxVerified(ctx context.Context, driverID string) (bool, error)
	IsDriverDocumentsApproved(ctx context.Context, driverID string) (bool, error)
	IsDriverSubscriptionActive(ctx context.Context, driverID string, now time.Time) (bool, error)
}
