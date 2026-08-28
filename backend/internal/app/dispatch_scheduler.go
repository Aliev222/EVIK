package app

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"strconv"
	"sync"
	"time"

	"golang.org/x/sync/errgroup"

	matchingdomain "evik/backend/internal/domain/matching"
	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/domain/settings"
	wsinfra "evik/backend/internal/infrastructure/websocket"
)

type dispatchOfferRepo interface {
	Create(ctx context.Context, offer *orderdomain.Offer) (bool, error)
	CreateTx(ctx context.Context, tx *sql.Tx, offer *orderdomain.Offer) (bool, error)
	ExpirePending(ctx context.Context) ([]string, error)
	GetCurrentRound(ctx context.Context, orderID string) (int, error)
	ListOrderOfferedDriverIDs(ctx context.Context, orderID string, round int) ([]string, error)
	ListSearchingWithoutOffer(ctx context.Context, limit int) ([]*orderdomain.Order, error)
}

// dispatchDriverRepo is used to atomically reserve a driver row (FOR UPDATE
// NOWAIT) so concurrent dispatch goroutines cannot offer the same driver to
// two different orders.
type dispatchDriverRepo interface {
	ReserveForOfferTx(ctx context.Context, tx *sql.Tx, driverID string) (bool, error)
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
	driverRepo     dispatchDriverRepo
	orderRepo      dispatchOrderRepo
	db             *sql.DB
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
	stepRadiusKM    float64
	geoFreshness   time.Duration
	maxRounds      int

	// wakeGrace is how long the dispatcher waits for an offline-online driver
	// (no live WS) to reconnect after a wake-up push before giving up on them
	// for this offer round.
	wakeGrace time.Duration
	// waking holds drivers who were offered an order via push but have not yet
	// reconnected their WebSocket. Keyed by orderID+driverID. Guarded by mu.
	mu      sync.Mutex
	waking  map[string]wakeEntry
}

// wakeEntry tracks a driver we sent a wake-up push to, awaiting WS reconnect.
type wakeEntry struct {
	orderID   string
	driverID  string
	round     int
	expiresAt time.Time
}

