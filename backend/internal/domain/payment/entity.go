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
	ID        string
	UserID    string
	Brand     CardBrand
	Last4     string
	ExpMonth  int
	ExpYear   int
	Holder    string
	IsDefault bool
	CreatedAt time.Time
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
