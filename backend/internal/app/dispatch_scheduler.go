package app

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"strconv"
	"time"

	matchingdomain "evik/backend/internal/domain/matching"
	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/domain/settings"
	wsinfra "evik/backend/internal/infrastructure/websocket"
)

type dispatchOfferRepo interface {
	Create(ctx context.Context, offer *orderdomain.Offer) (bool, error)
	ExpirePending(ctx context.Context) ([]string, error)
	GetCurrentRound(ctx context.Context, orderID string) (int, error)
	ListOrderOfferedDriverIDs(ctx context.Context, orderID string, round int) ([]string, error)
	ListSearchingWithoutOffer(ctx context.Context, limit int) ([]*orderdomain.Order, error)
}

type dispatchOrderRepo interface {
	GetByID(ctx context.Context, id string) (*orderdomain.Order, error)
	Update(ctx context.Context, ord *orderdomain.Order) error
}

type dispatchMatchingService interface {
	FindCandidates(ctx context.Context, ord *orderdomain.Order, radiusKM float64, exclude []string, liveChecker matchingdomain.LiveDriverChecker, geoFreshness time.Duration) ([]matchingdomain.Candidate, error)
}

type dispatchSettingsRepo interface {
	List(ctx context.Context) ([]settings.Setting, error)
}

type dispatchEventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type dispatchPushSender interface {
	SendToUser(ctx context.Context, userID, role, title, body string, data map[string]string) error
}

type DispatchScheduler struct {
	offerRepo      dispatchOfferRepo
	orderRepo      dispatchOrderRepo
	matchingSvc    dispatchMatchingService
	settingsRepo   dispatchSettingsRepo
	hub            *wsinfra.Hub
	eventPublisher dispatchEventPublisher
	pushSender     dispatchPushSender
	idGen          idGenerator
	clock          clock
	logger         *log.Logger
	checkInterval  time.Duration
	offerTimeout   time.Duration
	maxRadiusKM    float64
	stepRadiusKM   float64
	geoFreshness   time.Duration
	maxRounds      int
}

func NewDispatchScheduler(
	offerRepo dispatchOfferRepo,
	orderRepo dispatchOrderRepo,
	matchingSvc dispatchMatchingService,
	settingsRepo dispatchSettingsRepo,
	hub *wsinfra.Hub,
	eventPublisher dispatchEventPublisher,
	pushSender dispatchPushSender,
	idGen idGenerator,
	clock clock,
	logger *log.Logger,
	checkInterval time.Duration,
	offerTimeout time.Duration,
	geoFreshness time.Duration,
) *DispatchScheduler {
	if checkInterval <= 0 {
		checkInterval = 2 * time.Second
	}
	if offerTimeout <= 0 {
		offerTimeout = 15 * time.Second
	}
	if geoFreshness <= 0 {
		geoFreshness = 60 * time.Second
	}
	return &DispatchScheduler{
		offerRepo:     offerRepo,
		orderRepo:     orderRepo,
		matchingSvc:   matchingSvc,
		settingsRepo:  settingsRepo,
		hub:           hub,
		eventPublisher: eventPublisher,
		pushSender:    pushSender,
		idGen:         idGen,
		clock:         clock,
		logger:        logger,
		checkInterval: checkInterval,
		offerTimeout:  offerTimeout,
		maxRadiusKM:   15,
		stepRadiusKM:  2,
		geoFreshness:  geoFreshness,
		maxRounds:     3,
	}
}

func (s *DispatchScheduler) Run(ctx context.Context) {
	s.logger.Printf("dispatch scheduler started: check=%s offer_timeout=%s", s.checkInterval, s.offerTimeout)
	ticker := time.NewTicker(s.checkInterval)
	defer ticker.Stop()

	s.safeTick(ctx)
	for {
		select {
		case <-ctx.Done():
			s.logger.Printf("dispatch scheduler stopped")
			return
		case <-ticker.C:
			s.safeTick(ctx)
		}
	}
}

func (s *DispatchScheduler) safeTick(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			s.logger.Printf("dispatch: panic recovered in tick: %v", r)
		}
	}()
	s.tick(ctx)
}

