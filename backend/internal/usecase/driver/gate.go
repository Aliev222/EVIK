package driver

import (
	"context"
	"errors"
	"time"
)

var (
	ErrDriverDocumentsNotApproved = errors.New("driver documents are not approved")
	ErrDriverTaxNotVerified       = errors.New("driver tax status is not verified")
	ErrDriverSubscriptionInactive = errors.New("driver subscription is inactive")
)

type GateRepository interface {
	IsDriverDocumentsApproved(ctx context.Context, driverID string) (bool, error)
	IsDriverTaxVerified(ctx context.Context, driverID string) (bool, error)
	IsDriverSubscriptionActive(ctx context.Context, driverID string, now time.Time) (bool, error)
}

type GateService struct {
	repo                 GateRepository
	clock                Clock
	subscriptionRequired bool
	bypass               bool
	debugMode            bool
}

func NewGateService(repo GateRepository, clock Clock, subscriptionRequired bool, bypass bool, debugMode bool) *GateService {
	return &GateService{repo: repo, clock: clock, subscriptionRequired: subscriptionRequired, bypass: bypass, debugMode: debugMode}
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
	return nil
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
