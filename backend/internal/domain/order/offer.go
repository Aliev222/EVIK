package order

import "time"

type Offer struct {
	ID         string
	OrderID    string
	DriverID   string
	Round      int
	DistanceKM *float64
	OfferedAt  time.Time
	ExpiresAt  time.Time
	Outcome    *string
	ResolvedAt *time.Time
}
