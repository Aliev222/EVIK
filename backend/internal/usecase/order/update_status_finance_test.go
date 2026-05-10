package order

import (
	"context"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

func TestUpdateStatusCompletedCompletesFinanceWithoutPayoutRequest(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	driverID := "driver-1"
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:        "order-1",
			UserID:    "client-1",
			DriverID:  &driverID,
			Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:    orderdomain.StatusInProgress,
			CreatedAt: now,
			UpdatedAt: now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	finance := &fakeCompletionFinance{}
	uc := NewUpdateStatusUseCase(orderRepo, driverRepo, publisher, finance, fakeClock{now: now})

	ord, err := uc.Execute(context.Background(), "order-1", orderdomain.StatusCompleted)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusCompleted {
		t.Fatalf("status = %q, want completed", ord.Status)
	}
	if finance.completeCalls != 1 || finance.orderID != "order-1" {
		t.Fatalf("finance completion calls = %d order = %q, want one call for order-1", finance.completeCalls, finance.orderID)
	}
	if !driverRepo.released {
		t.Fatal("driver was not released after completed order")
	}
	if len(publisher.events) != 1 || publisher.events[0].Type != orderdomain.EventCompleted {
		t.Fatalf("events = %+v, want one completed event", publisher.events)
	}
}

type fakeCompletionFinance struct {
	completeCalls int
	orderID       string
}

func (f *fakeCompletionFinance) CompleteOrderFinancially(_ context.Context, orderID string) error {
	f.completeCalls++
	f.orderID = orderID
	return nil
}
