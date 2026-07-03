package driver

import "time"

type Status string

const (
	StatusOffline Status = "offline"
	StatusOnline  Status = "online"
	StatusBusy    Status = "busy"
)

type Driver struct {
	ID             string
	UserID         string
	Status         Status
	CurrentOrderID *string
	LastSeenAt     time.Time
	UpdatedAt      time.Time
}

// DriverProfile contains complete driver information for profile display
type DriverProfile struct {
	// Basic driver info
	ID             string
	UserID         string
	Status         Status
	CurrentOrderID *string
	LastSeenAt     time.Time
	UpdatedAt      time.Time

	// User identity
	FullName string
	Phone    string

	// Vehicle information (from verification)
	VehiclePlate string
	VehicleModel string
	VehicleType  string

	// Rating and statistics
	RatingAverage float64
	RatingCount   int
	TotalOrders   int

	// Avatar (selfie document URL)
	AvatarURL *string
}

func (d Driver) IsAvailable() bool {
	return d.Status == StatusOnline && d.CurrentOrderID == nil
}

func IsValidStatus(status Status) bool {
	switch status {
	case StatusOffline, StatusOnline, StatusBusy:
		return true
	default:
		return false
	}
}
