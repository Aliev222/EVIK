package order

import (
	"errors"
	"fmt"
)

var (
	ErrOrderNotFound     = errors.New("order not found")
	ErrInvalidTransition = errors.New("invalid order status transition")
	ErrValidationFailed  = errors.New("validation failed")
	ErrOrderAlreadyTaken = errors.New("order already taken by another driver")
	// ErrOfferNotActive means the driver attempted to accept an order without
	// a current, active offer. It is an expected racing/expiry outcome, not an
	// internal server failure.
	ErrOfferNotActive      = errors.New("no active offer for driver")
	ErrIdempotencyConflict = errors.New("order with this idempotency key already exists")
	ErrNonPositivePrice    = errors.New("order price must be positive")
)

func WrapValidation(err error) error {
	return fmt.Errorf("%w: %v", ErrValidationFailed, err)
}
