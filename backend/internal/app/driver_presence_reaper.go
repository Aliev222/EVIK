package app

import (
	"context"
	"log"
	"time"

	driverdomain "evik/backend/internal/domain/driver"
	locationdomain "evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
)

type presenceDriverRepo interface {
	ListOnlineStale(ctx context.Context, olderThan time.Time, limit int) ([]*driverdomain.Driver, error)
	Upsert(ctx context.Context, driver *driverdomain.Driver) error
	GetByID(ctx context.Context, id string) (*driverdomain.Driver, error)
}

type presenceLocationStore interface {
	GetLastLocation(ctx context.Context, driverID string) (*locationdomain.Location, error)
	RemoveDriver(ctx context.Context, driverID string) error
}

type presenceHub interface {
	HasDriver(driverID string) bool
}

type presenceEventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type DriverPresenceReaper struct {
	driverRepo       presenceDriverRepo
	locationStore    presenceLocationStore
	hub              presenceHub
	eventPublisher   presenceEventPublisher
	logger           *log.Logger
	checkInterval    time.Duration
	gracePeriod      time.Duration
}

func NewDriverPresenceReaper(
	driverRepo presenceDriverRepo,
	locationStore presenceLocationStore,
	hub presenceHub,
	eventPublisher presenceEventPublisher,
	logger *log.Logger,
	checkInterval time.Duration,
	gracePeriod time.Duration,
) *DriverPresenceReaper {
	if checkInterval <= 0 {
		checkInterval = 30 * time.Second
	}
	if gracePeriod <= 0 {
		gracePeriod = 90 * time.Second
	}
	return &DriverPresenceReaper{
		driverRepo:     driverRepo,
		locationStore:  locationStore,
		hub:            hub,
		eventPublisher: eventPublisher,
		logger:         logger,
		checkInterval:  checkInterval,
		gracePeriod:    gracePeriod,
	}
}

func (r *DriverPresenceReaper) Run(ctx context.Context) {
	r.logger.Printf("driver presence reaper started: check=%s grace=%s", r.checkInterval, r.gracePeriod)
	ticker := time.NewTicker(r.checkInterval)
	defer ticker.Stop()

	r.reapStaleDrivers(ctx)
	for {
		select {
		case <-ctx.Done():
			r.logger.Printf("driver presence reaper stopped")
			return
		case <-ticker.C:
			r.reapStaleDrivers(ctx)
		}
	}
}

func (r *DriverPresenceReaper) reapStaleDrivers(ctx context.Context) {
	defer func() {
		if rec := recover(); rec != nil {
			r.logger.Printf("presence reaper: panic recovered: %v", rec)
		}
	}()

	olderThan := time.Now().UTC().Add(-r.gracePeriod)
	candidates, err := r.driverRepo.ListOnlineStale(ctx, olderThan, 100)
	if err != nil {
		r.logger.Printf("presence reaper: list stale drivers: %v", err)
		return
	}

	for _, drv := range candidates {
		if drv.CurrentOrderID != nil {
			r.logger.Printf("presence reaper: skip driver=%s (has active order %s)", drv.ID, *drv.CurrentOrderID)
			continue
		}
		if r.hub.HasDriver(drv.ID) {
			continue
		}
		loc, locErr := r.locationStore.GetLastLocation(ctx, drv.ID)
		if locErr == nil && loc != nil && time.Since(loc.UpdatedAt) < r.gracePeriod {
			r.logger.Printf("presence reaper: skip driver=%s (location fresh, age=%s)", drv.ID, time.Since(loc.UpdatedAt).Round(time.Second))
			continue
		}
		r.reapDriver(ctx, drv)
	}
}

func (r *DriverPresenceReaper) reapDriver(ctx context.Context, drv *driverdomain.Driver) {
	now := time.Now().UTC()
	updated := &driverdomain.Driver{
		ID:         drv.ID,
		UserID:     drv.UserID,
		Status:     driverdomain.StatusOffline,
		LastSeenAt: now,
		UpdatedAt:  now,
	}
	if err := r.driverRepo.Upsert(ctx, updated); err != nil {
		r.logger.Printf("presence reaper: upsert offline driver=%s: %v", drv.ID, err)
		return
	}
	if err := r.locationStore.RemoveDriver(ctx, drv.ID); err != nil {
		r.logger.Printf("presence reaper: remove geo driver=%s: %v", drv.ID, err)
	}
	_ = r.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventAdminDriverLocation,
		OrderID: "",
		Payload: map[string]any{
			"driver_id":  drv.ID,
			"status":     "offline",
			"reason":     "presence_reaper_stale",
			"updated_at": now.Format(time.RFC3339),
		},
	})
	r.logger.Printf("presence reaper: driver=%s set offline (stale, no WS, no active order)", drv.ID)
}
