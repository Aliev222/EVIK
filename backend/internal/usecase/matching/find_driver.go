package matching

import (
	"context"
	"errors"
	"time"

	domainmatching "evik/backend/internal/domain/matching"
	orderdomain "evik/backend/internal/domain/order"
)

type Clock interface {
	Now() time.Time
}

type EventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type FindDriverUseCase struct {
	orderRepo      orderdomain.Repository
	matchingSvc    domainmatching.MatchingService
	eventPublisher EventPublisher
	clock          Clock
}

type radiusExpander interface {
	ExpandSearchRadius()
}

func NewFinder(
	orderRepo orderdomain.Repository,
	matchingSvc domainmatching.MatchingService,
	eventPublisher EventPublisher,
	clock Clock,
) *FindDriverUseCase {
	return &FindDriverUseCase{
		orderRepo:      orderRepo,
		matchingSvc:    matchingSvc,
		eventPublisher: eventPublisher,
		clock:          clock,
	}
}

func (uc *FindDriverUseCase) Execute(ctx context.Context, orderID string) (*orderdomain.Order, error) {
	ord, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}

	matchCtx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()

	const retries = 3
	const retryDelay = 2 * time.Second

	matchingDone := false
	for attempt := 0; attempt < retries; attempt++ {
		drv, err := uc.matchingSvc.FindNearestDriver(matchCtx, ord)
		if err == nil {
			now := uc.clock.Now()
			if err := ord.AssignDriver(drv.ID, now); err != nil {
				return nil, err
			}
			if err := ord.TransitionTo(orderdomain.StatusAccepted, now); err != nil {
				return nil, err
			}
			if err := uc.orderRepo.Update(ctx, ord); err != nil {
				return nil, err
			}
			if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
				Type:    orderdomain.EventAccepted,
				OrderID: ord.ID,
				Payload: map[string]any{"driver_id": drv.ID},
			}); err != nil {
				return nil, err
			}
			return ord, nil
		}

		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
			break
		}

		if expander, ok := uc.matchingSvc.(radiusExpander); ok {
			expander.ExpandSearchRadius()
		}

		if attempt < retries-1 {
			select {
			case <-matchCtx.Done():
				matchingDone = true
			case <-time.After(retryDelay):
			}
			if matchingDone {
				break
			}
		}
	}

	now := uc.clock.Now()
	if err := ord.TransitionTo(orderdomain.StatusNoDriverFound, now); err != nil {
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, ord); err != nil {
		return nil, err
	}
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventNoDriverFound,
		OrderID: ord.ID,
		Payload: map[string]any{
			"status": ord.Status,
			"reason": "no_driver_found_after_retries",
		},
	}); err != nil {
		return nil, err
	}
	return ord, nil
}