func NewDispatchScheduler(
	offerRepo dispatchOfferRepo,
	driverRepo dispatchDriverRepo,
	orderRepo dispatchOrderRepo,
	db *sql.DB,
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
		driverRepo:    driverRepo,
		orderRepo:     orderRepo,
		db:            db,
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
		wakeGrace:     8 * time.Second,
		waking:        make(map[string]wakeEntry),
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

	// Deliver offers to drivers that reconnected after a wake push.
	s.matureWaking(ctx)

	searchingOrders, err := s.offerRepo.ListSearchingWithoutOffer(ctx, 50)
	if err != nil {
		s.logger.Printf("dispatch: list searching without offer: %v", err)
		return
	}

	// Process orders in parallel with bounded concurrency (10 goroutines).
	// Sized to DB pool: 10 concurrent dispatchers × ~5 queries each = 50 connections,
	// well within MaxOpenConns=100. Prevents thundering herd on DB.
	var g errgroup.Group
	g.SetLimit(10)
	for _, ord := range searchingOrders {
		ord := ord
		g.Go(func() error {
			s.logger.Printf("dispatch: new order searching without offer order=%s", ord.ID)
			s.tryOfferNext(ctx, ord.ID)
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		s.logger.Printf("dispatch: batch error: %v", err)
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

	// Drivers currently being woken (push sent, awaiting reconnect) are also
	// excluded so we don't re-send a wake push on every tick.
	s.mu.Lock()
	for key, w := range s.waking {
		if w.orderID == orderID {
			exclude = append(exclude, w.driverID)
		}
		_ = key
	}
	s.mu.Unlock()

	offerTimeout := s.loadOfferTimeout(ctx)

	const perRound = 3 // водителей за круг перед повтором/расширением
	maxRounds := s.loadRoundLimit(ctx)
	if maxRounds < 1 {
		maxRounds = 1
	}

	// Determine the current dispatch round from how many drivers were already
	// offered in the current round. Every `perRound` offers advance to the
	// next round (a fresh attempt to the same nearest drivers). Once all
	// rounds are exhausted, the search zone is expanded and the client is
	// notified via EventOrderExpanded (the "expand zone?" toast).
	round := currentRound
	offeredThisRound := exclude
	if len(offeredThisRound) >= perRound {
		if round < maxRounds {
			round++
			offeredThisRound = nil // repeat the round with the same nearest drivers
			currentRound = round
		} else {
			// All rounds exhausted → expand the search zone + notify client.
			if !ord.IsExpanded {
				ord.IsExpanded = true
				now := s.clock.Now()
				expandedAt := now
				ord.ExpandedAt = &expandedAt
				if err := s.orderRepo.Update(ctx, ord); err != nil {
					s.logger.Printf("dispatch: update expanded flag order=%s: %v", ord.ID, err)
				}
				if err := s.eventPublisher.Publish(ctx, orderdomain.Event{
					Type:    orderdomain.EventOrderExpanded,
					OrderID: ord.ID,
					Payload: map[string]any{"status": ord.Status, "round": round},
				}); err != nil {
					s.logger.Printf("dispatch: publish order_expanded event order=%s: %v", ord.ID, err)
				}
				s.logger.Printf("dispatch: order=%s expanded after %d rounds", ord.ID, round)
			}
		}
	}

	// Search outward from the nearest zone. For each radius we try the
	// candidates in distance order, atomically reserving the driver row
	// (FOR UPDATE NOWAIT) and creating the offer in one transaction. This is
	// bounded: we make at most one offer per call and return; the next tick
	// (after an offer expires/rejects) continues from where we left off using
	// the persisted round/exclude state. This keeps each dispatch goroutine
	// short-lived and avoids lock contention storms under parallel dispatch.
	radius := s.stepRadiusKM
	var lastErr error
	for radius <= s.maxRadiusKM {
		candidates, err := s.matchingSvc.FindCandidates(ctx, ord, radius, offeredThisRound, s.hub, s.geoFreshness)
		if err != nil && err != matchingdomain.ErrNoCandidateDrivers {
			lastErr = err
		}
		if len(candidates) > 0 {
			assigned := false
			for _, candidate := range candidates {
				// Offline-online driver (no live WS): send a wake-up push and
				// wait for the app to reconnect before delivering the offer. If
				// the driver has already reconnected (WS present), deliver the
				// offer directly instead of re-waking.
				if candidate.NeedsWake && !s.hub.HasDriver(candidate.DriverID) {
					if s.tryWakeDriver(ctx, ord, candidate, round) {
						s.logger.Printf("dispatch: wake push sent order=%s driver=%s round=%d", ord.ID, candidate.DriverID, round)
						assigned = true
						break
					}
					continue
				}
				ok, offerID, assignErr := s.tryReserveAndOffer(ctx, ord, candidate, round, offerTimeout)
				if assignErr != nil {
					s.logger.Printf("dispatch: reserve+offer order=%s driver=%s: %v", ord.ID, candidate.DriverID, assignErr)
					lastErr = assignErr
					continue
				}
				if ok {
					s.logger.Printf("dispatch: offer %s created for order=%s driver=%s round=%d", offerID, ord.ID, candidate.DriverID, round)
					assigned = true
					break
				}
				// reserved=false → driver busy/locked by another tx → next candidate.
			}
			if assigned {
				return
			}
		}
		radius += s.stepRadiusKM
	}

	s.logger.Printf("dispatch: no candidate reserved for order=%s after reaching %gkm (last_err=%v)", orderID, s.maxRadiusKM, lastErr)

	// If any candidate is currently being woken (push sent, awaiting app
	// reconnect), do NOT give up on the order yet — matureWaking will deliver
	// the offer once the WebSocket reconnects, or drop it after the grace
	// window. Marking no_driver_found here would abort a valid wake flow.
	s.mu.Lock()
	hasWaking := false
	for key, w := range s.waking {
		if w.orderID == orderID {
			hasWaking = true
			break
		}
		_ = key
	}
	s.mu.Unlock()
	if hasWaking {
		s.logger.Printf("dispatch: order=%s has waking drivers, deferring no_driver_found", orderID)
		return
	}

	s.markNoDriverFound(ctx, ord)
}

// tryReserveAndOffer atomically reserves the candidate driver (FOR UPDATE
// NOWAIT) and creates the offer inside a single transaction. Returns:
//   - (true, offerID, nil)  — driver reserved and offer created
//   - (false, "", nil)      — driver busy/locked by another tx → caller tries next candidate
//   - (false, "", err)      — unexpected error
func (s *DispatchScheduler) tryReserveAndOffer(ctx context.Context, ord *orderdomain.Order, candidate matchingdomain.Candidate, round int, offerTimeout time.Duration) (bool, string, error) {
	now := s.clock.Now()
	offer := &orderdomain.Offer{
		ID:         s.idGen.NewID(),
		OrderID:    ord.ID,
		DriverID:   candidate.DriverID,
		Round:      round,
		DistanceKM: &candidate.DistanceKM,
		OfferedAt:  now,
		ExpiresAt:  now.Add(offerTimeout),
	}

	// When s.db is nil (tests with in-memory fakes), skip the real
	// transaction and call the tx-aware methods with a nil tx.
	if s.db == nil {
		reserved, err := s.driverRepo.ReserveForOfferTx(ctx, nil, candidate.DriverID)
		if err != nil {
			return false, "", err
		}
		if !reserved {
			return false, "", nil
		}
		created, err := s.offerRepo.CreateTx(ctx, nil, offer)
		if err != nil {
			return false, "", err
		}
		if !created {
			return false, "", nil
		}
		s.sendOfferPush(ctx, offer, ord, candidate.DistanceKM)
		return true, offer.ID, nil
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return false, "", err
	}
	defer tx.Rollback()

	reserved, err := s.driverRepo.ReserveForOfferTx(ctx, tx, candidate.DriverID)
	if err != nil {
		return false, "", err
	}
	if !reserved {
		// Driver busy or locked by another dispatch tx — not an error, just skip.
		return false, "", nil
	}

	created, err := s.offerRepo.CreateTx(ctx, tx, offer)
	if err != nil {
		return false, "", err
	}
	if !created {
		// Defensive: unique constraint conflict (shouldn't happen with reservation).
		return false, "", nil
	}

	if err := tx.Commit(); err != nil {
		return false, "", err
	}

	s.sendOfferPush(ctx, offer, ord, candidate.DistanceKM)
	return true, offer.ID, nil
}

// tryWakeDriver sends a wake-up push to an offline-online driver (available in
// the DB but without a live WebSocket) and enqueues them in the waking map. The
// actual order offer is delivered once the driver's app reconnects (see
// matureWaking). Returns true if the wake push was sent (caller should stop
// trying other candidates this round).
func (s *DispatchScheduler) tryWakeDriver(ctx context.Context, ord *orderdomain.Order, candidate matchingdomain.Candidate, round int) bool {
	key := ord.ID + ":" + candidate.DriverID
	s.mu.Lock()
	if _, exists := s.waking[key]; exists {
		s.mu.Unlock()
		return true // already waking this driver for this order
	}
	s.waking[key] = wakeEntry{
		orderID:   ord.ID,
		driverID:  candidate.DriverID,
		round:     round,
		expiresAt: s.clock.Now().Add(s.wakeGrace),
	}
	s.mu.Unlock()

	s.sendWakePush(ctx, ord, candidate)
	return true
}

// sendWakePush delivers a high-priority data message (no notification body) so
// the mobile OS wakes the app in the background; the app then reconnects its
// WebSocket and the dispatcher delivers the real offer via matureWaking.
func (s *DispatchScheduler) sendWakePush(ctx context.Context, ord *orderdomain.Order, candidate matchingdomain.Candidate) {
	if s.pushSender == nil {
		return
	}
	grace := int(s.wakeGrace.Seconds())
	data := map[string]string{
		"type":                  "driver_wake",
		"order_id":              ord.ID,
		"wake_grace_seconds":    fmt.Sprintf("%d", grace),
		"pickup_lat":            fmt.Sprintf("%f", ord.Pickup.Lat),
		"pickup_lng":            fmt.Sprintf("%f", ord.Pickup.Lng),
		"tow_truck_type":        string(ord.TowTruckType),
	}
	title := "Новый заказ"
	body := fmt.Sprintf("Эвакуатор %s — %.0f ₽", ord.TowTruckType, float64(ord.PriceTotal)/100)
	pushCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	if err := s.pushSender.SendToUser(pushCtx, candidate.DriverID, "driver", title, body, data); err != nil {
		s.logger.Printf("dispatch: wake push to driver=%s order=%s: %v", candidate.DriverID, ord.ID, err)
	}
}

// matureWaking checks drivers we previously sent a wake push to. If a driver
// has reconnected their WebSocket within the grace window, we deliver the real
// offer now. If the grace window elapsed without a reconnect, the entry is
// dropped so the next tick can try the next candidate (or mark no_driver_found).
func (s *DispatchScheduler) matureWaking(ctx context.Context) {
	now := s.clock.Now()
	var expired []wakeEntry
	var reconnected []wakeEntry
	s.mu.Lock()
	for key, w := range s.waking {
		if s.hub.HasDriver(w.driverID) {
			// Driver reconnected (app woke up) → deliver the offer now,
			// regardless of how much grace time is left.
			delete(s.waking, key)
			reconnected = append(reconnected, w)
		} else if now.After(w.expiresAt) {
			// Grace window elapsed with no reconnect → drop so the next tick
			// can try another candidate.
			delete(s.waking, key)
			expired = append(expired, w)
		}
	}
	s.mu.Unlock()

	for _, w := range reconnected {
		ord, err := s.orderRepo.GetByID(ctx, w.orderID)
		if err != nil || ord == nil {
			continue
		}
		if ord.Status != orderdomain.StatusSearching {
			continue
		}
		s.logger.Printf("dispatch: driver=%s reconnected after wake, delivering offer for order=%s", w.driverID, w.orderID)
		s.tryOfferNext(ctx, w.orderID)
	}
	for _, w := range expired {
		s.logger.Printf("dispatch: wake grace expired for driver=%s order=%s (no WS reconnect)", w.driverID, w.orderID)
	}
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
