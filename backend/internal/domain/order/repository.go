package order

import (
	"context"
	"time"
)

type Repository interface {
	Create(ctx context.Context, order *Order) error
	Update(ctx context.Context, order *Order) error
	UpdateStatus(ctx context.Context, id string, status Status, updatedAt time.Time) error
	GetByID(ctx context.Context, id string) (*Order, error)
	GetByOrderKey(ctx context.Context, idempotencyKey string) (*Order, error)
	// AcceptOrder atomatically sets driver_id and status='accepted' only when the
	// order is in 'searching' state with no driver assigned yet. Returns
	// ErrOrderAlreadyTaken when another driver won the race.
	AcceptOrder(ctx context.Context, orderID, driverID string) (*Order, error)
	// CancelOrder atomically transitions a live order to 'cancelled' with a
	// single conditional UPDATE...RETURNING. Only orders NOT yet in
	// 'completed'/'cancelled' match; the RETURNING projection carries the
	// CURRENT driver_id captured at statement time (so a concurrent accept can
	// never be lost — see BUG-CANCEL-RACE-DRIVER). Returns ErrOrderNotFound
	// when no live row matched.
	CancelOrder(ctx context.Context, orderID string, reason string, now time.Time) (*Order, error)
	ListByStatus(ctx context.Context, status Status, limit int) ([]*Order, error)
	ListAdminOrders(ctx context.Context, filter AdminOrderFilter) ([]AdminOrderListItem, int64, error)
	GetAdminOrderDetails(ctx context.Context, orderID string) (*AdminOrderDetails, error)
}

// AdminOrderFilter captures all supported filters of GET /admin/orders.
// Empty fields mean "do not filter on this column". From/To filter by
// orders.created_at. Limit defaults to 50, capped at 200. Offset defaults to 0.
type AdminOrderFilter struct {
	Status          string
	PaymentMethod   string
	FinancialStatus string
	DriverID        string
	ClientID        string
	From            *time.Time
	To              *time.Time
	Limit           int
	Offset          int
}

// AdminOrderListItem is a flat denormalized row for the admin orders table.
// All monetary values are in kopecks (minor units).
type AdminOrderListItem struct {
	OrderID          string
	ClientID         string
	ClientName       string
	ClientPhone      string
	DriverID         string
	DriverName       string
	DriverPhone      string
	Status           string
	PaymentMethod    string
	PaymentStatus    string
	FinancialStatus  string
	PriceTotal       int64
	CommissionAmount int64
	DriverAmount     int64
	CreatedAt        time.Time
	CompletedAt      *time.Time
	CancelledAt      *time.Time
}

// AdminOrderDetails contains the full payload of GET /admin/orders/{id}.
// Wallet / payment / payout links live in their own structs to keep the
// admin handler concise. Amounts in kopecks.
type AdminOrderDetails struct {
	Order              AdminOrderListItem
	Pickup             Coordinate
	Dropoff            Coordinate
	TowTruckType       string
	Timeline           []AdminOrderTimelineEvent
	Payment            *AdminOrderPaymentLink
	WalletTransactions []AdminOrderWalletTxLink
	Payouts            []AdminOrderPayoutLink
	Refunds            []AdminOrderRefundLink
	FinancialBreakdown AdminOrderFinancialBreakdown
}

type AdminOrderTimelineEvent struct {
	At     time.Time
	Status string
}

type AdminOrderPaymentLink struct {
	ID                string
	Provider          string
	ProviderPaymentID string
	PaymentMethod     string
	Amount            int64
	Status            string
	PaidAt            *time.Time
	CreatedAt         time.Time
}

type AdminOrderWalletTxLink struct {
	ID          string
	DriverID    string
	Type        string
	Direction   string
	Amount      int64
	Status      string
	Description string
	CreatedAt   time.Time
}

type AdminOrderPayoutLink struct {
	ID        string
	DriverID  string
	Amount    int64
	Status    string
	CreatedAt time.Time
}

type AdminOrderRefundLink struct {
	ID        string
	PaymentID string
	Amount    int64
	Status    string
	Reason    string
	CreatedAt time.Time
}

type AdminOrderFinancialBreakdown struct {
	TotalAmount        int64
	CommissionAmount   int64
	DriverAmount       int64
	CashCommissionHold int64
	PlatformNetAmount  int64
}
