package http

// Public DTOs used by swagger annotations. The handlers internally still
// use unexported request/response types; these mirror the same JSON shape
// and exist only so swag can resolve schema references.
//
// As more endpoints get annotated, more DTOs should land here (or be moved
// to a dedicated dto/ package once this file outgrows ~300 lines).

// ErrorResponse is the canonical error envelope returned by 4xx/5xx replies.
type ErrorResponse struct {
	Error string `json:"error" example:"invalid request body"`
}

// LoginRequest is the body of POST /auth/login.
type LoginRequest struct {
	Phone    string `json:"phone" example:"+79991234567"`
	Password string `json:"password" example:"secret123"`
	Role     string `json:"role" example:"client" enums:"client,driver"`
}

// AuthTokens is the OAuth-style token pair returned by login/refresh endpoints.
type AuthTokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type" example:"Bearer"`
}

// AuthUser is the authenticated user summary embedded into login responses.
type AuthUser struct {
	ID       string `json:"id"`
	Role     string `json:"role" example:"client"`
	Phone    string `json:"phone" example:"+79991234567"`
	FullName string `json:"full_name" example:"Ivan Ivanov"`
}

// LoginResponse is the response of POST /auth/login.
type LoginResponse struct {
	Tokens AuthTokens `json:"tokens"`
	User   AuthUser   `json:"user"`
}

// CoordinateDTO is a latitude/longitude pair used by order payloads.
type CoordinateDTO struct {
	Lat float64 `json:"lat" example:"55.7522"`
	Lng float64 `json:"lng" example:"37.6156"`
}

// CreateOrderRequest is the body of POST /orders.
type CreateOrderRequest struct {
	PickupLat      float64 `json:"pickup_lat" example:"55.7522"`
	PickupLng      float64 `json:"pickup_lng" example:"37.6156"`
	DropoffLat     float64 `json:"dropoff_lat" example:"55.7600"`
	DropoffLng     float64 `json:"dropoff_lng" example:"37.6200"`
	PickupAddress  string  `json:"pickup_address" example:"ул. Тверская, 1"`
	DropoffAddress string  `json:"dropoff_address" example:"ул. Арбат, 10"`
	TowTruckType   string  `json:"tow_truck_type" example:"winch" enums:"winch,platform,manipulator"`
	PaymentMethod  string  `json:"payment_method" example:"card" enums:"cash,card"`
	AutoDispatch   bool    `json:"auto_dispatch" example:"false"`
}

// OrderDTO is the order representation returned in single-order and list
// responses. Mirrors the existing internal orderResponse shape.
type OrderDTO struct {
	ID              string        `json:"id"`
	UserID          string        `json:"user_id"`
	DriverID        *string       `json:"driver_id"`
	Pickup          CoordinateDTO `json:"pickup"`
	Dropoff         CoordinateDTO `json:"dropoff"`
	PickupLat       float64       `json:"pickup_lat"`
	PickupLng       float64       `json:"pickup_lng"`
	DropoffLat      float64       `json:"dropoff_lat"`
	DropoffLng      float64       `json:"dropoff_lng"`
	PickupAddress   string        `json:"pickup_address" example:"ул. Тверская, 1"`
	DropoffAddress  string        `json:"dropoff_address" example:"ул. Арбат, 10"`
	TowTruckType    string        `json:"tow_truck_type" example:"winch"`
	Status          string        `json:"status" example:"searching"`
	IsCrossCity     bool          `json:"is_cross_city"`
	SurchargeAmount int64         `json:"surcharge_amount"`
	SurchargePercent int          `json:"surcharge_percent"`
	CreatedAt       string        `json:"created_at"`
	UpdatedAt       string        `json:"updated_at"`
	CancelledAt     *string       `json:"cancelled_at"`
}

// SingleOrderResponse is the response of POST /orders and GET /orders/{orderID}.
type SingleOrderResponse struct {
	Order OrderDTO `json:"order"`
}

// OrderListResponse is the response of GET /orders.
type OrderListResponse struct {
	Orders []OrderDTO `json:"orders"`
}

// CreateOrderPaymentRequest is the body of POST /orders/{orderID}/payments.
type CreateOrderPaymentRequest struct {
	PaymentMethod string `json:"payment_method" example:"card" enums:"cash,card"`
}

// PaymentDTO mirrors the finance payment response shape.
type PaymentDTO struct {
	ID              string  `json:"id"`
	OrderID         *string `json:"order_id"`
	UserID          string  `json:"user_id"`
	Provider        string  `json:"provider" example:"yookassa"`
	PaymentMethod   string  `json:"payment_method" example:"card"`
	Purpose         string  `json:"purpose" example:"order"`
	Amount          int64   `json:"amount" example:"800000"`
	Currency        string  `json:"currency" example:"RUB"`
	Status          string  `json:"status" example:"pending"`
	ConfirmationURL *string `json:"confirmation_url"`
	CreatedAt       string  `json:"created_at"`
}

