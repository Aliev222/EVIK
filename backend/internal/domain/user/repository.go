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
	CreateRefreshSession(ctx context.Context, session *RefreshSession) error
	GetActiveRefreshSessionByHash(ctx context.Context, tokenHash string) (*RefreshSession, error)
	RevokeRefreshSession(ctx context.Context, sessionID string, revokedAt time.Time) error
	CreatePhoneOTP(ctx context.Context, otp *PhoneOTP) error
	ConsumePhoneOTP(ctx context.Context, phone string, role string, codeHash string, now time.Time) (*PhoneOTP, error)
	UpsertTaxProfile(ctx context.Context, profile *TaxProfile) error
	GetTaxProfile(ctx context.Context, driverID string) (*TaxProfile, error)
	IsDriverTaxVerified(ctx context.Context, driverID string) (bool, error)
	IsDriverDocumentsApproved(ctx context.Context, driverID string) (bool, error)
	IsDriverSubscriptionActive(ctx context.Context, driverID string, now time.Time) (bool, error)
}
