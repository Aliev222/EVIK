package admin

import "time"

type Overview struct {
	TotalUsers         int64
	Clients            int64
	Drivers            int64
	OnlineDrivers      int64
	PendingModerations int64
	AverageDriverStars float64
	ReviewsToday       int64
	ActiveOrders       int64
}

type DriverVerification struct {
	ID             string
	UserID         string
	DriverName     string
	Phone          string
	City           string
	Vehicle        string
	Plate          string
	VehicleType    string
	Status         string
	Risk           string
	Stars          float64
	Orders         int64
	SubmittedAt    time.Time
	Documents      []string
	Signals        []string
	DecisionReason *string
}

type User struct {
	ID     string
	Name   string
	Role   string
	Phone  string
	Orders int64
	Status string
}

type Review struct {
	ID         string
	OrderID    string
	DriverID   string
	DriverName string
	ClientID   string
	ClientName string
	Stars      int
	Text       string
	CreatedAt  time.Time
}
