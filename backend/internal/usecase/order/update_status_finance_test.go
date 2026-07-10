package order

import (
	"context"
	"errors"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
)

func TestUpdateStatus_CompletedRejected(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:        "order-1",
			UserID:    "client-1",
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

	_, err := uc.Execute(context.Background(), "order-1", orderdomain.StatusCompleted)
	if !errors.Is(err, ErrCompletionRequiresFinalize) {
		t.Fatalf("Execute should return ErrCompletionRequiresFinalize, got: %v", err)
	}
}

func TestUpdateStatus_ArrivedAllowed(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	driverID := "driver-1"
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:        "order-1",
			UserID:    "client-1",
			DriverID:  &driverID,
			Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:    orderdomain.StatusAccepted,
			CreatedAt: now,
			UpdatedAt: now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewUpdateStatusUseCase(orderRepo, driverRepo, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", orderdomain.StatusArrived)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusArrived {
		t.Fatalf("status = %q, want arrived", ord.Status)
	}
}

func TestUpdateStatus_InProgressAllowed(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	driverID := "driver-1"
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:        "order-1",
			UserID:    "client-1",
			DriverID:  &driverID,
			Pickup:    orderdomain.Coordinate{Lat: 55.75, Lng: 37.62},
			Dropoff:   orderdomain.Coordinate{Lat: 55.76, Lng: 37.63},
			Status:    orderdomain.StatusArrived,
			CreatedAt: now,
			UpdatedAt: now,
		},
	}
	driverRepo := &fakeDriverOrderRepository{}
	publisher := &fakeEventPublisher{}
	uc := NewUpdateStatusUseCase(orderRepo, driverRepo, publisher, nil, fakeClock{now: now}, fakeLogger{})

	ord, err := uc.Execute(context.Background(), "order-1", orderdomain.StatusInProgress)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if ord.Status != orderdomain.StatusInProgress {
		t.Fatalf("status = %q, want in_progress", ord.Status)
	}
}

func TestUpdateStatus_CompletedRejectedEvenFromInProgress(t *testing.T) {
	now := time.Date(2026, 5, 10, 12, 0, 0, 0, time.UTC)
	orderRepo := &fakeOrderRepository{
		order: &orderdomain.Order{
			ID:        "order-1",
			UserID:    "client-1",
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
	if !errors.Is(err, ErrCompletionRequiresFinalize) {
		t.Fatalf("Execute should return ErrCompletionRequiresFinalize, got: %v", err)
	}
}
