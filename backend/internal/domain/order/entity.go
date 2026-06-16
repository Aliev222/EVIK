package order

import "time"

const StateNoDriverFound State = "no_driver_found"

type Coordinate struct {
	Lat float64
	Lng float64
}

type TowTruckType string

const (
	TowTruckWinch       TowTruckType = "winch"
	TowTruckPlatform    TowTruckType = "platform"
	TowTruckManipulator TowTruckType = "manipulator"
)

func (t TowTruckType) IsValid() bool {
	switch t {
	case TowTruckWinch, TowTruckPlatform, TowTruckManipulator:
		return true
	default:
		return false
	}
}

type Order struct {
	ID             string
	UserID         string
	DriverID       *string
	Pickup         Coordinate
	PickupAddress  string
	Dropoff        Coordinate
	DropoffAddress string
	TowTruckType   TowTruckType
	Status         Status
	CreatedAt      time.Time
	UpdatedAt      time.Time
	CancelledAt    *time.Time
}

func NewOrder(id, userID string, pickup, dropoff Coordinate, towTruckType TowTruckType, now time.Time) (*Order, error) {
	if userID == "" {
		return nil, WrapValidation(errUserIDRequired{})
	}
	if !isValidCoordinate(pickup) || !isValidCoordinate(dropoff) {
		return nil, WrapValidation(errInvalidCoordinate{})
	}
	if !towTruckType.IsValid() {
		return nil, WrapValidation(errInvalidTowTruckType{})
	}

	return &Order{
		ID:           id,
		UserID:       userID,
		Pickup:       pickup,
		Dropoff:      dropoff,
		TowTruckType: towTruckType,
		Status:       StatusCreated,
		CreatedAt:    now,
		UpdatedAt:    now,
	}, nil
}

func (o *Order) TransitionTo(next Status, now time.Time) error {
	machine := NewStateMachine(State(o.Status))
	if err := machine.Transition(State(next)); err != nil {
		return err
	}
	o.Status = Status(machine.Current())
	o.UpdatedAt = now
	if next == StatusCancelled {
		o.CancelledAt = &now
	}
	return nil
}

func (o *Order) AssignDriver(driverID string, now time.Time) error {
	if driverID == "" {
		return WrapValidation(errDriverIDRequired{})
	}
	o.DriverID = &driverID
	o.UpdatedAt = now
	return nil
}

type errUserIDRequired struct{}

func (errUserIDRequired) Error() string { return "user id is required" }

type errDriverIDRequired struct{}

func (errDriverIDRequired) Error() string { return "driver id is required" }

type errInvalidCoordinate struct{}

func (errInvalidCoordinate) Error() string { return "invalid coordinate" }

type errInvalidTowTruckType struct{}

func (errInvalidTowTruckType) Error() string { return "invalid tow truck type" }

func isValidCoordinate(c Coordinate) bool {
	return c.Lat >= -90 && c.Lat <= 90 && c.Lng >= -180 && c.Lng <= 180
}
