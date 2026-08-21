package admin

import "time"

type Overview struct {
	TotalUsers         int64
	Clients            int64
	NewClientsToday    int64
	OnlineClients      int64
	Drivers            int64
	OnlineDrivers      int64
	PendingModerations int64
	AverageDriverStars float64
	ReviewsToday       int64
	ActiveOrders       int64

	// Phase 1 KPI extension. All amounts are in kopecks (minor units).
	GMVToday                  int64
	GMVMonth                  int64
	CommissionToday           int64
	CommissionMonth           int64
	PayoutsToday              int64
	PayoutsMonth              int64
	PayoutsPending            int64
	FailedPayments            int64
	FailedPayouts             int64
	SubscriptionsRevenueToday int64
	SubscriptionsRevenueMonth int64
	CashDebtTotal             int64
	ActiveDrivers             int64
	PendingVerifications      int64

	// Response time metrics (seconds).
	AvgAcceptanceTimeSec float64
	AvgCompletionTimeSec float64
	OrdersToday          int64

	GMVByDay        []KPIDailyPoint
	CommissionByDay []KPIDailyPoint
}

// KPIDailyPoint is a single calendar-day aggregate value used in dashboard
// charts. Date is formatted as YYYY-MM-DD. Amount is in kopecks (minor units).
type KPIDailyPoint struct {
	Date   string
	Amount int64
}

// DriverVerificationDecision carries the fields the admin enters while
// approving or rejecting a driver verification. VehiclePlate / VehicleModel /
// VehicleType are admin-entered and only applied when Status = "approved";
// they overwrite whatever the driver submitted with the verification request.
// Empty strings mean "leave the existing column untouched".
type DriverVerificationDecision struct {
	ID           string
	Status       string
	Reason       string
	ModeratorID  string
	AuditID      string
	Now          time.Time
	VehiclePlate string
	VehicleModel string
	VehicleType  string
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
	IsHidden   bool
	CreatedAt  time.Time
}
