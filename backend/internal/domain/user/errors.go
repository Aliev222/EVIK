package user

import "errors"

var (
	ErrUserNotFound       = errors.New("user not found")
	ErrUserAlreadyExists  = errors.New("user already exists")
	ErrSessionNotFound    = errors.New("refresh session not found")
	ErrOTPNotFound        = errors.New("otp code not found")
	ErrTaxProfileNotFound = errors.New("tax profile not found")
	ErrNPDProviderNotConfigured = errors.New("npd partner integration is not configured yet")
)