func (s *DispatchScheduler) tick(ctx context.Context) {
	expiredOrderIDs, err := s.offerRepo.ExpirePending(ctx)
	if err != nil {
		s.logger.Printf("dispatch: expire pending: %v", err)
	} else {
		for _, orderID := range expiredOrderIDs {
			s.logger.Printf("dispatch: offer expired for order=%s", orderID)
			s.tryOfferNext(ctx, orderID)
		}
	}

	searchingOrders, err := s.offerRepo.ListSearchingWithoutOffer(ctx, 50)
	if err != nil {
		s.logger.Printf("dispatch: list searching without offer: %v", err)
		return
	}
	for _, ord := range searchingOrders {
		s.logger.Printf("dispatch: new order searching without offer order=%s", ord.ID)
		s.tryOfferNext(ctx, ord.ID)
	}
}

func (s *DispatchScheduler) tryOfferNext(ctx context.Context, orderID string) {
	ord, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		s.logger.Printf("dispatch: get order %s: %v", orderID, err)
		return
	}
	if ord.Status != orderdomain.StatusSearching {
		return
	}

	currentRound, err := s.offerRepo.GetCurrentRound(ctx, orderID)
	if err != nil {
		s.logger.Printf("dispatch: get round for %s: %v", orderID, err)
		return
	}
	if currentRound == 0 {
		currentRound = 1
	}

	exclude, err := s.offerRepo.ListOrderOfferedDriverIDs(ctx, orderID, currentRound)
	if err != nil {
		s.logger.Printf("dispatch: list offered for %s: %v", orderID, err)
		return
	}

	offerTimeout := s.loadOfferTimeout(ctx)

	radius := s.stepRadiusKM
	roundLimit := s.loadRoundLimit(ctx)

	var lastErr error
	for attempt := 0; attempt < roundLimit; attempt++ {
		if radius > s.maxRadiusKM {
			s.logger.Printf("dispatch: radius %g exceeds max %g for order=%s", radius, s.maxRadiusKM, orderID)
			break
		}
		candidates, err := s.matchingSvc.FindCandidates(ctx, ord, radius, exclude, s.hub, s.geoFreshness)
		if err == matchingdomain.ErrNoCandidateDrivers {
			radius += s.stepRadiusKM
			continue
		}
		if err != nil {
			lastErr = err
			radius += s.stepRadiusKM
			continue
		}
		if len(candidates) == 0 {
			radius += s.stepRadiusKM
			continue
		}

		candidate := candidates[0]
		s.createOffer(ctx, ord, candidate, currentRound, candidate.DistanceKM, offerTimeout)
		return
	}

	s.logger.Printf("dispatch: no candidates for order=%s after %d attempts (last_err=%v)", orderID, roundLimit, lastErr)
	s.markNoDriverFound(ctx, ord)
}

func (s *DispatchScheduler) createOffer(ctx context.Context, ord *orderdomain.Order, candidate matchingdomain.Candidate, round int, distanceKM float64, offerTimeout time.Duration) {
	now := s.clock.Now()
	offer := &orderdomain.Offer{
		ID:         s.idGen.NewID(),
		OrderID:    ord.ID,
		DriverID:   candidate.DriverID,
		Round:      round,
		DistanceKM: &distanceKM,
		OfferedAt:  now,
		ExpiresAt:  now.Add(offerTimeout),
	}

	created, err := s.offerRepo.Create(ctx, offer)
	if err != nil {
		s.logger.Printf("dispatch: create offer for order=%s driver=%s: %v", ord.ID, candidate.DriverID, err)
		return
	}
	if !created {
		s.logger.Printf("dispatch: offer not created (conflict) for order=%s driver=%s", ord.ID, candidate.DriverID)
		return
	}

	s.logger.Printf("dispatch: offer %s created for order=%s driver=%s round=%d expires=%s",
		offer.ID, ord.ID, candidate.DriverID, round, offer.ExpiresAt.Format(time.RFC3339))

	s.sendOfferPush(ctx, offer, ord, distanceKM)
}

