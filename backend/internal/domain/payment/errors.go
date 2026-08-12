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
	ErrBelowMinimum          = errors.New("payout amount is below the minimum withdrawal threshold")
	ErrPayoutNotFound        = errors.New("payout not found")
	ErrPayoutNotApprovable   = errors.New("payout cannot be approved in its current status")
	ErrPayoutNotRejectable   = errors.New("payout cannot be rejected in its current status")
)
