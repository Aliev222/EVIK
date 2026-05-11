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
}

func NewGateService(repo GateRepository, clock Clock, subscriptionRequired bool) *GateService {
	return &GateService{repo: repo, clock: clock, subscriptionRequired: subscriptionRequired}
}

func (s *GateService) EnsureCanWork(ctx context.Context, driverID string) error {
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

func (s *GateService) EnsureCanRequestPayout(ctx context.Context, driverID string) error {
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
	return nil
}
