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
