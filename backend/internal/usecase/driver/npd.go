package driver

import (
	"context"
	"errors"
	"strings"
	"time"

	userdomain "evik/backend/internal/domain/user"
)

// NPDProvider abstracts the Moy Nalog (FNS) partner integration. The real
// implementation will use lknpd.nalog.ru OAuth2 endpoints and require a
// signed partner agreement with FNS. Until that contract is in place, a
// stub provider is wired in so the whole flow can be exercised end-to-end
// and the UI shows a "Coming soon" state instead of hard-failing.
type NPDProvider interface {
	// Connect exchanges a one-time grant produced by the driver in the
	// Moy Nalog app for a long-lived OAuth2 token bound to their INN.
	// inn is the 10 or 12 digit taxpayer number entered by the driver
	// before opening Moy Nalog. The real provider verifies that the
	// driver actually granted our partner access; the stub provider
	// returns ErrNPDProviderNotConfigured so the caller can render a
	// "Скоро" banner in the UI.
	Connect(ctx context.Context, inn string) (userdomain.NPDConnectionResult, error)
	// RegisterIncome registers an income receipt for the given driver
	// after their share of an order has been paid out. Returns the
	// receipt URL produced by FNS. Stub provider returns an error.
	RegisterIncome(ctx context.Context, accessToken string, req RegisterIncomeRequest) (RegisterIncomeResult, error)
}

type RegisterIncomeRequest struct {
	DriverINN string
	Amount    int64 // kopecks
	OrderID   string
	Now       time.Time
}

type RegisterIncomeResult struct {
	ReceiptID  string
	ReceiptURL string
}

// StubNPDProvider is the development / pre-partnership provider. Every
// method returns ErrNPDProviderNotConfigured so HTTP handlers can answer
// the driver app with "503 npd integration is not configured yet" and
// show the "Скоро" banner in driver UI.
type StubNPDProvider struct{}

func (StubNPDProvider) Connect(_ context.Context, _ string) (userdomain.NPDConnectionResult, error) {
	return userdomain.NPDConnectionResult{}, userdomain.ErrNPDProviderNotConfigured
}

func (StubNPDProvider) RegisterIncome(_ context.Context, _ string, _ RegisterIncomeRequest) (RegisterIncomeResult, error) {
	return RegisterIncomeResult{}, userdomain.ErrNPDProviderNotConfigured
}

// NPDRepository is the slice of UserRepository this usecase needs. Kept
// narrow so tests can fake it without implementing all of user.Repository.
type NPDRepository interface {
	GetTaxProfile(ctx context.Context, driverID string) (*userdomain.TaxProfile, error)
	UpdateNPDConnection(ctx context.Context, driverID string, result userdomain.NPDConnectionResult, now time.Time) error
	MarkNPDRevoked(ctx context.Context, driverID string, now time.Time) error
}

type NPDService struct {
	repo     NPDRepository
	provider NPDProvider
	clock    Clock
}

func NewNPDService(repo NPDRepository, provider NPDProvider, clock Clock) *NPDService {
	if clock == nil {
		clock = systemClock{}
	}
	if provider == nil {
		provider = StubNPDProvider{}
	}
	return &NPDService{repo: repo, provider: provider, clock: clock}
}

var ErrINNRequired = errors.New("inn is required and must be 10 or 12 digits")

// Status returns the driver's current connection state. The tokens are
// stripped — handlers must never echo OAuth2 secrets back to clients.
func (s *NPDService) Status(ctx context.Context, driverID string) (*userdomain.TaxProfile, error) {
	profile, err := s.repo.GetTaxProfile(ctx, driverID)
	if err != nil {
		return nil, err
	}
	profile.NPDAccessToken = ""
	profile.NPDRefreshToken = ""
	return profile, nil
}

// Connect drives the driver-initiated connection to Moy Nalog. The flow:
//  1. driver opens Moy Nalog and grants our partner integration access
//  2. driver enters their INN in our app and calls this endpoint
//  3. provider exchanges the grant for tokens, returns INN + full name
//  4. repo persists tokens, mirrors full name into users.fns_full_name
//
// While we don't have the partnership signed, provider.Connect returns
// ErrNPDProviderNotConfigured and the API responds 503 — driver UI
// shows the "Скоро" banner.
func (s *NPDService) Connect(ctx context.Context, driverID, inn string) (*userdomain.TaxProfile, error) {
	normalizedINN := strings.TrimSpace(inn)
	if !isValidINN(normalizedINN) {
		return nil, ErrINNRequired
	}

	result, err := s.provider.Connect(ctx, normalizedINN)
	if err != nil {
		return nil, err
	}

	now := s.clock.Now()
	if err := s.repo.UpdateNPDConnection(ctx, driverID, result, now); err != nil {
		return nil, err
	}
	return s.Status(ctx, driverID)
}

// Disconnect marks the profile as revoked. Tokens are wiped so a future
// reconnect can re-issue cleanly. We don't call FNS — it's the driver's
// decision to leave, and FNS keeps a 1:1 mapping anyway.
func (s *NPDService) Disconnect(ctx context.Context, driverID string) error {
	return s.repo.MarkNPDRevoked(ctx, driverID, s.clock.Now())
}

func isValidINN(value string) bool {
	if len(value) != 10 && len(value) != 12 {
		return false
	}
	for _, r := range value {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

type systemClock struct{}

func (systemClock) Now() time.Time { return time.Now().UTC() }
