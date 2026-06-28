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
)

func WrapValidation(err error) error {
	return fmt.Errorf("%w: %v", ErrValidationFailed, err)
}
