package driver

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"evik/backend/internal/domain/settings"
)

var (
	ErrDriverDocumentsNotApproved = errors.New("driver documents are not approved")
	ErrDriverTaxNotVerified       = errors.New("driver tax status is not verified")
	ErrDriverSubscriptionInactive = errors.New("driver subscription is inactive")
	// ErrOutstandingDebtBlocksWork is returned when a driver's accumulated cash
	// debt exceeds the configured maximum and the driver is not allowed to take
	// new orders until it is repaid. Subscribers (0% commission) never accrue
	// debt and are unaffected.
	ErrOutstandingDebtBlocksWork = errors.New("outstanding debt blocks work")
)

type GateRepository interface {
	IsDriverDocumentsApproved(ctx context.Context, driverID string) (bool, error)
	IsDriverTaxVerified(ctx context.Context, driverID string) (bool, error)
	IsDriverSubscriptionActive(ctx context.Context, driverID string, now time.Time) (bool, error)
	// DriverDebtBalance returns the driver's outstanding cash-commission debt
	// in kopecks (driver_wallets.debt_balance). Drivers without a wallet row
	// report 0.
	DriverDebtBalance(ctx context.Context, driverID string) (int64, error)
}

type GateService struct {
	repo                 GateRepository
	settingsRepo         settings.Repository
	clock                Clock
	subscriptionRequired bool
	bypass               bool
	debugMode            bool
}

func NewGateService(repo GateRepository, settingsRepo settings.Repository, clock Clock, subscriptionRequired bool, bypass bool, debugMode bool) *GateService {
	return &GateService{repo: repo, settingsRepo: settingsRepo, clock: clock, subscriptionRequired: subscriptionRequired, bypass: bypass, debugMode: debugMode}
}

func (s *GateService) EnsureCanWork(ctx context.Context, driverID string) error {
	if s.bypass || s.debugMode {
		return nil
	}
	docsApproved, err := s.repo.IsDriverDocumentsApproved(ctx, driverID)
	if err != nil {
		return err
	}
	if !docsApproved {
		return ErrDriverDocumentsNotApproved
	}
	taxVerified, err := s.repo.IsDriverTaxVerified(ctx, driverID)
	if err != nil {
		return err
	}
	if !taxVerified {
		return ErrDriverTaxNotVerified
	}
	if s.subscriptionRequired {
		active, err := s.repo.IsDriverSubscriptionActive(ctx, driverID, s.clock.Now())
		if err != nil {
			return err
		}
		if !active {
			return ErrDriverSubscriptionInactive
		}
	}
	maxDebt := s.maxCashDebtKopecks(ctx)
	if maxDebt > 0 {
		debt, err := s.repo.DriverDebtBalance(ctx, driverID)
		if err != nil {
			return err
		}
		if debt > int64(maxDebt) {
			return fmt.Errorf("%w: outstanding cash debt %d kopecks exceeds the max of %d", ErrOutstandingDebtBlocksWork, debt, maxDebt)
		}
	}
	return nil
}

// maxCashDebtKopecks reads the configured debt threshold from platform
// settings. 0 disables the gate. Falls back to the default threshold when the
// setting is missing or the settings store is unavailable (fail-closed).
func (s *GateService) maxCashDebtKopecks(ctx context.Context) int {
	if s.settingsRepo == nil {
		return settings.DefaultMaxCashDebtKopecks
	}
	list, err := s.settingsRepo.List(ctx)
	if err != nil {
		log.Printf("WARN: settings unavailable for debt threshold, fallback %d: %v", settings.DefaultMaxCashDebtKopecks, err)
		return settings.DefaultMaxCashDebtKopecks
	}
	v := settings.GetInt(list, settings.MaxCashDebtKopecksKey, settings.DefaultMaxCashDebtKopecks)
	if v < 0 {
		return settings.DefaultMaxCashDebtKopecks
	}
	return v
}

// EnsureCanRequestPayout checks the money-specific prerequisites for a driver
// payout request. It intentionally does NOT require an approved driver
// verification: once money is earned, losing the right to take new orders
// (e.g. verification status 'blocked') must not revoke access to withdrawing
// that money. Tax verification remains the only gate — it is a regulatory
// (self-employed / НПД) requirement that is independent of moderation status.
func (s *GateService) EnsureCanRequestPayout(ctx context.Context, driverID string) error {
	if s.bypass || s.debugMode {
		return nil
	}
	taxVerified, err := s.repo.IsDriverTaxVerified(ctx, driverID)
	if err != nil {
		return err
	}
	if !taxVerified {
		return ErrDriverTaxNotVerified
	}
	return nil
}
