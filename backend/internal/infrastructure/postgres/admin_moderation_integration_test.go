//go:build integration

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	admindomain "evik/backend/internal/domain/admin"
	"evik/backend/internal/infrastructure/postgres"
)

// seedVerification inserts a driver verification row for the given user with
// the provided status and (optionally) vehicle data.
func seedVerification(t *testing.T, db *sql.DB, verID, userID, status string) {
	t.Helper()
	_, err := db.Exec(`
INSERT INTO driver_verifications (id, user_id, full_name, phone, city, vehicle_model, vehicle_plate, vehicle_type, status, submitted_at, updated_at)
VALUES ($1, $2, 'Driver', '79990000000', 'Moscow', 'GAZ', 'A000AA77', 'winch', $3, NOW(), NOW())`,
		verID, userID, status)
	if err != nil {
		t.Fatalf("insert verification %s: %v", verID, err)
	}
}

func verificationStatus(t *testing.T, db *sql.DB, verID string) string {
	t.Helper()
	var status string
	if err := db.QueryRow(`SELECT status FROM driver_verifications WHERE id = $1`, verID).Scan(&status); err != nil {
		t.Fatalf("query status for %s: %v", verID, err)
	}
	return status
}

func moderationDecision(verID, status string, vehicle *admindomain.DriverVerificationDecision) admindomain.DriverVerificationDecision {
	d := admindomain.DriverVerificationDecision{
		ID:          verID,
		Status:      status,
		Reason:      "admin decision " + status,
		ModeratorID: "admin-1",
		AuditID:     "audit-" + verID + "-" + status + "-" + time.Now().Format("150405.000000000"),
		Now:         time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC),
	}
	if vehicle != nil {
		d.VehiclePlate = vehicle.VehiclePlate
		d.VehicleModel = vehicle.VehicleModel
		d.VehicleType = vehicle.VehicleType
	}
	return d
}

// TestModerationApprove_RequiresVehicleData covers БАГ #1 through the shared
// decision path (the same one BatchApproveVerifications loops over): an
// approval without valid admin-entered vehicle data must be rejected and must
// not touch the verification record.
func TestModerationApprove_RequiresVehicleData(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	repo := postgres.NewAdminRepository(db)

	t.Run("empty plate rejected, record stays pending", func(t *testing.T) {
		seedVerification(t, db, "ver-no-plate", "user-no-plate", "pending")
		err := repo.DecideDriverVerification(ctx, moderationDecision("ver-no-plate", "approved", &admindomain.DriverVerificationDecision{VehicleModel: "GAZ", VehicleType: "winch"}))
		if !errors.Is(err, admindomain.ErrVehicleDataRequired) {
			t.Fatalf("err = %v, want ErrVehicleDataRequired", err)
		}
		if got := verificationStatus(t, db, "ver-no-plate"); got != "pending" {
			t.Fatalf("status = %q, want pending (record must not be approved)", got)
		}
	})

	t.Run("empty model rejected", func(t *testing.T) {
		seedVerification(t, db, "ver-no-model", "user-no-model", "pending")
		err := repo.DecideDriverVerification(ctx, moderationDecision("ver-no-model", "approved", &admindomain.DriverVerificationDecision{VehiclePlate: "A111AA77", VehicleType: "winch"}))
		if !errors.Is(err, admindomain.ErrVehicleDataRequired) {
			t.Fatalf("err = %v, want ErrVehicleDataRequired", err)
		}
	})

	t.Run("empty vehicle type rejected", func(t *testing.T) {
		seedVerification(t, db, "ver-no-type", "user-no-type", "pending")
		err := repo.DecideDriverVerification(ctx, moderationDecision("ver-no-type", "approved", &admindomain.DriverVerificationDecision{VehiclePlate: "A111AA77", VehicleModel: "GAZ"}))
		if !errors.Is(err, admindomain.ErrVehicleDataRequired) {
			t.Fatalf("err = %v, want ErrVehicleDataRequired", err)
		}
	})

	t.Run("invalid vehicle type rejected", func(t *testing.T) {
		seedVerification(t, db, "ver-bad-type", "user-bad-type", "pending")
		err := repo.DecideDriverVerification(ctx, moderationDecision("ver-bad-type", "approved", &admindomain.DriverVerificationDecision{VehiclePlate: "A111AA77", VehicleModel: "GAZ", VehicleType: "tank"}))
		if !errors.Is(err, admindomain.ErrVehicleTypeNotAllowed) {
			t.Fatalf("err = %v, want ErrVehicleTypeNotAllowed", err)
		}
		if got := verificationStatus(t, db, "ver-bad-type"); got != "pending" {
			t.Fatalf("status = %q, want pending (record must not be approved)", got)
		}
	})
}

