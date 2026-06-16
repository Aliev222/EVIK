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
	ID             string        `json:"id"`
	UserID         string        `json:"user_id"`
	DriverID       *string       `json:"driver_id"`
	Pickup         CoordinateDTO `json:"pickup"`
	Dropoff        CoordinateDTO `json:"dropoff"`
	PickupLat      float64       `json:"pickup_lat"`
	PickupLng      float64       `json:"pickup_lng"`
	DropoffLat     float64       `json:"dropoff_lat"`
	DropoffLng     float64       `json:"dropoff_lng"`
	PickupAddress  string        `json:"pickup_address" example:"ул. Тверская, 1"`
	DropoffAddress string        `json:"dropoff_address" example:"ул. Арбат, 10"`
	TowTruckType   string        `json:"tow_truck_type" example:"winch"`
	Status         string        `json:"status" example:"searching"`
	CreatedAt      string        `json:"created_at"`
	UpdatedAt      string        `json:"updated_at"`
	CancelledAt    *string       `json:"cancelled_at"`
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

// EmptyResponse is the 200 OK acknowledgement for webhook callbacks.
type EmptyResponse struct {
	OK bool `json:"ok" example:"true"`
}
