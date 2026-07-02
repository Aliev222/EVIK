package matching

import (
	"context"
	"errors"
	"log"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	domainmatching "evik/backend/internal/domain/matching"
	orderdomain "evik/backend/internal/domain/order"
)

type Clock interface {
	Now() time.Time
}

type EventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type DriverOrderRepository interface {
	AssignOrder(ctx context.Context, driverID string, orderID string, now time.Time) (*driverdomain.Driver, error)
	ReleaseOrder(ctx context.Context, driverID string, orderID string, now time.Time) error
}

type FindDriverUseCase struct {
	orderRepo      orderdomain.Repository
	driverRepo     DriverOrderRepository
	matchingSvc    domainmatching.MatchingService
	eventPublisher EventPublisher
	clock          Clock
}

type radiusExpander interface {
	ExpandSearchRadius()
}

func NewFinder(
	orderRepo orderdomain.Repository,
	driverRepo DriverOrderRepository,
	matchingSvc domainmatching.MatchingService,
	eventPublisher EventPublisher,
	clock Clock,
) *FindDriverUseCase {
	return &FindDriverUseCase{
		orderRepo:      orderRepo,
		driverRepo:     driverRepo,
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
			if _, err := uc.driverRepo.AssignOrder(ctx, drv.ID, ord.ID, now); err != nil {
				if errors.Is(err, driverdomain.ErrDriverUnavailable) {
					if attempt < retries-1 {
						continue
					}
					break
				}
				return nil, err
			}
			if err := ord.AssignDriver(drv.ID, now); err != nil {
				return nil, err
			}
			if err := ord.TransitionTo(orderdomain.StatusAccepted, now); err != nil {
				releaseOrderWithRetry(ctx, uc.driverRepo, drv.ID, ord.ID, now)
				return nil, err
			}
			if err := uc.orderRepo.Update(ctx, ord); err != nil {
				releaseOrderWithRetry(ctx, uc.driverRepo, drv.ID, ord.ID, now)
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
	latest, err := uc.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if latest.Status != orderdomain.StatusSearching {
		return latest, nil
	}
	if err := latest.TransitionTo(orderdomain.StatusNoDriverFound, now); err != nil {
		return nil, err
	}
	if err := uc.orderRepo.Update(ctx, latest); err != nil {
		return nil, err
	}
	if err := uc.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventNoDriverFound,
		OrderID: latest.ID,
		Payload: map[string]any{
			"status": latest.Status,
			"reason": "no_driver_found_after_retries",
		},
	}); err != nil {
		return nil, err
	}
	return latest, nil
}

// releaseOrderWithRetry attempts to release a driver from an order up to 3 times with
// 100ms delays. If all attempts fail, a CRITICAL message is logged so an admin can
// intervene — the driver would otherwise be stuck in busy status permanently.
func releaseOrderWithRetry(ctx context.Context, repo DriverOrderRepository, driverID, orderID string, now time.Time) {
	var err error
	for i := range 3 {
		if i > 0 {
			time.Sleep(100 * time.Millisecond)
		}
		err = repo.ReleaseOrder(ctx, driverID, orderID, now)
		if err == nil {
			return
		}
	}
	log.Printf("CRITICAL: failed to release driver %s from order %s after 3 attempts: %v — manual admin intervention required", driverID, orderID, err)
}