// TestModerationApprove_HappyPath proves a valid approval from an allowed
// status still works exactly as before and overwrites the vehicle columns.
func TestModerationApprove_HappyPath(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	repo := postgres.NewAdminRepository(db)

	t.Run("approve from pending", func(t *testing.T) {
		seedVerification(t, db, "ver-ok", "user-ok", "pending")
		err := repo.DecideDriverVerification(ctx, moderationDecision("ver-ok", "approved", &admindomain.DriverVerificationDecision{VehiclePlate: "B222BB77", VehicleModel: "Kamaz", VehicleType: "platform"}))
		if err != nil {
			t.Fatalf("DecideDriverVerification failed: %v", err)
		}
		if got := verificationStatus(t, db, "ver-ok"); got != "approved" {
			t.Fatalf("status = %q, want approved", got)
		}
		var plate, model, vtype string
		if err := db.QueryRow(`SELECT vehicle_plate, vehicle_model, vehicle_type FROM driver_verifications WHERE id = $1`, "ver-ok").Scan(&plate, &model, &vtype); err != nil {
			t.Fatalf("query vehicle data: %v", err)
		}
		if plate != "B222BB77" || model != "Kamaz" || vtype != "platform" {
			t.Fatalf("vehicle data = (%q,%q,%q), want (B222BB77,Kamaz,platform)", plate, model, vtype)
		}
	})

	t.Run("approve from changes_requested", func(t *testing.T) {
		seedVerification(t, db, "ver-cr", "user-cr", "changes_requested")
		err := repo.DecideDriverVerification(ctx, moderationDecision("ver-cr", "approved", &admindomain.DriverVerificationDecision{VehiclePlate: "C333CC77", VehicleModel: "GAZ", VehicleType: "winch"}))
		if err != nil {
			t.Fatalf("DecideDriverVerification failed: %v", err)
		}
		if got := verificationStatus(t, db, "ver-cr"); got != "approved" {
			t.Fatalf("status = %q, want approved", got)
		}
	})
}

// TestModerationApprove_InvalidCurrentStatus covers БАГ #3: approving a
// verification that is not in an open round (already approved / rejected /
// blocked) must fail loudly and must not change the record.
func TestModerationApprove_InvalidCurrentStatus(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	repo := postgres.NewAdminRepository(db)
	vehicle := &admindomain.DriverVerificationDecision{VehiclePlate: "D444DD77", VehicleModel: "GAZ", VehicleType: "winch"}

	tests := []struct {
		name       string
		seedStatus string
	}{
		{name: "re-approve already approved", seedStatus: "approved"},
		{name: "approve rejected", seedStatus: "rejected"},
		{name: "approve blocked", seedStatus: "blocked"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			verID := "ver-invalid-" + tc.seedStatus
			seedVerification(t, db, verID, "user-invalid-"+tc.seedStatus, tc.seedStatus)
			err := repo.DecideDriverVerification(ctx, moderationDecision(verID, "approved", vehicle))
			if !errors.Is(err, admindomain.ErrInvalidDecisionStatus) {
				t.Fatalf("err = %v, want ErrInvalidDecisionStatus", err)
			}
			if got := verificationStatus(t, db, verID); got != tc.seedStatus {
				t.Fatalf("status = %q, want %q (record must not change)", got, tc.seedStatus)
			}
		})
	}
}

// TestModerationApprove_MissingVerification preserves the existing 404
// behaviour (sql.ErrNoRows) when the verification does not exist.
func TestModerationApprove_MissingVerification(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	repo := postgres.NewAdminRepository(db)

	err := repo.DecideDriverVerification(ctx, moderationDecision("does-not-exist", "approved", &admindomain.DriverVerificationDecision{VehiclePlate: "A111AA77", VehicleModel: "GAZ", VehicleType: "winch"}))
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("err = %v, want sql.ErrNoRows", err)
	}
}

// TestModerationReject_NoVehicleData proves non-approval decisions keep their
// existing behaviour: they never require vehicle data.
func TestModerationReject_NoVehicleData(t *testing.T) {
	db, cleanup := setupTestDB(t)
	defer cleanup()
	defer truncateAll(t, db)

	ctx := context.Background()
	repo := postgres.NewAdminRepository(db)

	seedVerification(t, db, "ver-reject", "user-reject", "pending")
	if err := repo.DecideDriverVerification(ctx, moderationDecision("ver-reject", "rejected", nil)); err != nil {
		t.Fatalf("DecideDriverVerification failed: %v", err)
	}
	if got := verificationStatus(t, db, "ver-reject"); got != "rejected" {
		t.Fatalf("status = %q, want rejected", got)
	}
}
