package order

import (
	"context"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

func TestUpdateStatusToCompletedReleasesDriver(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	driverID := "driver-1"
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:        "order-1",
			UserID:    "client-1",
			DriverID:  &driverID,
			Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:    orderdomain.StatusAwaitingPayment,
			CreatedAt: now,
			UpdatedAt: now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewUpdateStatusUseCase(orderRepo, driverRepo, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", orderdomain.StatusCompleted)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusCompleted {
		t.Fatalf("status = %q, want completed", ord.Status)
	}
	if !driverRepo.released {
		t.Fatal("driver was not released after completed order")
	}
	if len(publisher.events) != 1 || publisher.events[0].Type != orderdomain.EventCompleted {
		t.Fatalf("events = %+v, want one completed event", publisher.events)
	}
}

func TestUpdateStatusInProgressToCompletedFailsWithoutAwaitingPayment(t *testing.T) {
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
	uc := NewUpdateStatusUseCase(orderRepo, driverRepo, publisher, nil, fakeClock{now: now}, fakeLogger{})

	_, err := uc.Execute(context.Background(), "order-1", orderdomain.StatusCompleted)
	if err == nil {
		t.Fatal("Execute should return error when transitioning in_progress -> completed directly")
	}
}
