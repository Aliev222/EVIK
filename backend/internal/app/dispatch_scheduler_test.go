package app

import (
	"context"
	"log"
	"sync"
	"testing"
	"time"

	matchingdomain "evik/backend/internal/domain/matching"
	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/domain/settings"
	wsinfra "evik/backend/internal/infrastructure/websocket"
)

type fakeOfferRepo struct {
	mu      sync.Mutex
	offers  []*orderdomain.Offer
	created []*orderdomain.Offer
	round   int
}

func (f *fakeOfferRepo) Create(_ context.Context, offer *orderdomain.Offer) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	all := append(f.offers, f.created...)
	for _, o := range all {
		if o.OrderID == offer.OrderID && outcomeIsNil(o) {
			return false, nil
		}
		if o.DriverID == offer.DriverID && outcomeIsNil(o) {
			return false, nil
		}
	}
	offer.ID = "offer-" + offer.OrderID + "-" + offer.DriverID
	f.created = append(f.created, offer)
	return true, nil
}

func outcomeIsNil(o *orderdomain.Offer) bool { return o.Outcome == nil }

func (f *fakeOfferRepo) ExpirePending(_ context.Context) ([]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	now := time.Now().UTC()
	var expired []string
	for _, o := range f.offers {
		if o.Outcome == nil && o.ExpiresAt.Before(now) {
			outcome := "expired"
			o.Outcome = &outcome
			expired = append(expired, o.OrderID)
		}
	}
	return expired, nil
}

func (f *fakeOfferRepo) GetCurrentRound(_ context.Context, _ string) (int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.round, nil
}

func (f *fakeOfferRepo) ListOrderOfferedDriverIDs(_ context.Context, _ string, _ int) ([]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var ids []string
	for _, o := range f.offers {
		if o.Outcome == nil {
			ids = append(ids, o.DriverID)
		}
	}
	return ids, nil
}

func (f *fakeOfferRepo) ListSearchingWithoutOffer(_ context.Context, _ int) ([]*orderdomain.Order, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	hasOffer := map[string]bool{}
	all := append(f.offers, f.created...)
	for _, o := range all {
		if o.Outcome == nil {
			hasOffer[o.OrderID] = true
		}
	}
	var out []*orderdomain.Order
	for _, ord := range allOrders {
		if ord.Status == orderdomain.StatusSearching && !hasOffer[ord.ID] {
			out = append(out, ord)
		}
	}
	return out, nil
}

var allOrders []*orderdomain.Order

type fakeOrderRepo struct {
	mu     sync.Mutex
	orders map[string]*orderdomain.Order
}

func (f *fakeOrderRepo) GetByID(_ context.Context, id string) (*orderdomain.Order, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.orders[id], nil
}

func (f *fakeOrderRepo) Update(_ context.Context, ord *orderdomain.Order) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.orders[ord.ID] = ord
	return nil
}

type fakeMatchingSvc struct {
	mu       sync.Mutex
	calls    int
	candPool map[string][]matchingdomain.Candidate
}

func (f *fakeMatchingSvc) FindCandidates(_ context.Context, ord *orderdomain.Order, _ float64, exclude []string, liveChecker matchingdomain.LiveDriverChecker, _ time.Duration) ([]matchingdomain.Candidate, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	excludeSet := make(map[string]bool)
	for _, id := range exclude {
		excludeSet[id] = true
	}
	pool := f.candPool[ord.ID]
	var out []matchingdomain.Candidate
	for _, c := range pool {
		if excludeSet[c.DriverID] {
			continue
		}
		if liveChecker != nil && !liveChecker.HasDriver(c.DriverID) {
			continue
		}
		out = append(out, c)
	}
	if len(out) == 0 {
		return nil, matchingdomain.ErrNoCandidateDrivers
	}
	return out, nil
}

type fakeSettingsRepo struct {
	settings []settings.Setting
}

func (f *fakeSettingsRepo) List(_ context.Context) ([]settings.Setting, error) {
	return f.settings, nil
}

type fakeEventPub struct {
	events []orderdomain.Event
	mu     sync.Mutex
}

func (f *fakeEventPub) Publish(_ context.Context, event orderdomain.Event) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.events = append(f.events, event)
	return nil
}

type fakePushSender struct {
	calls int
	mu    sync.Mutex
}

func (f *fakePushSender) SendToUser(_ context.Context, _, _, _, _ string, _ map[string]string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	return nil
}

type testIDGen struct {
	mu  sync.Mutex
	seq int
}

func (g *testIDGen) NewID() string {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.seq++
	return "id-" + time.Now().Format("150405") + "-" + string(rune('a'+g.seq))
}

type testClock struct{}

func (testClock) Now() time.Time { return time.Now().UTC() }

