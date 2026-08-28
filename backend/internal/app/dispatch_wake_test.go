package app

import (
	"context"
	"log"
	"sync"
	"testing"
	"time"

	matchingdomain "evik/backend/internal/domain/matching"
	orderdomain "evik/backend/internal/domain/order"
	wsinfra "evik/backend/internal/infrastructure/websocket"
)

// --- fakes for wake-up flow ---

// wakeMatchingSvc returns the candidates exactly as configured, including
// drivers without a live WebSocket (NeedsWake=true). It does NOT hard-filter
// by HasDriver, mirroring the production matching service (the scheduler is
// responsible for waking such drivers).
type wakeMatchingSvc struct {
	mu       sync.Mutex
	candPool map[string][]matchingdomain.Candidate
}

func (f *wakeMatchingSvc) FindCandidates(_ context.Context, ord *orderdomain.Order, _ float64, exclude []string, _ matchingdomain.LiveDriverChecker, _ time.Duration) ([]matchingdomain.Candidate, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
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
		out = append(out, c)
	}
	if len(out) == 0 {
		return nil, matchingdomain.ErrNoCandidateDrivers
	}
	return out, nil
}

// capturePushSender records the data payloads of every push sent.
type capturePushSender struct {
	mu    sync.Mutex
	calls int
	datas []map[string]string
}

func (f *capturePushSender) SendToUser(_ context.Context, _, _, _, _ string, data map[string]string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	d := make(map[string]string, len(data))
	for k, v := range data {
		d[k] = v
	}
	f.datas = append(f.datas, d)
	return nil
}

// fakeClock lets tests advance time deterministically.
type fakeClock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

func newWakeScheduler(offerRepo *fakeOfferRepo, orderRepo *fakeOrderRepo, matchingSvc *wakeMatchingSvc, hub *wsinfra.Hub, push *capturePushSender, clk *fakeClock) *DispatchScheduler {
	eventPub := &fakeEventPub{}
	return NewDispatchScheduler(
		offerRepo,
		&fakeDriverRepo{},
		orderRepo,
		nil,
		matchingSvc,
		&fakeSettingsRepo{},
		hub,
		eventPub,
		push,
		&testIDGen{},
		clk,
		log.Default(),
		50*time.Millisecond,
		5*time.Second,
		time.Minute,
	)
}

func TestDispatchWakeSendsPushNotOffer(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	clk := &fakeClock{now: time.Now().UTC()}
	push := &capturePushSender{}
	ord := &orderdomain.Order{ID: "wo1", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"wo1": ord}}
	allOrders = []*orderdomain.Order{ord}
	offerRepo := &fakeOfferRepo{round: 1}
	matchingSvc := &wakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
		"wo1": {{DriverID: "wd1", DistanceKM: 2.0, NeedsWake: true}},
	}}

	sched := newWakeScheduler(offerRepo, orderRepo, matchingSvc, hub, push, clk)
	sched.tick(context.Background())

	// No offer created yet (driver has no live WS).
	if len(offerRepo.created) != 0 {
		t.Fatalf("expected 0 offers immediately, got %d", len(offerRepo.created))
	}
	// Wake push sent with the right type.
	if push.calls != 1 {
		t.Fatalf("expected 1 wake push, got %d", push.calls)
	}
	if push.datas[0]["type"] != "driver_wake" {
		t.Fatalf("expected push type=driver_wake, got %q", push.datas[0]["type"])
	}
	if push.datas[0]["order_id"] != "wo1" {
		t.Fatalf("expected push order_id=wo1, got %q", push.datas[0]["order_id"])
	}
	// Enqueued in waking map.
	sched.mu.Lock()
	_, waking := sched.waking["wo1:wd1"]
	sched.mu.Unlock()
	if !waking {
		t.Fatal("expected driver wd1 to be in waking map")
	}
}

func TestDispatchWakeDeliversOfferAfterReconnect(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	clk := &fakeClock{now: time.Now().UTC()}
	push := &capturePushSender{}
	ord := &orderdomain.Order{ID: "wo2", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"wo2": ord}}
	allOrders = []*orderdomain.Order{ord}
	offerRepo := &fakeOfferRepo{round: 1}
	matchingSvc := &wakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
		"wo2": {{DriverID: "wd2", DistanceKM: 2.0, NeedsWake: true}},
	}}

	sched := newWakeScheduler(offerRepo, orderRepo, matchingSvc, hub, push, clk)
	sched.tick(context.Background())
	if len(offerRepo.created) != 0 {
		t.Fatalf("expected 0 offers before reconnect, got %d", len(offerRepo.created))
	}

	// Driver's app reconnects (WebSocket appears).
	hub.Register(&wsinfra.Client{UserID: "wd2", Role: "driver", Send: make(chan []byte, 10)})
	waitHubDriver(t, hub, "wd2")

	sched.matureWaking(context.Background())

	if len(offerRepo.created) != 1 {
		t.Fatalf("expected 1 offer after reconnect, got %d", len(offerRepo.created))
	}
	if offerRepo.created[0].DriverID != "wd2" {
		t.Fatalf("expected offer for wd2, got %s", offerRepo.created[0].DriverID)
	}
	// Removed from waking map.
	sched.mu.Lock()
	_, waking := sched.waking["wo2:wd2"]
	sched.mu.Unlock()
	if waking {
		t.Fatal("expected driver wd2 removed from waking map after offer")
	}
}

func TestDispatchWakeGraceExpiryDropsEntry(t *testing.T) {
	hub := wsinfra.NewHub()
	go hub.Run()

	clk := &fakeClock{now: time.Now().UTC()}
	push := &capturePushSender{}
	ord := &orderdomain.Order{ID: "wo3", Pickup: orderdomain.Coordinate{Lat: 55.75, Lng: 37.62}, Status: orderdomain.StatusSearching}
	orderRepo := &fakeOrderRepo{orders: map[string]*orderdomain.Order{"wo3": ord}}
	allOrders = []*orderdomain.Order{ord}
	offerRepo := &fakeOfferRepo{round: 1}
	matchingSvc := &wakeMatchingSvc{candPool: map[string][]matchingdomain.Candidate{
		"wo3": {{DriverID: "wd3", DistanceKM: 2.0, NeedsWake: true}},
	}}

	sched := newWakeScheduler(offerRepo, orderRepo, matchingSvc, hub, push, clk)
	sched.tick(context.Background())
	if len(offerRepo.created) != 0 {
		t.Fatalf("expected 0 offers before reconnect, got %d", len(offerRepo.created))
	}

	// Advance clock past the wake grace window, no reconnect.
	clk.advance(sched.wakeGrace + time.Second)
	sched.matureWaking(context.Background())

	if len(offerRepo.created) != 0 {
		t.Fatalf("expected still 0 offers after grace (no reconnect), got %d", len(offerRepo.created))
	}
	sched.mu.Lock()
	_, waking := sched.waking["wo3:wd3"]
	sched.mu.Unlock()
	if waking {
		t.Fatal("expected driver wd3 dropped from waking map after grace expiry")
	}
}
