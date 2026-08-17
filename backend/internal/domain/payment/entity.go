package payment

import "time"

type CardBrand string

const (
	CardBrandVisa       CardBrand = "visa"
	CardBrandMastercard CardBrand = "mastercard"
	CardBrandMir        CardBrand = "mir"
	CardBrandUnknown    CardBrand = "unknown"
)

type PaymentMethod struct {
	ID                      string
	UserID                  string
	Provider                PaymentProvider
	ProviderPaymentMethodID *string
	ProviderPaymentID       *string
	Brand                   CardBrand
	Last4                   string
	ExpMonth                int
	ExpYear                 int
	Holder                  string
	Status                  string
	IsDefault               bool
	CreatedAt               time.Time
}

type AddCardInit struct {
	PaymentMethodID string
	ConfirmationURL string
}

type PaymentTransaction struct {
	ID        string
	UserID    string
	OrderID   string
	Title     string
	Amount    int64
	Status    string
	CreatedAt time.Time
}

type Promocode struct {
	Code        string
	Description string
	DiscountPct int
}

const CurrencyRUB = "RUB"

type PaymentPurpose string
type PaymentProvider string
type PaymentStatus string
type PaymentMethodType string
type WalletTransactionType string
type WalletDirection string
type WalletTransactionStatus string
type PayoutStatus string
type PayoutMethodType string
type SubscriptionStatus string
type RefundStatus string

const (
	ProviderYooKassa PaymentProvider = "yookassa"

	PaymentPurposeOrder        PaymentPurpose = "order"
	PaymentPurposeSubscription PaymentPurpose = "subscription"
	PaymentPurposeCardBinding  PaymentPurpose = "card_binding"

	PaymentStatusPending   PaymentStatus = "pending"
	PaymentStatusWaiting   PaymentStatus = "waiting_for_capture"
	PaymentStatusSucceeded PaymentStatus = "succeeded"
	PaymentStatusCanceled  PaymentStatus = "canceled"
	PaymentStatusFailed    PaymentStatus = "failed"

	PaymentMethodCard PaymentMethodType = "card"
	PaymentMethodCash PaymentMethodType = "cash"

	WalletTypeOrderIncome        WalletTransactionType = "order_income"
	WalletTypeCommission         WalletTransactionType = "commission"
	WalletTypeCashCommissionDebt WalletTransactionType = "cash_commission_debt"
	WalletTypeDebtRepayment      WalletTransactionType = "debt_repayment"
	WalletTypePendingToAvailable WalletTransactionType = "pending_to_available"
	WalletTypePayout             WalletTransactionType = "payout"
	WalletTypeRefund             WalletTransactionType = "refund"
	WalletTypeAdjustment         WalletTransactionType = "adjustment"
	WalletTypeSubscription       WalletTransactionType = "subscription_payment"
	WalletTypeBonus              WalletTransactionType = "bonus"
	WalletTypePenalty            WalletTransactionType = "penalty"

	WalletDirectionCredit WalletDirection = "credit"
	WalletDirectionDebit  WalletDirection = "debit"

	WalletTxStatusPending   WalletTransactionStatus = "pending"
	WalletTxStatusAvailable WalletTransactionStatus = "available"
	WalletTxStatusSucceeded WalletTransactionStatus = "succeeded"
	WalletTxStatusFailed    WalletTransactionStatus = "failed"

	PayoutStatusCreated      PayoutStatus = "created"
	PayoutStatusProcessing   PayoutStatus = "processing"
	PayoutStatusPaid         PayoutStatus = "paid"
	PayoutStatusFailed       PayoutStatus = "failed"
	PayoutStatusCancelled    PayoutStatus = "cancelled"
	PayoutStatusManualReview PayoutStatus = "manual_review"

	PayoutMethodCard        PayoutMethodType = "card"
	PayoutMethodSBP         PayoutMethodType = "sbp"
	PayoutMethodBankAccount PayoutMethodType = "bank_account"

	SubscriptionStatusPending SubscriptionStatus = "pending"
	SubscriptionStatusActive  SubscriptionStatus = "active"
	SubscriptionStatusExpired SubscriptionStatus = "expired"
	SubscriptionStatusFailed  SubscriptionStatus = "failed"

	RefundStatusCreated   RefundStatus = "created"
	RefundStatusSucceeded RefundStatus = "succeeded"
	RefundStatusFailed    RefundStatus = "failed"
)

