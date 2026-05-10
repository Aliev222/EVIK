package payment

import "errors"

var (
	ErrPaymentMethodNotFound = errors.New("payment method not found")
	ErrValidationFailed      = errors.New("payment validation failed")
	ErrInvalidPromocode      = errors.New("invalid promocode")
	ErrPaymentNotFound       = errors.New("payment not found")
	ErrWalletNotFound        = errors.New("driver wallet not found")
	ErrPayoutMethodNotFound  = errors.New("payout method not found")
	ErrInsufficientFunds     = errors.New("insufficient available balance")
	ErrDuplicateOperation    = errors.New("duplicate operation")
	ErrInvalidAmount         = errors.New("invalid amount")
)
