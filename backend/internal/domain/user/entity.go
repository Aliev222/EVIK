package user

import (
	"time"

	"evik/backend/internal/auth"
)

type Status string

const (
	StatusActive  Status = "active"
	StatusBlocked Status = "blocked"
	// StatusDeleted marks an account that the owner deleted. Its PII has been
	// anonymized and login is rejected, but financial/order records that
	// reference the row are retained for tax/legal compliance.
	StatusDeleted Status = "deleted"
)

type User struct {
	ID           string
	Phone        string
	Name         string
	Role         auth.Role
	PasswordHash *string
	Status       Status
	DeletedAt    *time.Time
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

type DeviceToken struct {
	UserID     string
	Role       auth.Role
	FCMToken   string
	Platform   string
	AppVersion string
	CreatedAt  time.Time
	UpdatedAt  time.Time
	RevokedAt  *time.Time
}

type TaxProfile struct {
	DriverID           string
	INN                string
	TaxpayerType       string
	VerificationStatus string
	CreatedAt          time.Time
	UpdatedAt          time.Time

	// NPD partner connection (Moy Nalog / lknpd.nalog.ru). All fields are
	// populated only after the driver grants permission to our partner
	// integration through the Moy Nalog app. Until the partner contract
	// with FNS is signed, ConnectionStatus stays "not_connected".
	NPDAccessToken      string
	NPDRefreshToken     string
	NPDTokenExpiresAt   *time.Time
	NPDConnectedAt      *time.Time
	NPDRevokedAt        *time.Time
	NPDConnectionStatus string
}

const (
	NPDStatusNotConnected = "not_connected"
	NPDStatusConnected    = "connected"
	NPDStatusRevoked      = "revoked"
	NPDStatusError        = "error"
)

// NPDConnectionResult is what the Moy Nalog partner API returns after the
// driver successfully connects our integration. Real provider produces all
// fields; the stub provider used until partnership is signed produces only
// the INN passed in plus a placeholder access token.
type NPDConnectionResult struct {
	INN          string
	FullName     string
	AccessToken  string
	RefreshToken string
	ExpiresAt    time.Time
}
