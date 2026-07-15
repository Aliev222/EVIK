//go:build integration

package postgres_test

import (
	"context"
	"sync"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	"evik/backend/internal/infrastructure/postgres"
)

func TestOfferRepository_OneActiveOfferPerOrder_Concurrent(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	orderID := "test-order"
	driver1 := "driver-1"
	driver2 := "driver-2"

	seedUser(t, db, driver1, "driver")
	seedUser(t, db, driver2, "driver")
	seedDriver(t, db, driver1)
	seedDriver(t, db, driver2)
	seedUser(t, db, "client-test", "client")
	seedOrderRaw(t, db, orderID, "client-test")
	setOrderSearching(t, db, orderID)

	offerRepo := postgres.NewOfferRepository(db)

	for iter := 0; iter < 50; iter++ {
		db.Exec(`DELETE FROM order_offers`)

		db.Exec(`UPDATE orders SET status = 'searching', updated_at = NOW() WHERE id = $1`, orderID)

		start := make(chan struct{})
		var wg sync.WaitGroup
		created1, created2 := false, false
		var err1, err2 error

		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			offer1 := &orderdomain.Offer{
				ID:         "offer-" + uuid() + "-1",
				OrderID:    orderID,
				DriverID:   driver1,
				Round:      1,
				OfferedAt:  time.Now(),
				ExpiresAt:  time.Now().Add(time.Hour),
				DistanceKM: float64Ptr(5.5),
			}
			created1, err1 = offerRepo.Create(context.Background(), offer1)
		}()

		go func() {
			defer wg.Done()
			<-start
			offer2 := &orderdomain.Offer{
				ID:         "offer-" + uuid() + "-2",
				OrderID:    orderID,
				DriverID:   driver2,
				Round:      1,
				OfferedAt:  time.Now(),
				ExpiresAt:  time.Now().Add(time.Hour),
				DistanceKM: float64Ptr(6.5),
			}
			created2, err2 = offerRepo.Create(context.Background(), offer2)
		}()

		close(start)
		wg.Wait()

		if err1 != nil {
			t.Fatalf("iteration %d: driver1 create error: %v", iter, err1)
		}
		if err2 != nil {
			t.Fatalf("iteration %d: driver2 create error: %v", iter, err2)
		}

		if created1 == created2 {
			t.Fatalf("iteration %d: expected exactly one success, got created1=%v created2=%v", iter, created1, created2)
		}

		var count int
		err := db.QueryRow(`SELECT COUNT(*) FROM order_offers WHERE order_id = $1 AND outcome IS NULL`, orderID).Scan(&count)
		if err != nil {
			t.Fatalf("iteration %d: count query error: %v", iter, err)
		}
		if count != 1 {
			t.Fatalf("iteration %d: expected 1 active offer, got %d", iter, count)
		}

		var dbCreated1, dbCreated2 bool
		err = db.QueryRow(`SELECT COUNT(*) > 0 FROM order_offers WHERE order_id = $1 AND driver_id = $2 AND outcome IS NULL`, orderID, driver1).Scan(&dbCreated1)
		if err != nil {
			t.Fatalf("iteration %d: check driver1 error: %v", iter, err)
		}
		err = db.QueryRow(`SELECT COUNT(*) > 0 FROM order_offers WHERE order_id = $1 AND driver_id = $2 AND outcome IS NULL`, orderID, driver2).Scan(&dbCreated2)
		if err != nil {
			t.Fatalf("iteration %d: check driver2 error: %v", iter, err)
		}

		if dbCreated1 == dbCreated2 {
			t.Fatalf("iteration %d: expected exactly one driver to have offer, got driver1=%v driver2=%v", iter, dbCreated1, dbCreated2)
		}
	}
}

func TestOfferRepository_OneActiveOfferPerDriver_Concurrent(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	driverID := "test-driver"
	order1 := "order-1"
	order2 := "order-2"

	seedUser(t, db, driverID, "driver")
	seedDriver(t, db, driverID)
	seedUser(t, db, "client-1", "client")
	seedUser(t, db, "client-2", "client")
	seedOrderRaw(t, db, order1, "client-1")
	seedOrderRaw(t, db, order2, "client-2")
	setOrderSearching(t, db, order1)
	setOrderSearching(t, db, order2)

	offerRepo := postgres.NewOfferRepository(db)

	for iter := 0; iter < 50; iter++ {
		db.Exec(`DELETE FROM order_offers`)

		db.Exec(`UPDATE orders SET status = 'searching', updated_at = NOW() WHERE id IN ($1, $2)`, order1, order2)

		start := make(chan struct{})
		var wg sync.WaitGroup
		created1, created2 := false, false
		var err1, err2 error

		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			offer1 := &orderdomain.Offer{
				ID:         "offer-" + uuid() + "-1",
				OrderID:    order1,
				DriverID:   driverID,
				Round:      1,
				OfferedAt:  time.Now(),
				ExpiresAt:  time.Now().Add(time.Hour),
				DistanceKM: float64Ptr(5.5),
			}
			created1, err1 = offerRepo.Create(context.Background(), offer1)
		}()

		go func() {
			defer wg.Done()
			<-start
			offer2 := &orderdomain.Offer{
				ID:         "offer-" + uuid() + "-2",
				OrderID:    order2,
				DriverID:   driverID,
				Round:      1,
				OfferedAt:  time.Now(),
				ExpiresAt:  time.Now().Add(time.Hour),
				DistanceKM: float64Ptr(6.5),
			}
			created2, err2 = offerRepo.Create(context.Background(), offer2)
		}()

		close(start)
		wg.Wait()

		if err1 != nil {
			t.Fatalf("iteration %d: order1 create error: %v", iter, err1)
		}
		if err2 != nil {
			t.Fatalf("iteration %d: order2 create error: %v", iter, err2)
		}

		if created1 == created2 {
			t.Fatalf("iteration %d: expected exactly one success, got created1=%v created2=%v", iter, created1, created2)
		}

		var count int
		err := db.QueryRow(`SELECT COUNT(*) FROM order_offers WHERE driver_id = $1 AND outcome IS NULL`, driverID).Scan(&count)
		if err != nil {
			t.Fatalf("iteration %d: count query error: %v", iter, err)
		}
		if count != 1 {
			t.Fatalf("iteration %d: expected 1 active offer, got %d", iter, count)
		}

		var dbCreated1, dbCreated2 bool
		err = db.QueryRow(`SELECT COUNT(*) > 0 FROM order_offers WHERE driver_id = $1 AND order_id = $2 AND outcome IS NULL`, driverID, order1).Scan(&dbCreated1)
		if err != nil {
			t.Fatalf("iteration %d: check order1 error: %v", iter, err)
		}
		err = db.QueryRow(`SELECT COUNT(*) > 0 FROM order_offers WHERE driver_id = $1 AND order_id = $2 AND outcome IS NULL`, driverID, order2).Scan(&dbCreated2)
		if err != nil {
			t.Fatalf("iteration %d: check order2 error: %v", iter, err)
		}

		if dbCreated1 == dbCreated2 {
			t.Fatalf("iteration %d: expected exactly one order to have offer, got order1=%v order2=%v", iter, dbCreated1, dbCreated2)
		}
	}
}

func float64Ptr(v float64) *float64 {
	return &v
}