type Payment struct {
	ID                string
	OrderID           *string
	DriverID          *string
	UserID            string
	Provider          PaymentProvider
	ProviderPaymentID *string
	PaymentMethod     PaymentMethodType
	Purpose           PaymentPurpose
	Amount            int64
	Currency          string
	Status            PaymentStatus
	ConfirmationURL   *string
	IdempotencyKey    string
	PaidAt            *time.Time
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

type DriverWallet struct {
	ID               string
	DriverID         string
	AvailableBalance int64
	PendingBalance   int64
	DebtBalance      int64
	Currency         string
	CreatedAt        time.Time
	UpdatedAt        time.Time
}

// DriverEarnings aggregates a driver's completed-order income across the
// today/week/month periods (amounts in kopecks) plus their current rating.
type DriverEarnings struct {
	TodayAmount   int64
	TodayOrders   int64
	WeekAmount    int64
	WeekOrders    int64
	MonthAmount   int64
	MonthOrders   int64
	RatingAverage float64
	RatingCount   int64
}

type WalletTransaction struct {
	ID             string
	WalletID       string
	DriverID       string
	OrderID        *string
	PaymentID      *string
	PayoutID       *string
	Type           WalletTransactionType
	Direction      WalletDirection
	Amount         int64
	Currency       string
	Status         WalletTransactionStatus
	Description    string
	IdempotencyKey string
	AvailableAfter *time.Time
	CreatedAt      time.Time
}

// DriverDebtTransaction is a wallet transaction that either built up the
// driver's cash-commission debt (cash_commission_debt) or reduced it
// (debt_repayment), enriched with the total of the linked order so the «Погасить
// долг» screen can show what the debt came from. Amounts in kopecks. OrderAmount
// is 0 when the linked order is missing.
type DriverDebtTransaction struct {
	ID          string
	OrderID     *string
	Type        WalletTransactionType
	Direction   WalletDirection
	Amount      int64
	Currency    string
	Status      WalletTransactionStatus
	Description string
	OrderAmount int64
	CreatedAt   time.Time
}

type Payout struct {
	ID               string
	DriverID         string
	WalletID         string
	Provider         PaymentProvider
	ProviderPayoutID *string
	Amount           int64
	Currency         string
	Status           PayoutStatus
	FailureReason    *string
	IdempotencyKey   string
	PaidAt           *time.Time
	CreatedAt        time.Time
	UpdatedAt        time.Time
}

type DriverPayoutMethod struct {
	ID                  string
	DriverID            string
	ProviderRecipientID string
	Type                PayoutMethodType
	MaskedValue         string
	IsDefault           bool
	Status              string
	CreatedAt           time.Time
}

type Subscription struct {
	ID            string
	DriverID      string
	PlanID        string
	Plan          string
	PaymentID     string
	LastPaymentID string
	Amount        int64
	Currency      string
	Status        SubscriptionStatus
	StartsAt      *time.Time
	EndsAt        *time.Time
	PeriodStart   *time.Time
	PeriodEnd     *time.Time
	CreatedAt     time.Time
	UpdatedAt     time.Time
}

type Refund struct {
	ID               string
	PaymentID        string
	ProviderRefundID *string
	Amount           int64
	Currency         string
	Reason           string
	Status           RefundStatus
	IdempotencyKey   string
	CreatedAt        time.Time
	UpdatedAt        time.Time
}

type WalletScreenData struct {
	Wallet             DriverWallet
	RecentTransactions []WalletTransaction
	RecentPayouts      []Payout
	SubscriptionStatus *SubscriptionStatus
}

type PayoutScreenData struct {
	AvailableBalance  int64
	PayoutMethods     []DriverPayoutMethod
	MinimumWithdrawal int64
	CanWithdraw       bool
}