func (s *DispatchScheduler) sendOfferPush(ctx context.Context, offer *orderdomain.Offer, ord *orderdomain.Order, distanceKM float64) {
	payload, _ := json.Marshal(map[string]any{
		"type":            "offer",
		"offer_id":        offer.ID,
		"order_id":        ord.ID,
		"expires_at":      offer.ExpiresAt.UTC().Format(time.RFC3339),
		"pickup_lat":      ord.Pickup.Lat,
		"pickup_lng":      ord.Pickup.Lng,
		"dropoff_lat":     ord.Dropoff.Lat,
		"dropoff_lng":     ord.Dropoff.Lng,
		"pickup_address":  ord.PickupAddress,
		"dropoff_address": ord.DropoffAddress,
		"distance_km":     math.Round(distanceKM*10) / 10,
		"price_total":     ord.PriceTotal,
		"tow_truck_type":  string(ord.TowTruckType),
	})

	s.hub.SendToDriver(offer.DriverID, payload)
	s.logger.Printf("dispatch: offer WS sent to driver=%s for order=%s", offer.DriverID, ord.ID)

	if s.pushSender != nil {
		title := "Новый заказ"
		body := fmt.Sprintf("Эвакуатор %s — %.0f ₽, %.0f км", ord.TowTruckType, float64(ord.PriceTotal)/100, distanceKM)
		data := map[string]string{
			"type":      "offer",
			"offer_id":  offer.ID,
			"order_id":  ord.ID,
			"expires":   offer.ExpiresAt.Format(time.RFC3339),
		}
		pushCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
		defer cancel()
		if err := s.pushSender.SendToUser(pushCtx, offer.DriverID, "driver", title, body, data); err != nil {
			s.logger.Printf("dispatch: FCM push to driver=%s order=%s: %v", offer.DriverID, ord.ID, err)
		}
	}
}

func (s *DispatchScheduler) markNoDriverFound(ctx context.Context, ord *orderdomain.Order) {
	now := s.clock.Now()
	// TODO(Phase 3): предложить клиенту поднять цену вместо no_driver_found
	if err := ord.TransitionTo(orderdomain.StatusNoDriverFound, now); err != nil {
		s.logger.Printf("dispatch: transition no_driver_found order=%s: %v", ord.ID, err)
		return
	}
	if err := s.orderRepo.Update(ctx, ord); err != nil {
		s.logger.Printf("dispatch: update no_driver_found order=%s: %v", ord.ID, err)
		return
	}
	if err := s.eventPublisher.Publish(ctx, orderdomain.Event{
		Type:    orderdomain.EventNoDriverFound,
		OrderID: ord.ID,
		Payload: map[string]any{
			"status": ord.Status,
			"reason": "no_driver_after_dispatch",
		},
	}); err != nil {
		s.logger.Printf("dispatch: publish no_driver_found event order=%s: %v", ord.ID, err)
	}
	s.logger.Printf("dispatch: order=%s marked no_driver_found", ord.ID)
}

func (s *DispatchScheduler) loadOfferTimeout(ctx context.Context) time.Duration {
	val := s.loadSettingInt(ctx, "offer_timeout_seconds", int(s.offerTimeout.Seconds()))
	if val < 5 {
		val = 5
	}
	if val > 60 {
		val = 60
	}
	return time.Duration(val) * time.Second
}

func (s *DispatchScheduler) loadRoundLimit(ctx context.Context) int {
	val := s.loadSettingInt(ctx, "dispatch_round_limit", s.maxRounds)
	if val < 1 {
		val = 1
	}
	if val > 10 {
		val = 10
	}
	return val
}

type idGenerator interface {
	NewID() string
}

type clock interface {
	Now() time.Time
}

func (s *DispatchScheduler) loadSettingInt(ctx context.Context, key string, fallback int) int {
	list, err := s.settingsRepo.List(ctx)
	if err != nil {
		s.logger.Printf("WARN: %s not found in settings, using default %d", key, fallback)
		return fallback
	}
	for _, setting := range list {
		if setting.Key != key {
			continue
		}
		switch v := setting.Value.(type) {
		case float64:
			if v <= 0 {
				s.logger.Printf("WARN: invalid %s %v (negative), using default %d", key, v, fallback)
				return fallback
			}
			return int(v)
		case string:
			f, err := strconv.ParseFloat(v, 64)
			if err != nil || f <= 0 {
				s.logger.Printf("WARN: invalid %s %q, using default %d", key, v, fallback)
				return fallback
			}
			return int(f)
		default:
			s.logger.Printf("WARN: %s not a string or float (%T), using default %d", key, v, fallback)
			return fallback
		}
	}
	s.logger.Printf("WARN: %s not found in settings, using default %d", key, fallback)
	return fallback
}
