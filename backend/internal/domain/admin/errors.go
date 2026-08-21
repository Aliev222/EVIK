package admin

import "errors"

// Decision validation errors. They are raised by the shared moderation
// decision path (DecideDriverVerification) — never by individual handlers —
// so both the single and the batch moderation flows enforce the same rules
// and a rebuilt admin UI cannot bypass them.
var (
	// ErrInvalidDecisionStatus: the verification's current status does not
	// permit the requested decision. E.g. re-approving a verification that is
	// already approved / rejected / blocked.
	ErrInvalidDecisionStatus = errors.New("verification status does not allow this decision")

	// ErrVehicleDataRequired: an approval decision must carry the
	// admin-entered vehicle data (plate, model, type).
	ErrVehicleDataRequired = errors.New("vehicle_plate, vehicle_model and vehicle_type are required when approving")

	// ErrVehicleTypeNotAllowed: vehicle_type is not a tow truck type the
	// platform supports for matching and pricing.
	ErrVehicleTypeNotAllowed = errors.New("vehicle_type must be one of winch, platform, manipulator")

	// ErrDriverVerificationBlocked: a driver whose verification is in the
	// 'blocked' state tries to resubmit documents. The block is sticky — it
	// can only be lifted through an explicit admin decision, never by a
	// driver resubmitting the verification form.
	ErrDriverVerificationBlocked = errors.New("driver verification is blocked")

	// ErrTaxProfileNotFound: an admin tax-profile status update targeted a
	// driver that has no tax profile row.
	ErrTaxProfileNotFound = errors.New("tax profile not found")
)
