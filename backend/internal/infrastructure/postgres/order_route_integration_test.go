//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	evik "evik/backend"
	od "evik/backend/internal/domain/order"
	pg "evik/backend/internal/infrastructure/postgres"
	uc "evik/backend/internal/usecase/order"
	"fmt"
	"github.com/pressly/goose/v3"
	"os"
	"testing"
	"time"
)

func TestRouteChangeTransaction(t *testing.T) {
	dsn := os.Getenv("EVIK_ROUTE_TEST_DSN")
	if dsn == "" {
		t.Skip("EVIK_ROUTE_TEST_DSN must point to an isolated temporary database")
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	goose.SetBaseFS(evik.EmbedMigrations)
	goose.SetLogger(goose.NopLogger())
	if err = goose.SetDialect("postgres"); err != nil {
		t.Fatal(err)
	}
	if err = goose.Up(db, "migrations"); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	repo := pg.NewOrderRepository(db)
	clientID := fmt.Sprintf("route-client-%d", time.Now().UnixNano())
	seedUser(t, db, clientID, "client")
	now := time.Now().UTC().Truncate(time.Microsecond)
	ord, err := od.NewOrder(clientID+"-order", clientID, od.Coordinate{Lat: 42, Lng: 47}, od.Coordinate{Lat: 43, Lng: 48}, od.TowTruckWinch, now)
	if err != nil {
		t.Fatal(err)
	}
	ord.Status = od.StatusSearching
	ord.IdempotencyKey = &ord.ID
	ord.PriceTotal = 100000
	ord.PaymentMethod = "cash"
	ord.PickupAddress = "A"
	ord.DropoffAddress = "B"
	if err = repo.Create(ctx, ord); err != nil {
		t.Fatal(err)
	}
	q := &uc.RouteQuote{ID: "route-quote-1", OrderID: ord.ID, UserID: ord.UserID, Snapshot: now, Price: 200000, ExpiresAt: now.Add(time.Minute), Draft: uc.RouteDraft{PickupLat: 42.1, PickupLng: 47.1, DropoffLat: 43.1, DropoffLng: 48.1, PickupAddress: "New A", DropoffAddress: "New B"}}
	q.ID = clientID + "-quote-1"
	if err = repo.SaveRouteQuote(ctx, q); err != nil {
		t.Fatal(err)
	}
	if _, err = repo.ApplyRouteQuote(ctx, "stranger", ord.ID, q.ID, now); err == nil {
		t.Fatal("foreign caller applied quote")
	}
	saved, err := repo.GetByID(ctx, ord.ID)
	if err != nil {
		t.Fatal(err)
	}
	if saved.PriceTotal != 100000 || saved.PickupAddress != "A" {
		t.Fatal("preview mutated order")
	}
	saved, err = repo.ApplyRouteQuote(ctx, ord.UserID, ord.ID, q.ID, now.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if saved.PriceTotal != 200000 || saved.PickupAddress != "New A" || saved.Dropoff.Lng != 48.1 || saved.Status != od.StatusSearching {
		t.Fatalf("incorrect persisted order %+v", saved)
	}
	if _, err = repo.ApplyRouteQuote(ctx, ord.UserID, ord.ID, q.ID, now.Add(2*time.Second)); err != nil {
		t.Fatalf("retry failed: %v", err)
	}
	q.ID = clientID + "-quote-2"
	q.Snapshot = saved.UpdatedAt
	q.Draft.PickupLat = 45
	if err = repo.SaveRouteQuote(ctx, q); err != nil {
		t.Fatal(err)
	}
	if err = repo.UpdateStatus(ctx, ord.ID, od.StatusInProgress, now.Add(3*time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err = repo.ApplyRouteQuote(ctx, ord.UserID, ord.ID, q.ID, now.Add(4*time.Second)); err == nil {
		t.Fatal("stale quote applied after loading")
	}
	saved, _ = repo.GetByID(ctx, ord.ID)
	if saved.Pickup.Lat != 42.1 {
		t.Fatal("pickup changed after loading")
	}
	q.ID = clientID + "-quote-loaded-pickup"
	q.Snapshot = saved.UpdatedAt
	q.ExpiresAt = now.Add(time.Minute)
	q.Draft.PickupLat = saved.Pickup.Lat + 0.01
	if err = repo.SaveRouteQuote(ctx, q); err != nil {
		t.Fatal(err)
	}
	if _, err = repo.ApplyRouteQuote(ctx, ord.UserID, ord.ID, q.ID, now.Add(5*time.Second)); err == nil {
		t.Fatal("loaded order accepted changed pickup")
	}
	q.ID = clientID + "-quote-expired"
	q.Snapshot = saved.UpdatedAt
	q.ExpiresAt = now
	q.Draft.PickupLat = saved.Pickup.Lat
	q.Draft.PickupLng = saved.Pickup.Lng
	q.Draft.PickupAddress = saved.PickupAddress
	if err = repo.SaveRouteQuote(ctx, q); err != nil {
		t.Fatal(err)
	}
	if _, err = repo.ApplyRouteQuote(ctx, ord.UserID, ord.ID, q.ID, now.Add(6*time.Second)); err == nil {
		t.Fatal("expired quote accepted")
	}
}
