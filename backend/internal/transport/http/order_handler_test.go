package http

import (
	"context"
	"testing"

	"evik/backend/internal/auth"
	orderdomain "evik/backend/internal/domain/order"
)

func TestOrderAccessAllowsOnlyOwnerAssignedDriverOrAdmin(t *testing.T) {
	driverID := "driver-1"
	ord := &orderdomain.Order{
		ID:       "order-1",
		UserID:   "client-1",
		DriverID: &driverID,
		Status:   orderdomain.StatusAccepted,
	}
	handler := &OrderHandler{}

	cases := []struct {
		name string
		ctx  context.Context
		want bool
	}{
		{
			name: "client owner",
			ctx:  withAuth(context.Background(), "client-1", auth.RoleClient),
			want: true,
		},
		{
			name: "other client denied",
			ctx:  withAuth(context.Background(), "client-2", auth.RoleClient),
			want: false,
		},
		{
			name: "assigned driver",
			ctx:  withAuth(context.Background(), "driver-1", auth.RoleDriver),
			want: true,
		},
		{
			name: "other driver denied",
			ctx:  withAuth(context.Background(), "driver-2", auth.RoleDriver),
			want: false,
		},
		{
			name: "admin",
			ctx:  withAuth(context.Background(), "admin", auth.RoleAdmin),
			want: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := handler.canAccessOrder(tc.ctx, ord, false); got != tc.want {
				t.Fatalf("canAccessOrder = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestOrderAccessAllowsDriverToInspectSearchingOrderWhenExplicitlyAllowed(t *testing.T) {
	ord := &orderdomain.Order{ID: "order-1", UserID: "client-1", Status: orderdomain.StatusSearching}
	handler := &OrderHandler{}
	ctx := withAuth(context.Background(), "driver-1", auth.RoleDriver)

	if !handler.canAccessOrder(ctx, ord, true) {
		t.Fatal("expected driver to inspect searching order")
	}
	if handler.canAccessOrder(ctx, ord, false) {
		t.Fatal("expected driver to be denied searching order when not explicitly allowed")
	}
}
