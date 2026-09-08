package order

import (
	"context"
	od "evik/backend/internal/domain/order"
	pricing "evik/backend/internal/domain/pricing"
	routing "evik/backend/internal/domain/routing"
	"math"
	"testing"
	"time"
)

type routeStoreFake struct {
	ord   *od.Order
	meter *TripMeter
	saved *RouteQuote
}

func (s *routeStoreFake) GetByID(context.Context, string) (*od.Order, error) { return s.ord, nil }
func (s *routeStoreFake) GetTripMeter(context.Context, string) (*TripMeter, error) {
	return s.meter, nil
}
func (s *routeStoreFake) SaveRouteQuote(_ context.Context, q *RouteQuote) error {
	s.saved = q
	return nil
}
func (s *routeStoreFake) ApplyRouteQuote(context.Context, string, string, string, time.Time) (*od.Order, error) {
	return s.ord, nil
}

type routeTariffFake struct{}

func (routeTariffFake) GetActiveTariff(context.Context, od.TowTruckType) (*pricing.Tariff, error) {
	return &pricing.Tariff{IsActive: true, BasePrice: 100000, MinimumPrice: 100000, PricePerKm: 10000}, nil
}

type routeRoutingFake struct{ from od.Coordinate }

func (r *routeRoutingFake) CalculateRoute(_ context.Context, req routing.RouteRequest) (*routing.Route, error) {
	r.from = req.DriverLocation
	return &routing.Route{Distance: 3000}, nil
}
func (*routeRoutingFake) GetDirections(context.Context, routing.RouteRequest) ([]routing.RouteStep, error) {
	return nil, nil
}

func TestRouteDraftRules(t *testing.T) {
	d := RouteDraft{PickupLat: 42, PickupLng: 47, DropoffLat: 43, DropoffLng: 48, PickupAddress: "A"}
	for _, status := range []od.Status{od.StatusSearching, od.StatusAccepted, od.StatusArrived, od.StatusInProgress, od.StatusCompleted, od.StatusCancelled, od.StatusAwaitingPayment} {
		t.Run(string(status), func(t *testing.T) {
			ord := &od.Order{Status: status, Pickup: od.Coordinate{Lat: 42, Lng: 47}, PickupAddress: "A"}
			err := ValidateRouteDraft(ord, d)
			allowed := status == od.StatusSearching || status == od.StatusAccepted || status == od.StatusArrived || status == od.StatusInProgress
			if (err == nil) != allowed {
				t.Fatalf("status %s err %v", status, err)
			}
			changed := d
			changed.PickupLat = 44
			if status == od.StatusInProgress && ValidateRouteDraft(ord, changed) == nil {
				t.Fatal("pickup changed after loading")
			}
		})
	}
	d.PickupLat = math.NaN()
	if ValidateRouteDraft(&od.Order{Status: od.StatusSearching}, d) == nil {
		t.Fatal("NaN accepted")
	}
}
func TestRouteQuoteIncludesTravelledAndRemainingWithoutMutatingOrder(t *testing.T) {
	now := time.Now()
	ord := &od.Order{ID: "order", UserID: "client", Status: od.StatusInProgress, Pickup: od.Coordinate{Lat: 42, Lng: 47}, PriceTotal: 150000, SurchargeAmount: 5000}
	s := &routeStoreFake{ord: ord, meter: &TripMeter{Lat: 42.1, Lng: 47.1, DistanceMeters: 2000, ObservedAt: now, Complete: true}}
	routes := &routeRoutingFake{}
	uc := &ChangeRouteUseCase{Store: s, Tariffs: routeTariffFake{}, Routing: routes, Clock: fakeClock{now: now}, IDs: &seqIDGen{}}
	d := RouteDraft{PickupLat: 42, PickupLng: 47, DropoffLat: 43, DropoffLng: 48}
	q, err := uc.Quote(context.Background(), "client", "order", d)
	if err != nil {
		t.Fatal(err)
	}
	if q.DistanceMeters != 5000 || q.Price != 155000 {
		t.Fatalf("quote %+v", q)
	}
	if routes.from.Lat != 42.1 {
		t.Fatal("route did not start at current driver position")
	}
	if ord.PriceTotal != 150000 {
		t.Fatal("preview mutated order")
	}
	if _, err = uc.Quote(context.Background(), "stranger", "order", d); err == nil {
		t.Fatal("foreign order allowed")
	}
	for _, meter := range []*TripMeter{nil, {Complete: false, ObservedAt: now}, {Complete: true, ObservedAt: now.Add(-2 * time.Minute)}} {
		s.meter = meter
		if _, err = uc.Quote(context.Background(), "client", "order", d); err != ErrTripUnavailable {
			t.Fatalf("missing trip accepted: %v", err)
		}
	}
}