// CreatePaymentResponse is the response of POST /orders/{orderID}/payments.
type CreatePaymentResponse struct {
	Payment PaymentDTO `json:"payment"`
}

// YooKassaWebhookRequest is a loose schema for the YooKassa webhook body.
// We accept arbitrary JSON and rely on internal parsing; this struct only
// documents the fields the backend actually reads.
type YooKassaWebhookRequest struct {
	Event  string                `json:"event" example:"payment.succeeded"`
	Type   string                `json:"type" example:"notification"`
	Object YooKassaWebhookObject `json:"object"`
}

type YooKassaWebhookObject struct {
	ID       string            `json:"id" example:"22e12f66-000f-5000-8000-18db351245c7"`
	Status   string            `json:"status" example:"succeeded"`
	Paid     bool              `json:"paid" example:"true"`
	Metadata map[string]string `json:"metadata"`
}

// RegisterRequest is the body of POST /auth/register.
type RegisterRequest struct {
	Phone    string `json:"phone" example:"+79991234567"`
	Password string `json:"password" example:"secret123"`
	FullName string `json:"full_name" example:"Ivan Ivanov"`
	Role     string `json:"role" example:"client" enums:"client,driver"`
}

// OTPRequest is the body of POST /auth/otp/request.
type OTPRequest struct {
	Phone string `json:"phone" example:"+79991234567"`
	Role  string `json:"role" example:"client" enums:"client,driver"`
}

// OTPVerifyRequest is the body of POST /auth/otp/verify.
type OTPVerifyRequest struct {
	Phone    string `json:"phone" example:"+79991234567"`
	Code     string `json:"code" example:"123456"`
	Role     string `json:"role" example:"client" enums:"client,driver"`
	FullName string `json:"full_name,omitempty" example:"Ivan Ivanov"`
}

// AdminLoginRequest is the body of POST /auth/admin/login.
type AdminLoginRequest struct {
	UserID   string `json:"user_id,omitempty" example:"admin"`
	Password string `json:"password" example:"admin123"`
}

// RefreshRequest is the body of POST /auth/refresh.
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" example:"eyJhbGciOiJIUzI1NiIs..."`
}

// MeResponse is the response of GET /auth/me.
type MeResponse struct {
	User AuthUser `json:"user"`
}

// DeviceTokenRequest is the body of POST /devices/fcm-token.
type DeviceTokenRequest struct {
	FCMToken   string `json:"fcm_token" example:"fcm-token-123"`
	Role       string `json:"role,omitempty" example:"driver"`
	Platform   string `json:"platform,omitempty" example:"android"`
	AppVersion string `json:"app_version,omitempty" example:"1.1.0"`
}

// AcceptOrderRequest is the body of POST /orders/{orderID}/accept.
type AcceptOrderRequest struct {
	DriverID string `json:"driver_id,omitempty" example:"driver-123"`
}

// UpdateOrderStatusRequest is the body of POST /orders/{orderID}/status.
type UpdateOrderStatusRequest struct {
	Status string `json:"status" example:"arrived" enums:"accepted,arrived,in_progress,completed"`
}

// CancelOrderRequest is the body of POST /orders/{orderID}/cancel.
type CancelOrderRequest struct {
	Reason string `json:"reason,omitempty" example:"cancel reason"`
}

// AddCardRequest is the body of POST /payments/cards.
type AddCardRequest struct {
	CardNumber string `json:"card_number" example:"4111111111111111"`
	ExpMonth   int    `json:"exp_month" example:"12"`
	ExpYear    int    `json:"exp_year" example:"2028"`
	Holder     string `json:"holder" example:"IVAN IVANOV"`
	SetDefault bool   `json:"set_default" example:"true"`
}

// ApplyPromocodeRequest is the body of POST /payments/promocode/apply.
type ApplyPromocodeRequest struct {
	Code string `json:"code" example:"EVIK2025"`
}

// RequestPayoutRequest is the body of POST /driver/payouts/request.
type RequestPayoutRequest struct {
	Amount int64 `json:"amount" example:"500000"`
}

// AddPayoutMethodRequest is the body of POST /driver/payout-methods.
type AddPayoutMethodRequest struct {
	ProviderRecipientID string `json:"provider_recipient_id" example:"account-123"`
	Type                string `json:"type" example:"bank_card" enums:"bank_card,wallet"`
	MaskedValue         string `json:"masked_value" example:"****1234"`
	IsDefault           bool   `json:"is_default" example:"true"`
}

// SubscriptionPaymentRequest is the body of POST /driver/subscription/payment.
type SubscriptionPaymentRequest struct {
	PlanID string `json:"plan_id" example:"plan-monthly"`
}

// RefundRequest is the body of POST /admin/finance/refunds.
type RefundRequest struct {
	PaymentID string `json:"payment_id" example:"pay-123"`
	Amount    int64  `json:"amount" example:"800000"`
	Reason    string `json:"reason" example:"Customer request"`
}

// EmptyResponse is the 200 OK acknowledgement for webhook callbacks.
type EmptyResponse struct {
	OK bool `json:"ok" example:"true"`
}
