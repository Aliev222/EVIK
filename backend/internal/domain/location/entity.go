package location

import "time"

type Location struct {
	Lat       float64
	Lng       float64
	UpdatedAt time.Time
}

type DriverLocation struct {
	DriverID   string
	Location   Location
	DistanceKM float64
}
