//go:build integration

package postgres_test

import (
	"context"
	"testing"

	"evik/backend/internal/infrastructure/postgres"
)

// TestGetDriverRating_ExcludesHiddenReviews proves the public (non-admin)
// aggregate is computed over non-hidden reviews only: hidden/moderated-away
// reviews must neither appear as text nor skew the average/count served to
// non-admin clients.
func TestGetDriverRating_ExcludesHiddenReviews(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	driverID := "rating-privacy-driver"
	clientID := "rating-privacy-client"
	seedUser(t, db, driverID, "driver")
	seedUser(t, db, clientID, "client")
	seedDriver(t, db, driverID)

	for _, oid := range []string{"rp-order-1", "rp-order-2", "rp-order-3"} {
		seedOrderRaw(t, db, oid, clientID)
	}
	if _, err := db.Exec(`UPDATE orders SET driver_id = $1 WHERE user_id = $2`, driverID, clientID); err != nil {
		t.Fatalf("assign orders to driver: %v", err)
	}

	// Two visible reviews (5 and 3 stars → avg 4.0) and one hidden review
	// (1 star) that must not influence the public aggregate.
	seedReview := func(orderID string, stars int, hidden bool, text string) {
		t.Helper()
		if _, err := db.Exec(`INSERT INTO driver_reviews (order_id, driver_id, client_id, stars, comment, is_hidden, created_at)
VALUES ($1, $2, $3, $4, $5, $6, NOW())`, orderID, driverID, clientID, stars, text, hidden); err != nil {
			t.Fatalf("insert review %s: %v", orderID, err)
		}
	}
	seedReview("rp-order-1", 5, false, "Отличный водитель")
	seedReview("rp-order-2", 3, false, "Нормально")
	seedReview("rp-order-3", 1, true, "Скрытый отзыв с текстом")

	repo := postgres.NewAdminRepository(db)

	stats, err := repo.GetDriverRating(ctx, driverID)
	if err != nil {
		t.Fatalf("GetDriverRating: %v", err)
	}
	if stats.Total != 2 || stats.RatingCount != 2 {
		t.Fatalf("total/rating_count = %d/%d, want 2/2 (hidden must be excluded)", stats.Total, stats.RatingCount)
	}
	if stats.RatingAverage < 3.99 || stats.RatingAverage > 4.01 {
		t.Fatalf("rating_average = %.2f, want ~4.0 (avg of 5 and 3, hidden excluded)", stats.RatingAverage)
	}
}

// TestGetDriverReviews_AdminSeesAllIncludingHidden proves the admin path keeps
// the full list (including hidden reviews and their texts), while the stats it
// returns cover every review for the driver.
func TestGetDriverReviews_AdminSeesAllIncludingHidden(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	driverID := "admin-reviews-driver"
	clientID := "admin-reviews-client"
	seedUser(t, db, driverID, "driver")
	seedUser(t, db, clientID, "client")
	seedDriver(t, db, driverID)

	for _, oid := range []string{"ar-order-1", "ar-order-2"} {
		seedOrderRaw(t, db, oid, clientID)
	}
	if _, err := db.Exec(`UPDATE orders SET driver_id = $1 WHERE user_id = $2`, driverID, clientID); err != nil {
		t.Fatalf("assign orders to driver: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO driver_reviews (order_id, driver_id, client_id, stars, comment, is_hidden, created_at)
VALUES ('ar-order-1', $1, $2, 5, 'Видимый отзыв', false, NOW())`, driverID, clientID); err != nil {
		t.Fatalf("insert visible review: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO driver_reviews (order_id, driver_id, client_id, stars, comment, is_hidden, created_at)
VALUES ('ar-order-2', $1, $2, 1, 'Скрытый отзыв', true, NOW())`, driverID, clientID); err != nil {
		t.Fatalf("insert hidden review: %v", err)
	}

	repo := postgres.NewAdminRepository(db)

	reviews, stats, err := repo.GetDriverReviews(ctx, driverID, 50)
	if err != nil {
		t.Fatalf("GetDriverReviews: %v", err)
	}
	if len(reviews) != 2 {
		t.Fatalf("items = %d, want 2 (admin sees hidden too)", len(reviews))
	}
	seenHidden := false
	for _, r := range reviews {
		if r.OrderID == "ar-order-2" && r.Text == "Скрытый отзыв" {
			seenHidden = true
		}
	}
	if !seenHidden {
		t.Fatal("admin review list must include the hidden review text")
	}
	if stats.Total != 2 || stats.RatingCount != 2 {
		t.Fatalf("total/rating_count = %d/%d, want 2/2", stats.Total, stats.RatingCount)
	}
}