func newTestScheduler(offerRepo *fakeOfferRepo, orderRepo *fakeOrderRepo, matchingSvc *fakeMatchingSvc, settingsRepo *fakeSettingsRepo, hub *wsinfra.Hub) *DispatchScheduler {
	eventPub := &fakeEventPub{}
	pushSender := &fakePushSender{}
	return NewDispatchScheduler(
		offerRepo,
		orderRepo,
		matchingSvc,
		settingsRepo,
		hub,
		eventPub,
		pushSender,
		&testIDGen{},
		testClock{},
		log.Default(),
		50*time.Millisecond,
		5*time.Second,
		time.Minute,
	)
}

func TestDispatchOfferCreatedForNearest(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	ord := &orderdomain.Order{ID: "o1", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	allOrders = []*orderdomain.Order{ord}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"o1": ord}}
	offerRepo := &fakeOfferRepo{round: 1}

	matchingSvc := &fakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
		"o1": {{DriverID: "d1", DistanceKM: 1.5}},
	}}

	hub.Register(&wsinfra.Client{UserID: "d1", Role: "driver", Send: make(chan []byte, 10)})
	waitHubDriver(t, hub, "d1")

	sched := newTestScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub)
	sched.tick(context.Background())

	if len(offerRepo.created) != 1 {
		t.Fatalf("expected 1 offer created, got %d", len(offerRepo.created))
	}
	if offerRepo.created[0].DriverID != "d1" {
		t.Fatalf("expected offer for d1, got %s", offerRepo.created[0].DriverID)
	}
}

func TestDispatchNoCandidatesNoDriverFound(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	ord := &orderdomain.Order{ID: "o2", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	allOrders = []*orderdomain.Order{ord}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"o2": ord}}
	offerRepo := &fakeOfferRepo{round: 1}
	matchingSvc := &fakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{"o2": {}}}

	sched := newTestScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub)
	eventPub := sched.eventPublisher.(*fakeEventPub)

	sched.tick(context.Background())

	if len(offerRepo.created) != 0 {
		t.Fatalf("expected 0 offers created, got %d", len(offerRepo.created))
	}

	hasNoDriver := false
	for _, e := range eventPub.events {
		if e.Type == orderdomain.EventNoDriverFound {
			hasNoDriver = true
			break
		}
	}
	if !hasNoDriver {
		t.Fatal("expected no_driver_found event")
	}
	if ord.Status != orderdomain.StatusNoDriverFound {
		t.Fatalf("expected order status no_driver_found, got %s", ord.Status)
	}
}

func TestDispatchExpiredOfferNextDriver(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	ord := &orderdomain.Order{ID: "o3", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	allOrders = []*orderdomain.Order{ord}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"o3": ord}}
	offerRepo := &fakeOfferRepo{round: 1}

	expired := "expired"
	offerRepo.offers = []*orderdomain.Offer{
		{OrderID: "o3", DriverID: "d1", Round: 1, ExpiresAt: time.Now().UTC().Add(-time.Second), Outcome: &expired},
	}

	matchingSvc := &fakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
		"o3": {{DriverID: "d2", DistanceKM: 3.0}},
	}}

	hub.Register(&wsinfra.Client{UserID: "d2", Role: "driver", Send: make(chan []byte, 10)})
	waitHubDriver(t, hub, "d2")

	sched := newTestScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub)
	sched.tick(context.Background())

	foundNew := false
	for _, c := range offerRepo.created {
		if c.DriverID == "d2" {
			foundNew = true
			break
		}
	}
	if !foundNew {
		t.Fatal("expected new offer for d2 after d1 expired, none found")
	}
}

func TestDispatchDeclinedNextDriver(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	ord := &orderdomain.Order{ID: "o4", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	allOrders = []*orderdomain.Order{ord}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"o4": ord}}
	offerRepo := &fakeOfferRepo{round: 1}

	declined := "declined"
	offerRepo.offers = []*orderdomain.Offer{
		{OrderID: "o4", DriverID: "d1", Round: 1, ExpiresAt: time.Now().UTC().Add(time.Hour), Outcome: &declined},
	}

	matchingSvc := &fakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
		"o4": {{DriverID: "d2", DistanceKM: 2.0}},
	}}

	hub.Register(&wsinfra.Client{UserID: "d2", Role: "driver", Send: make(chan []byte, 10)})
	waitHubDriver(t, hub, "d2")

	sched := newTestScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub)
	sched.tick(context.Background())

	foundNew := false
	for _, c := range offerRepo.created {
		if c.DriverID == "d2" {
			foundNew = true
			break
		}
	}
	if !foundNew {
		t.Fatal("expected new offer for d2 after d1 declined, none found")
	}
}

