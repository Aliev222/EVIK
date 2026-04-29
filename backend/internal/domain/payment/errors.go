package payment

import "errors"

var (
	ErrPaymentMethodNotFound = errors.New("payment method not found")
	ErrValidationFailed      = errors.New("payment validation failed")
	ErrInvalidPromocode      = errors.New("invalid promocode")
)
