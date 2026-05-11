package user

import (
	"time"

	"evik/backend/internal/auth"
)

type Status string

const (
	StatusActive  Status = "active"
	StatusBlocked Status = "blocked"
)

type User struct {
	ID           string
	Phone        string
	Name         string
	Role         auth.Role
	PasswordHash *string
	Status       Status
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

type RefreshSession struct {
	ID        string
	UserID    string
	Role      auth.Role
	TokenHash string
	ExpiresAt time.Time
	RevokedAt *time.Time
	CreatedAt time.Time
}

type PhoneOTP struct {
	ID         string
	Phone      string
	Role       auth.Role
	CodeHash   string
	ExpiresAt  time.Time
	ConsumedAt *time.Time
	CreatedAt  time.Time
}

type TaxProfile struct {
	DriverID           string
	INN                string
	TaxpayerType       string
	VerificationStatus string
	CreatedAt          time.Time
	UpdatedAt          time.Time
}