func TestDispatchOfflineDriverSkipped(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	ord := &orderdomain.Order{ID: "o5", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	allOrders = []*orderdomain.Order{ord}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"o5": ord}}
	offerRepo := &fakeOfferRepo{round: 1}

	matchingSvc := &fakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
		"o5": {{DriverID: "d1", DistanceKM: 1.0}},
	}}

	sched := newTestScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub)
	sched.tick(context.Background())

	if len(offerRepo.created) != 0 {
		t.Fatalf("expected 0 offers for d1 (no WS), got %d", len(offerRepo.created))
	}
}

func TestDispatchAcceptedOfferOrderAssigned(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	ord := &orderdomain.Order{ID: "o6", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	allOrders = []*orderdomain.Order{ord}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"o6": ord}}
	offerRepo := &fakeOfferRepo{round: 1}

	matchingSvc := &fakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
		"o6": {{DriverID: "d1", DistanceKM: 1.0}},
	}}

	hub.Register(&wsinfra.Client{UserID: "d1", Role: "driver", Send: make(chan []byte, 10)})
	waitHubDriver(t, hub, "d1")

	sched := newTestScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub)
	sched.tick(context.Background())

	if len(offerRepo.created) != 1 {
		t.Fatalf("expected 1 offer, got %d", len(offerRepo.created))
	}

	ord.DriverID = &offerRepo.created[0].DriverID
	ord.Status = orderdomain.StatusAccepted

	offerRepo.offers = append(offerRepo.offers, offerRepo.created...)
	// Second tick: no new offers since order is accepted
	sched.tick(context.Background())

	if len(offerRepo.created) != 1 {
		t.Fatalf("expected still 1 offer (no new after accept), got %d", len(offerRepo.created))
	}
}

func waitHubDriver(t *testing.T, hub *wsinfra.Hub, driverID string) {
	t.Helper()
	for i := 0; i < 100; i++ {
		if hub.HasDriver(driverID) {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("hub driver %s not registered after 100ms", driverID)
}

func TestDispatchOneOfferPerOrderConcurrent(t *testing.T) {
	for iter := 0; iter < 50; iter++ {
		hub := wsinfra.NewHub()
		go hub.Run()

		ord := &orderdomain.Order{ID: "o-con", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
		allOrders = []*orderdomain.Order{ord}
		orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"o-con": ord}}
		offerRepo := &fakeOfferRepo{round: 1}
		matchingSvc := &fakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
			"o-con": {{DriverID: "d1", DistanceKM: 1.0}},
		}}
		hub.Register(&wsinfra.Client{UserID: "d1", Role: "driver", Send: make(chan []byte, 10)})
		waitHubDriver(t, hub, "d1")

		eventPub := &fakeEventPub{}
		pushSender := &fakePushSender{}

		sched1 := NewDispatchScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub, eventPub, pushSender, &testIDGen{}, testClock{}, log.Default(), time.Microsecond, 5*time.Second, time.Minute)
		sched2 := NewDispatchScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub, eventPub, pushSender, &testIDGen{}, testClock{}, log.Default(), time.Microsecond, 5*time.Second, time.Minute)

		var wg sync.WaitGroup
		wg.Add(2)
		go func() { sched1.tick(context.Background()); wg.Done() }()
		go func() { sched2.tick(context.Background()); wg.Done() }()
		wg.Wait()

		if len(offerRepo.created) != 1 {
			t.Fatalf("iteration %d: expected exactly 1 offer from 2 concurrent ticks, got %d", iter, len(offerRepo.created))
		}
	}
}

func TestDispatchLateAcceptRejected(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	ord := &orderdomain.Order{ID: "o-late", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching, DriverID: strPtr("d2")}
	allOrders = []*orderdomain.Order{ord}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"o-late": ord}}
	offerRepo := &fakeOfferRepo{round: 1}

	outcome := "expired"
	offerRepo.offers = []*orderdomain.Offer{
		{OrderID: "o-late", DriverID: "d1", Round: 1, ExpiresAt: time.Now().UTC().Add(-time.Minute), Outcome: &outcome},
	}

	offerRepo.offers = append(offerRepo.offers, &orderdomain.Offer{
		OrderID: "o-late", DriverID: "d2", Round: 1, ExpiresAt: time.Now().UTC().Add(time.Hour), Outcome: strPtr("accepted"),
	})

	matchingSvc := &fakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{}}

	sched := newTestScheduler(offerRepo, orderRepo, matchingSvc, &fakeSettingsRepo{}, hub)
	sched.tick(context.Background())

	if len(offerRepo.created) != 0 {
		t.Fatalf("expected 0 new offers (order already assigned), got %d", len(offerRepo.created))
	}
}

func strPtr(s string) *string { return &s }
