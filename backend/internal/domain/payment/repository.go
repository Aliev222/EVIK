package payment

import (
	"context"
	"time"
)

// AdminRefundFilter captures GET /admin/finance/refunds filters.
// Empty fields mean no filter on that column.
type AdminRefundFilter struct {
	Status    string
	PaymentID string
	OrderID   string
	From      *time.Time
	To        *time.Time
	Limit     int
	Offset    int
}

type Repository interface {
	ListMethods(ctx context.Context, userID string) ([]PaymentMethod, error)
	AddMethod(ctx context.Context, method PaymentMethod) error
	CreatePendingPaymentMethod(ctx context.Context, payment *Payment, method PaymentMethod) (*AddCardInit, error)
	SetDefaultMethod(ctx context.Context, userID string, methodID string) (*PaymentMethod, error)
	DeleteMethod(ctx context.Context, userID string, methodID string) error
	ListTransactions(ctx context.Context, userID string, limit int) ([]PaymentTransaction, error)
	ListClientPayments(ctx context.Context, userID string, limit int, offset int) ([]PaymentTransaction, error)
	CreateTransaction(ctx context.Context, transaction *PaymentTransaction) error
	CreateOrderPayment(ctx context.Context, payment *Payment) (*Payment, error)
	CreateSubscriptionPayment(ctx context.Context, payment *Payment, subscription *Subscription) (*Payment, error)
	GetPayment(ctx context.Context, paymentID string) (*Payment, error)
	GetPaymentByOrderID(ctx context.Context, orderID string) (*Payment, error)
	UpdatePaymentFromProvider(ctx context.Context, providerPaymentID, status string, paid bool) (*Payment, error)
	StoreWebhook(ctx context.Context, eventID, provider, eventType string, payload []byte) (bool, error)
	MarkWebhookProcessed(ctx context.Context, eventID string) error
	CompleteOrderFinancially(ctx context.Context, orderID, idempotencyKey string, holdSeconds int) error
	ListReleasablePendingTransactions(ctx context.Context, limit int) ([]WalletTransaction, error)
	MarkTransactionReleased(ctx context.Context, txID string) error
	GetDriverWallet(ctx context.Context, driverID string) (*DriverWallet, error)
	ListWalletTransactions(ctx context.Context, driverID string, limit int) ([]WalletTransaction, error)
	ListPayouts(ctx context.Context, driverID string, limit int) ([]Payout, error)
	ListPayoutMethods(ctx context.Context, driverID string) ([]DriverPayoutMethod, error)
	AddPayoutMethod(ctx context.Context, method DriverPayoutMethod) error
	CreatePayout(ctx context.Context, payout *Payout, idempotencyKey string) (*Payout, error)
	MarkPayoutPaid(ctx context.Context, payoutID, providerPayoutID, idempotencyKey string) error
	MarkPayoutFailed(ctx context.Context, payoutID, reason string) error
	GetActiveDriverSubscription(ctx context.Context, driverID string) (*Subscription, error)
	GetLatestDriverSubscription(ctx context.Context, driverID string) (*Subscription, error)
	ActivateSubscriptionByPayment(ctx context.Context, paymentID string) error
	ActivatePaymentMethodFromProvider(ctx context.Context, providerPaymentID, providerPaymentMethodID, brand, last4 string, expMonth, expYear int, holder string) error
	CreateRefund(ctx context.Context, refund *Refund) (*Refund, error)
	ExportFinanceReport(ctx context.Context, reportType string) ([][]string, error)

	// Phase 1 admin endpoints.
	GetPayout(ctx context.Context, payoutID string) (*Payout, error)
	ApprovePayout(ctx context.Context, payoutID, moderatorID, providerPayoutID string, now time.Time) (*Payout, error)
	RejectPayout(ctx context.Context, payoutID, moderatorID, reason string, now time.Time) (*Payout, error)
	ListAdminRefunds(ctx context.Context, filter AdminRefundFilter) ([]Refund, int64, error)
	ListWalletTransactionsByOrder(ctx context.Context, orderID string) ([]WalletTransaction, error)
}
