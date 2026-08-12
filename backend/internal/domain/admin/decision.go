package admin

import (
	"strings"

	orderdomain "evik/backend/internal/domain/order"
)

// Verification statuses. Mirrors the driver_verifications.status column.
const (
	VerificationStatusPending          = "pending"
	VerificationStatusApproved         = "approved"
	VerificationStatusRejected         = "rejected"
	VerificationStatusBlocked          = "blocked"
	VerificationStatusChangesRequested = "changes_requested"
)

// ApprovableVerificationStatuses lists the statuses from which an approval
// decision is meaningful: the driver has an open verification round that the
// admin can approve. Approving an already approved / rejected / blocked record
// would silently overwrite a terminal state, so it is rejected loudly instead.
//
// Chosen conservatively on purpose: a blocked driver cannot be silently
// re-approved through the moderation endpoints; any product decision to allow
// that must be explicit (e.g. a dedicated "unblock + re-approve" flow).
var ApprovableVerificationStatuses = map[string]struct{}{
	VerificationStatusPending:          {},
	VerificationStatusChangesRequested: {},
}

// ApprovalAllowedFrom reports whether an approval decision is legal for a
// verification currently in the given status.
func ApprovalAllowedFrom(currentStatus string) bool {
	_, ok := ApprovableVerificationStatuses[currentStatus]
	return ok
}

// Validate enforces the rules that hold for a driver verification decision
// regardless of which endpoint issued it:
//
//   - approving requires the admin-entered vehicle data (plate/model/type) and
//     a tow truck type the platform supports; the values are authoritative and
//     overwrite whatever the driver originally submitted;
//   - every other status transition (rejected / changes_requested / blocked)
//     needs no vehicle data.
//
// The current-status transition guard lives in the repository layer where the
// persisted status is available (see AdminRepository.DecideDriverVerification).
func (d DriverVerificationDecision) Validate() error {
	if d.Status != VerificationStatusApproved {
		return nil
	}
	plate := strings.TrimSpace(d.VehiclePlate)
	model := strings.TrimSpace(d.VehicleModel)
	vehicleType := strings.TrimSpace(d.VehicleType)
	if plate == "" || model == "" || vehicleType == "" {
		return ErrVehicleDataRequired
	}
	if !orderdomain.TowTruckType(vehicleType).IsValid() {
		return ErrVehicleTypeNotAllowed
	}
	return nil
}
