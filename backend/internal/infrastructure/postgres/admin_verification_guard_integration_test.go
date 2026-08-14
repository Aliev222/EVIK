//go:build integration

package postgres_test

import (
	"context"
	"errors"
	"testing"

	admindomain "evik/backend/internal/domain/admin"
	"evik/backend/internal/infrastructure/postgres"
)

func pendingVerificationItem(driverID string) admindomain.DriverVerification {
	return admindomain.DriverVerification{
		ID:          driverID,
		UserID:      driverID,
		DriverName:  "Driver",
		Vehicle:     "GAZ",
		Plate:       "A000AA77",
		VehicleType: "winch",
		Status:      admindomain.VerificationStatusPending,
		Risk:        "low",
		Documents:   []string{"http://x/1.jpg"},
	}
}

// TestUpsertDriverVerification_BlockedIsSticky is the source-of-truth guard
// behind POST /driver-verifications: a blocked verification can never be
// flipped back to pending by a resubmission, while rejected and
// changes_requested verifications can.
func TestUpsertDriverVerification_BlockedIsSticky(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	repo := postgres.NewAdminRepository(db)

	t.Run("blocked resubmission is refused and status stays blocked", func(t *testing.T) {
		seedVerification(t, db, "v-blocked", "v-blocked", "blocked")

		err := repo.UpsertDriverVerification(ctx, pendingVerificationItem("v-blocked"))
		if !errors.Is(err, admindomain.ErrDriverVerificationBlocked) {
			t.Fatalf("err = %v, want ErrDriverVerificationBlocked", err)
		}
		if got := verificationStatus(t, db, "v-blocked"); got != admindomain.VerificationStatusBlocked {
			t.Fatalf("status = %q, want %q (block must persist)", got, admindomain.VerificationStatusBlocked)
		}
	})

	t.Run("blocked survives repeated resubmission attempts", func(t *testing.T) {
		seedVerification(t, db, "v-blocked2", "v-blocked2", "blocked")

		for i := 0; i < 3; i++ {
			if err := repo.UpsertDriverVerification(ctx, pendingVerificationItem("v-blocked2")); !errors.Is(err, admindomain.ErrDriverVerificationBlocked) {
				t.Fatalf("attempt %d: err = %v, want ErrDriverVerificationBlocked", i, err)
			}
		}
		if got := verificationStatus(t, db, "v-blocked2"); got != admindomain.VerificationStatusBlocked {
			t.Fatalf("status = %q, want blocked", got)
		}
	})

	t.Run("rejected resubmission flips to pending", func(t *testing.T) {
		seedVerification(t, db, "v-rejected", "v-rejected", "rejected")
		if err := repo.UpsertDriverVerification(ctx, pendingVerificationItem("v-rejected")); err != nil {
			t.Fatalf("upsert rejected driver: %v", err)
		}
		if got := verificationStatus(t, db, "v-rejected"); got != admindomain.VerificationStatusPending {
			t.Fatalf("status = %q, want pending", got)
		}
	})

	t.Run("changes_requested resubmission flips to pending", func(t *testing.T) {
		seedVerification(t, db, "v-changes", "v-changes", "changes_requested")
		if err := repo.UpsertDriverVerification(ctx, pendingVerificationItem("v-changes")); err != nil {
			t.Fatalf("upsert changes_requested driver: %v", err)
		}
		if got := verificationStatus(t, db, "v-changes"); got != admindomain.VerificationStatusPending {
			t.Fatalf("status = %q, want pending", got)
		}
	})

	t.Run("fresh submission is allowed", func(t *testing.T) {
		if err := repo.UpsertDriverVerification(ctx, pendingVerificationItem("v-new")); err != nil {
			t.Fatalf("upsert fresh submission: %v", err)
		}
		if got := verificationStatus(t, db, "v-new"); got != admindomain.VerificationStatusPending {
			t.Fatalf("status = %q, want pending", got)
		}
	})
}