package http

import (
	"context"
	"errors"

	"evik/backend/internal/auth"
)

type authContextKey string

const (
	authUserIDKey authContextKey = "auth_user_id"
	authRoleKey   authContextKey = "auth_role"
)

var ErrUnauthorized = errors.New("unauthorized")

func withAuth(ctx context.Context, userID string, role auth.Role) context.Context {
	ctx = context.WithValue(ctx, authUserIDKey, userID)
	return context.WithValue(ctx, authRoleKey, role)
}

func userIDFromContext(ctx context.Context) (string, error) {
	raw := ctx.Value(authUserIDKey)
	userID, ok := raw.(string)
	if !ok || userID == "" {
		return "", ErrUnauthorized
	}
	return userID, nil
}

func roleFromContext(ctx context.Context) (auth.Role, error) {
	raw := ctx.Value(authRoleKey)
	role, ok := raw.(auth.Role)
	if !ok || role == "" {
		return "", ErrUnauthorized
	}
	return role, nil
}
