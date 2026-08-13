package account

import (
	"context"
	"errors"
	"time"

	"evik/backend/internal/auth"
)

var (
	// ErrActiveOrder is returned when the account has an in-flight order
	// (as client or as driver). Deleting mid-order would corrupt the order
	// lifecycle involved, so it is refused.
	ErrActiveOrder = errors.New("account has an active order")
	// ErrOutstandingDriverBalance is returned when a driver still has money
	// on the wallet (available/pending/debt). The withdrawal must be settled
	// before the account can be deleted.
	ErrOutstandingDriverBalance = errors.New("driver has an outstanding balance")
	// ErrAccountNotFound is returned when the authenticated user row is gone.
	ErrAccountNotFound = errors.New("account not found")
)

// AccountRepository performs the deletion atomically. Guard checks (active
// order, outstanding balance) run inside the same transaction so a partial or
// racy deletion is impossible.
type AccountRepository interface {
	// Delete anonymizes the user, revokes all sessions/tokens and strips
	// driver PII, while retaining financial/order records for tax/legal
	// retention. Returns ErrActiveOrder / ErrOutstandingDriverBalance when a
	// guard fails; the transaction is rolled back in that case.
	Delete(ctx context.Context, userID string, role auth.Role, now time.Time) error
}

type UseCase struct {
	repo AccountRepository
}

func NewUseCase(repo AccountRepository) *UseCase {
	return &UseCase{repo: repo}
}

// Execute deletes the caller's own account. role is taken from the JWT, so a
// user can only ever delete their own account.
func (uc *UseCase) Execute(ctx context.Context, userID string, role auth.Role) error {
	if userID == "" {
		return errors.New("user id is required")
	}
	if role != auth.RoleClient && role != auth.RoleDriver {
		return errors.New("account deletion is only available for client and driver accounts")
	}
	return uc.repo.Delete(ctx, userID, role, time.Now().UTC())
}