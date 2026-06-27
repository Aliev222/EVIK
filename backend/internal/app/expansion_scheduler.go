package app

import (
	"context"
	"fmt"
	"log"
	"time"

	locationdomain "evik/backend/internal/domain/location"
	orderdomain "evik/backend/internal/domain/order"
)

type expansionOrderRepo interface {
	ListSearchingForExpansion(ctx context.Context, olderThan time.Time, limit int) ([]*orderdomain.Order, error)
	MarkExpanded(ctx context.Context, orderID string, now time.Time) error
}

type expansionLocationStore interface {
	GetNearbyDrivers(ctx context.Context, pickup locationdomain.Location, radiusKM float64, limit int) ([]locationdomain.DriverLocation, error)
	GetDriverCity(ctx context.Context, driverID string) (string, error)
}

type expansionPushSender interface {
	SendToUser(ctx context.Context, userID, role, title, body string, data map[string]string) error
}

type expansionEventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

// SearchExpansionScheduler periodically promotes stale "searching" orders to
// the wider radius, pushing notifications to newly eligible drivers.
type SearchExpansionScheduler struct {
	orderRepo      expansionOrderRepo
	locationStore  expansionLocationStore
	pushSender     expansionPushSender
	eventPublisher expansionEventPublisher
	logger         *log.Logger
	checkInterval  time.Duration
	delay          time.Duration
	radiusKM       float64
}

func NewSearchExpansionScheduler(
	orderRepo expansionOrderRepo,
	locationStore expansionLocationStore,
	pushSender expansionPushSender,
	eventPublisher expansionEventPublisher,
	logger *log.Logger,
	checkInterval, delay time.Duration,
	radiusKM float64,
) *SearchExpansionScheduler {
	if checkInterval <= 0 {
		checkInterval = 10 * time.Second
	}
	if delay <= 0 {
		delay = 60 * time.Second
	}
	if radiusKM <= 0 {
		radiusKM = 30
	}
	return &SearchExpansionScheduler{
		orderRepo:      orderRepo,
		locationStore:  locationStore,
		pushSender:     pushSender,
		eventPublisher: eventPublisher,
		logger:         logger,
		checkInterval:  checkInterval,
		delay:          delay,
		radiusKM:       radiusKM,
	}
}

func (s *SearchExpansionScheduler) Run(ctx context.Context) {
	s.logger.Printf("search expansion scheduler started: check=%s delay=%s radius=%.0fkm",
		s.checkInterval, s.delay, s.radiusKM)
	ticker := time.NewTicker(s.checkInterval)
	defer ticker.Stop()

	s.expandStaleOrders(ctx)
	for {
		select {
		case <-ctx.Done():
			s.logger.Printf("search expansion scheduler stopped")
			return
		case <-ticker.C:
			s.expandStaleOrders(ctx)
		}
	}
}

func (s *SearchExpansionScheduler) expandStaleOrders(ctx context.Context) {
	olderThan := time.Now().UTC().Add(-s.delay)
	orders, err := s.orderRepo.ListSearchingForExpansion(ctx, olderThan, 100)
	if err != nil {
		s.logger.Printf("expansion: list stale orders: %v", err)
		return
	}
	for _, ord := range orders {
		s.expandOrder(ctx, ord)
	}
}

func (s *SearchExpansionScheduler) expandOrder(ctx context.Context, ord *orderdomain.Order) {
	now := time.Now().UTC()

	// Mark expanded first to prevent duplicate processing on the next tick.
	if err := s.orderRepo.MarkExpanded(ctx, ord.ID, now); err != nil {
		s.logger.Printf("expansion: mark order=%s: %v", ord.ID, err)
		return
	}

	pickup := locationdomain.Location{Lat: ord.Pickup.Lat, Lng: ord.Pickup.Lng, UpdatedAt: now}
	nearby, err := s.locationStore.GetNearbyDrivers(ctx, pickup, s.radiusKM, 500)
	if err != nil {
		s.logger.Printf("expansion: nearby drivers order=%s: %v", ord.ID, err)
		return
	}

	// Exclude drivers already in the order's city — they were notified at creation.
	cityID := ""
	if ord.CityID != nil {
		cityID = *ord.CityID
	}

	type driverDist struct {
		id   string
		dist float64
	}
	newDrivers := make([]driverDist, 0, len(nearby))
	for _, dl := range nearby {
		if cityID != "" {
			driverCity, _ := s.locationStore.GetDriverCity(ctx, dl.DriverID)
			if driverCity == cityID {
				continue
			}
		}
		newDrivers = append(newDrivers, driverDist{dl.DriverID, dl.DistanceKM})
	}

	s.logger.Printf("expansion: order=%s found=%d new drivers within %.0fkm",
		ord.ID, len(newDrivers), s.radiusKM)

	// Send personalised push per driver showing their actual distance.
	for _, dd := range newDrivers {
		pushCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		title := "Новый заказ"
		body := fmt.Sprintf("Новый заказ в %.0f км от вас", dd.dist)
		data := map[string]string{
			"type":       "order_expanded",
			"order_id":   ord.ID,
			"pickup_lat": fmt.Sprintf("%f", ord.Pickup.Lat),
			"pickup_lng": fmt.Sprintf("%f", ord.Pickup.Lng),
		}
		if err := s.pushSender.SendToUser(pushCtx, dd.id, "driver", title, body, data); err != nil {
			s.logger.Printf("expansion: push driver=%s order=%s: %v", dd.id, ord.ID, err)
		}
		cancel()
	}

	// Publish WS event so connected drivers receive the expanded order.
	if err := s.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventOrderExpanded,
		OrderID: ord.ID,
		Payload: map[string]any{
			"order":       ord,
			"is_expanded": true,
		},
	}); err != nil {
		s.logger.Printf("expansion: publish event order=%s: %v", ord.ID, err)
	}
}
