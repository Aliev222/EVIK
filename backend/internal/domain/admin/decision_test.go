package admin_test

import (
	"errors"
	"testing"
	"time"

	admindomain "evik/backend/internal/domain/admin"
)

func TestDriverVerificationDecisionValidate(t *testing.T) {
	base := func() admindomain.DriverVerificationDecision {
		return admindomain.DriverVerificationDecision{
			ID:           "ver-1",
			Status:       admindomain.VerificationStatusApproved,
			Reason:       "approved by admin",
			ModeratorID:  "admin-1",
			AuditID:      "audit-1",
			Now:          time.Now(),
			VehiclePlate: "A123AA77",
			VehicleModel: "GAZ Sable",
			VehicleType:  "winch",
		}
	}

	t.Run("approved with valid vehicle data", func(t *testing.T) {
		if err := base().Validate(); err != nil {
			t.Fatalf("Validate() = %v, want nil", err)
		}
	})

	for _, tc := range []struct {
		name string
		mut  func(*admindomain.DriverVerificationDecision)
		want error
	}{
		{name: "empty plate", mut: func(d *admindomain.DriverVerificationDecision) { d.VehiclePlate = "" }, want: admindomain.ErrVehicleDataRequired},
		{name: "empty model", mut: func(d *admindomain.DriverVerificationDecision) { d.VehicleModel = "" }, want: admindomain.ErrVehicleDataRequired},
		{name: "empty vehicle type", mut: func(d *admindomain.DriverVerificationDecision) { d.VehicleType = "" }, want: admindomain.ErrVehicleDataRequired},
		{name: "whitespace-only plate", mut: func(d *admindomain.DriverVerificationDecision) { d.VehiclePlate = "   " }, want: admindomain.ErrVehicleDataRequired},
		{name: "whitespace-only type", mut: func(d *admindomain.DriverVerificationDecision) { d.VehicleType = "\t" }, want: admindomain.ErrVehicleDataRequired},
		{name: "vehicle type not in allowlist", mut: func(d *admindomain.DriverVerificationDecision) { d.VehicleType = "helicopter" }, want: admindomain.ErrVehicleTypeNotAllowed},
		{name: "vehicle type case-sensitive", mut: func(d *admindomain.DriverVerificationDecision) { d.VehicleType = "Winch" }, want: admindomain.ErrVehicleTypeNotAllowed},
		{name: "vehicle type surrounded by spaces", mut: func(d *admindomain.DriverVerificationDecision) { d.VehicleType = " platform " }, want: nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := base()
			tc.mut(&d)
			err := d.Validate()
			if tc.want == nil {
				if err != nil {
					t.Fatalf("Validate() = %v, want nil", err)
				}
				return
			}
			if !errors.Is(err, tc.want) {
				t.Fatalf("Validate() = %v, want %v", err, tc.want)
			}
		})
	}

	t.Run("non-approval decisions never require vehicle data", func(t *testing.T) {
		for _, status := range []string{
			admindomain.VerificationStatusRejected,
			admindomain.VerificationStatusChangesRequested,
			admindomain.VerificationStatusBlocked,
		} {
			d := base()
			d.Status = status
			d.VehiclePlate = ""
			d.VehicleModel = ""
			d.VehicleType = ""
			if err := d.Validate(); err != nil {
				t.Fatalf("status %q Validate() = %v, want nil", status, err)
			}
		}
	})
}

func TestApprovalAllowedFrom(t *testing.T) {
	for _, status := range []string{
		admindomain.VerificationStatusPending,
		admindomain.VerificationStatusChangesRequested,
	} {
		if !admindomain.ApprovalAllowedFrom(status) {
			t.Fatalf("ApprovalAllowedFrom(%q) = false, want true", status)
		}
	}

	for _, status := range []string{
		admindomain.VerificationStatusApproved,
		admindomain.VerificationStatusRejected,
		admindomain.VerificationStatusBlocked,
		"",
		"unknown",
	} {
		if admindomain.ApprovalAllowedFrom(status) {
			t.Fatalf("ApprovalAllowedFrom(%q) = true, want false", status)
		}
	}
}
