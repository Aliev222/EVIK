//go:build integration

package postgres_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/infrastructure/postgres"
)

func TestCreateOrder_Idempotent(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 12, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-ik", "client")

	repo := postgres.NewOrderRepository(db)

	ik := "ik-double-" + uuid()

	order1 := &orderdomain.Order{
		ID:            "order-first-" + uuid(),
		UserID:        "client-ik",
		Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckType:  orderdomain.TowTruckWinch,
		Status:        orderdomain.StatusCreated,
		PriceTotal:    500000,
		PaymentMethod: "card",
		CreatedAt:     now,
		UpdatedAt:     now,
		IdempotencyKey: strPtr(ik),
	}

	if err := repo.Create(ctx, order1); err != nil {
		t.Fatalf("first create: %v", err)
	}
	t.Logf("first order id: %s", order1.ID)

	order2 := &orderdomain.Order{
		ID:            "order-second-" + uuid(),
		UserID:        "client-ik",
		Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckType:  orderdomain.TowTruckWinch,
		Status:        orderdomain.StatusCreated,
		PriceTotal:    500000,
		PaymentMethod: "card",
		CreatedAt:     now,
		UpdatedAt:     now,
		IdempotencyKey: strPtr(ik),
	}

	err := repo.Create(ctx, order2)
	if err == nil {
		t.Fatal("second create with same key: expected error, got nil")
	}
	if !isIdempotencyConflict(err) {
		t.Fatalf("second create: expected ErrIdempotencyConflict, got %v", err)
	}

	existing, err := repo.GetByOrderKey(ctx, ik)
	if err != nil {
		t.Fatalf("GetByOrderKey: %v", err)
	}
	if existing == nil {
		t.Fatal("GetByOrderKey returned nil")
	}
	if existing.ID != order1.ID {
		t.Errorf("GetByOrderKey returned order %s, want %s", existing.ID, order1.ID)
	}
}

func TestCreateOrder_DifferentKey_NewOrder(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 12, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-dk", "client")

	repo := postgres.NewOrderRepository(db)

	orderA := &orderdomain.Order{
		ID:            "order-a-" + uuid(),
		UserID:        "client-dk",
		Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckType:  orderdomain.TowTruckWinch,
		Status:        orderdomain.StatusCreated,
		PriceTotal:    500000,
		PaymentMethod: "card",
		CreatedAt:     now,
		UpdatedAt:     now,
		IdempotencyKey: strPtr("ik-a"),
	}
	if err := repo.Create(ctx, orderA); err != nil {
		t.Fatalf("create with ik-a: %v", err)
	}

	orderB := &orderdomain.Order{
		ID:            "order-b-" + uuid(),
		UserID:        "client-dk",
		Pickup:        orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:       orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckType:  orderdomain.TowTruckWinch,
		Status:        orderdomain.StatusCreated,
		PriceTotal:    500000,
		PaymentMethod: "card",
		CreatedAt:     now,
		UpdatedAt:     now,
		IdempotencyKey: strPtr("ik-b"),
	}
	if err := repo.Create(ctx, orderB); err != nil {
		t.Fatalf("create with ik-b: %v", err)
	}

	if orderA.ID == orderB.ID {
		t.Fatal("different keys should produce different orders, got same ID")
	}
}

func TestCreateOrder_EmptyKey_NoConflict(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 12, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-ek", "client")

	repo := postgres.NewOrderRepository(db)

	order1 := &orderdomain.Order{
		ID:             "order-empty1-" + uuid(),
		UserID:         "client-ek",
		Pickup:         orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:        orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckType:   orderdomain.TowTruckWinch,
		Status:         orderdomain.StatusCreated,
		PriceTotal:     500000,
		PaymentMethod:  "card",
		CreatedAt:      now,
		UpdatedAt:      now,
		IdempotencyKey: strPtr(""),
	}
	if err := repo.Create(ctx, order1); err != nil {
		t.Fatalf("first create with empty key: %v", err)
	}

	order2 := &orderdomain.Order{
		ID:             "order-empty2-" + uuid(),
		UserID:         "client-ek",
		Pickup:         orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
		Dropoff:        orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
		TowTruckType:   orderdomain.TowTruckWinch,
		Status:         orderdomain.StatusCreated,
		PriceTotal:     500000,
		PaymentMethod:  "card",
		CreatedAt:      now,
		UpdatedAt:      now,
		IdempotencyKey: strPtr(""),
	}
	if err := repo.Create(ctx, order2); err != nil {
		t.Fatalf("second create with empty key: %v", err)
	}

	if order1.ID == order2.ID {
		t.Fatal("empty keys should not conflict, got same order ID")
	}
}

func TestCreateOrder_Idempotent_Concurrent(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	now := time.Date(2026, 7, 12, 12, 0, 0, 0, time.UTC)

	seedUser(t, db, "client-cc", "client")

	repo := postgres.NewOrderRepository(db)
	ik := "ik-concurrent-" + uuid()

	var wg sync.WaitGroup
	start := make(chan struct{})
	created := make(chan string, 50)

	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start

			ord := &orderdomain.Order{
				ID:             "order-cc-" + uuid(),
				UserID:         "client-cc",
				Pickup:         orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
				Dropoff:        orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
				TowTruckType:   orderdomain.TowTruckWinch,
				Status:         orderdomain.StatusCreated,
				PriceTotal:     500000,
				PaymentMethod:  "card",
				CreatedAt:      now,
				UpdatedAt:      now,
				IdempotencyKey: strPtr(ik),
			}
			if err := repo.Create(ctx, ord); err == nil {
				created <- ord.ID
			}
		}()
	}
	close(start)
	wg.Wait()
	close(created)

	var ids []string
	for id := range created {
		ids = append(ids, id)
	}

	if len(ids) != 1 {
		t.Errorf("expected exactly 1 order created, got %d (ids: %v)", len(ids), ids)
	}

	existing, err := repo.GetByOrderKey(ctx, ik)
	if err != nil {
		t.Fatalf("GetByOrderKey: %v", err)
	}
	if existing == nil {
		t.Fatal("GetByOrderKey returned nil")
	}
	if len(ids) > 0 && existing.ID != ids[0] {
		t.Errorf("GetByOrderKey returned %s, but created was %s", existing.ID, ids[0])
	}
}

func isIdempotencyConflict(err error) bool {
	return errors.Is(err, orderdomain.ErrIdempotencyConflict)
}
