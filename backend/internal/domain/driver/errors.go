package driver

import (
	"errors"
	"fmt"
)

var (
	ErrDriverNotFound    = errors.New("driver not found")
	ErrDriverUnavailable = errors.New("driver unavailable")
	ErrDriverBusy        = errors.New("driver is busy on another order")
	ErrValidationFailed  = errors.New("validation failed")
)

func WrapValidation(err error) error {
	return fmt.Errorf("%w: %v", ErrValidationFailed, err)
}
