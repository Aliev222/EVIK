package http

import (
	"encoding/csv"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"evik/backend/internal/auth"
	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
	driveruc "evik/backend/internal/usecase/driver"
	paymentuc "evik/backend/internal/usecase/payment"
	"github.com/go-chi/chi/v5"
)

type PaymentHandler struct {
	repo      paymentdomain.Repository
	financeUC *paymentuc.FinanceUseCase
	orderRepo orderdomain.Repository
	gates     *driveruc.GateService
	idGen     interface{ NewID() string }
	clock     interface{ Now() time.Time }
	verifier  paymentuc.WebhookVerifier
}

func NewPaymentHandler(
	repo paymentdomain.Repository,
	financeUC *paymentuc.FinanceUseCase,
	orderRepo orderdomain.Repository,
	gates *driveruc.GateService,
	idGen interface{ NewID() string },
	clock interface{ Now() time.Time },
	verifier paymentuc.WebhookVerifier,
) *PaymentHandler {
	return &PaymentHandler{repo: repo, financeUC: financeUC, orderRepo: orderRepo, gates: gates, idGen: idGen, clock: clock, verifier: verifier}
}

// writePaymentError maps payment/provider errors to accurate HTTP status codes
// and hides internal error detail from the response body. A misconfigured or
// unreachable payment provider must never surface as a 400 (which wrongly blames
// the caller); it surfaces as 503/502 instead.
func writePaymentError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, paymentuc.ErrProviderNotConfigured):
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "Payment service is temporarily unavailable"})
	case errors.Is(err, paymentuc.ErrProviderUnavailable):
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "Payment service is temporarily unavailable"})
	case errors.Is(err, paymentuc.ErrProviderUnauthorized):
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Payment authorization failed"})
	case errors.Is(err, paymentuc.ErrOrderNotOwned):
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
	case errors.Is(err, paymentdomain.ErrDuplicateOperation):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "duplicate operation"})
	case errors.Is(err, paymentdomain.ErrValidationFailed),
		errors.Is(err, paymentdomain.ErrInvalidAmount),
		errors.Is(err, paymentdomain.ErrInsufficientFunds),
		errors.Is(err, paymentdomain.ErrPayoutMethodNotFound),
		errors.Is(err, orderdomain.ErrInvalidTransition):
		// Validation/precondition errors are safe and useful to echo back.
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
	default:
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Payment processing failed"})
	}
}

type addCardRequest struct {
	CardNumber string `json:"card_number"`
	ExpMonth   int    `json:"exp_month"`
	ExpYear    int    `json:"exp_year"`
	Holder     string `json:"holder"`
	SetDefault bool   `json:"set_default"`
}

type applyPromocodeRequest struct {
	Code string `json:"code"`
}

type createOrderPaymentRequest struct {
	PaymentMethod string `json:"payment_method"`
}

type requestPayoutRequest struct {
	Amount int64 `json:"amount"`
}

type addPayoutMethodRequest struct {
	ProviderRecipientID string `json:"provider_recipient_id"`
	Type                string `json:"type"`
	MaskedValue         string `json:"masked_value"`
	IsDefault           bool   `json:"is_default"`
}

type subscriptionPaymentRequest struct {
	PlanID string `json:"plan_id"`
}

type refundRequest struct {
	PaymentID string `json:"payment_id"`
	Amount    int64  `json:"amount"`
	Reason    string `json:"reason"`
}

type paymentMethodResponse struct {
	ID                      string  `json:"id"`
	ProviderPaymentMethodID *string `json:"provider_payment_method_id,omitempty"`
	Brand                   string  `json:"brand"`
	Last4                   string  `json:"last4"`
	ExpMonth                int     `json:"exp_month"`
	ExpYear                 int     `json:"exp_year"`
	Holder                  string  `json:"holder"`
	Status                  string  `json:"status"`
	IsDefault               bool    `json:"is_default"`
	CreatedAt               string  `json:"created_at"`
}

type paymentTransactionResponse struct {
	ID        string `json:"id"`
	OrderID   string `json:"order_id"`
	Title     string `json:"title"`
	Amount    int64  `json:"amount"`
	Status    string `json:"status"`
	CreatedAt string `json:"created_at"`
}

// @Summary      Get client wallet
// @Description  Returns saved payment cards and recent payment transactions for the authenticated client.
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "cards and payments lists"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Router       /payments/wallet [get]
func (h *PaymentHandler) GetWallet(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	methods, err := h.repo.ListMethods(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	transactions, err := h.repo.ListClientPayments(r.Context(), userID, 20, 0)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	cards := make([]paymentMethodResponse, 0, len(methods))
	for _, method := range methods {
		cards = append(cards, newPaymentMethodResponse(method))
	}
	payments := make([]paymentTransactionResponse, 0, len(transactions))
	for _, transaction := range transactions {
		payments = append(payments, newPaymentTransactionResponse(transaction))
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"cards":    cards,
		"payments": payments,
	})
}

// CreateOrderPayment creates a payment for an existing order. Cash payments are
// recorded immediately as succeeded; card payments are routed through YooKassa
// and start in pending status with a confirmation_url.
//
// @Summary      Create payment for order
// @Tags         payments
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path      string                     true  "Order ID"
// @Param        body     body      CreateOrderPaymentRequest  true  "Payment payload"
// @Success      201      {object}  CreatePaymentResponse
// @Failure      400      {object}  ErrorResponse  "invalid payment_method or validation failed"
// @Failure      401      {object}  ErrorResponse  "unauthorized"
// @Failure      403      {object}  ErrorResponse  "order does not belong to caller"
// @Router       /orders/{orderID}/payments [post]
func (h *PaymentHandler) CreateOrderPayment(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req createOrderPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	payment, err := h.financeUC.CreateOrderPayment(r.Context(), userID, chi.URLParam(r, "orderID"), paymentdomain.PaymentMethodType(req.PaymentMethod))
	if err != nil {
		writePaymentError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"payment": newFinancePaymentResponse(payment)})
}

// ConfirmPayment processes the client's payment confirmation for an order.
// For cash orders the order completes immediately. For card orders a YooKassa
// payment is created; if 3DS is required a confirmation_url is returned.
//
// @Summary      Confirm order payment
// @Description  Client confirms payment for a finalized order. Cash completes immediately; card creates YooKassa payment.
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path  string  true  "Order ID"
// @Success      200  {object}  map[string]any  "payment result, possible confirmation_url for 3DS"
// @Failure      400  {object}  ErrorResponse  "validation failed"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "order does not belong to caller"
// @Failure      409  {object}  ErrorResponse  "invalid order status"
// @Router       /orders/{orderID}/confirm-payment [post]
func (h *PaymentHandler) ConfirmPayment(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	orderID := chi.URLParam(r, "orderID")
	payment, err := h.financeUC.ConfirmOrderPayment(r.Context(), userID, orderID)
	if err != nil {
		writePaymentError(w, err)
		return
	}
	resp := map[string]any{"status": "completed"}
	if payment != nil {
		resp["status"] = string(payment.Status)
		if payment.ConfirmationURL != nil {
			resp["confirmation_url"] = *payment.ConfirmationURL
		}
		resp["payment"] = newFinancePaymentResponse(payment)
	}
	writeJSON(w, http.StatusOK, resp)
}

// UpdateOrderPaymentMethodRequest is the body of PATCH /orders/{orderID}/payment-method.
type updateOrderPaymentMethodRequest struct {
	PaymentMethod string `json:"payment_method"`
}

// @Summary      Update order payment method
// @Description  Changes the payment method on an order in awaiting_payment status. Only cash or card.
// @Tags         payments
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path  string  true  "Order ID"
// @Param        body     body  updateOrderPaymentMethodRequest  true  "New payment method"
// @Success      200  {object}  map[string]any  "payment method updated"
// @Failure      400  {object}  ErrorResponse  "invalid payment_method or order not in valid status"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "order does not belong to caller"
// @Router       /orders/{orderID}/payment-method [patch]
func (h *PaymentHandler) UpdateOrderPaymentMethod(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req updateOrderPaymentMethodRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if req.PaymentMethod != "cash" && req.PaymentMethod != "card" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "payment_method must be cash or card"})
		return
	}
	orderID := chi.URLParam(r, "orderID")
	if err := h.financeUC.UpdateOrderPaymentMethod(r.Context(), userID, orderID, paymentdomain.PaymentMethodType(req.PaymentMethod)); err != nil {
		writePaymentError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

// @Summary      Init payment method
// @Description  Initializes a YooKassa payment method for the client. Returns a confirmation URL for 3DS redirect.
// @Tags         payments
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Success      201  {object}  map[string]any  "confirmation_url and payment_method_id"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Router       /client/payment-methods/init [post]
func (h *PaymentHandler) InitClientPaymentMethod(w http.ResponseWriter, r *http.Request) {
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if role != auth.RoleClient && role != auth.RoleAdmin {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	init, err := h.financeUC.SaveClientPaymentMethod(r.Context(), userID)
	if err != nil {
		writePaymentError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"confirmation_url":  init.ConfirmationURL,
		"payment_method_id": init.PaymentMethodID,
	})
}

// @Summary      Get order payment status
// @Description  Returns the payment details for a specific order.
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path  string  true  "Order ID"
// @Success      200  {object}  map[string]any  "payment details"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Failure      404  {object}  ErrorResponse  "payment not found"
// @Router       /orders/{orderID}/payment-status [get]
func (h *PaymentHandler) GetOrderPaymentStatus(w http.ResponseWriter, r *http.Request) {
	if !h.canAccessOrderPayment(r, chi.URLParam(r, "orderID")) {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	payment, err := h.repo.GetPaymentByOrderID(r.Context(), chi.URLParam(r, "orderID"))
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, paymentdomain.ErrPaymentNotFound) {
			status = http.StatusNotFound
		}
		writeJSON(w, status, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"payment": newFinancePaymentResponse(payment)})
}

// @Summary      Get order receipt
// @Description  Returns a detailed receipt for a completed order including payment info, commission, and driver details.
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Param        orderID  path  string  true  "Order ID"
// @Success      200  {object}  map[string]any  "receipt details"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      403  {object}  ErrorResponse  "forbidden"
// @Failure      404  {object}  ErrorResponse  "order or payment not found"
// @Router       /orders/{orderID}/receipt [get]
func (h *PaymentHandler) GetOrderReceipt(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderID")
	if !h.canAccessOrderPayment(r, orderID) {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	payment, err := h.repo.GetPaymentByOrderID(r.Context(), orderID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	details, err := h.orderRepo.GetAdminOrderDetails(r.Context(), orderID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	completedAt := any(nil)
	if details.Order.CompletedAt != nil {
		completedAt = details.Order.CompletedAt.Format(time.RFC3339)
	}
	paidAt := any(nil)
	if payment.PaidAt != nil {
		paidAt = payment.PaidAt.Format(time.RFC3339)
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"order_id":          orderID,
		"payment_id":        payment.ID,
		"price_total":       payment.Amount,
		"amount":            payment.Amount,
		"currency":          payment.Currency,
		"payment_method":    payment.PaymentMethod,
		"payment_status":    payment.Status,
		"status":            payment.Status,
		"commission_amount": details.Order.CommissionAmount,
		"commission":        details.Order.CommissionAmount,
		"driver_amount":     details.Order.DriverAmount,
		"created_at":        details.Order.CreatedAt.Format(time.RFC3339),
		"completed_at":      completedAt,
		"paid_at":           paidAt,
		"driver_id":         details.Order.DriverID,
		"driver_name":       details.Order.DriverName,
		"driver_phone":      details.Order.DriverPhone,
	})
}

// HandleYooKassaWebhook receives asynchronous payment events from YooKassa.
// Verifies the sender by IP allowlist (YooKassa published CIDR ranges) and
// confirms the payment status by re-querying the YooKassa API before applying
// any state changes. Idempotent: replayed webhooks are stored and acknowledged
// without re-running side effects.
//
// @Summary      YooKassa webhook
// @Description  Public webhook receiver. Verified by IP allowlist; payment status confirmed via YooKassa API re-query. No bearer auth.
// @Tags         webhooks
// @Accept       json
// @Produce      json
// @Param        body  body      YooKassaWebhookRequest  true  "YooKassa event"
// @Success      200   {object}  EmptyResponse
// @Failure      400   {object}  ErrorResponse  "malformed payload"
// @Failure      403   {object}  ErrorResponse  "forbidden"
// @Router       /webhooks/yookassa [post]
func (h *PaymentHandler) HandleYooKassaWebhook(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if err := h.verifier.Verify(r, body); err != nil {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}
	if err := h.financeUC.HandleProviderWebhook(r.Context(), h.verifier, body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"processed": true})
}

// @Summary      Get driver wallet
// @Description  Returns the driver's wallet balance, recent transactions, and recent payouts.
// @Tags         driver
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "wallet info with balance, transactions, payouts"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Router       /driver/wallet [get]
func (h *PaymentHandler) GetDriverWallet(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	wallet, err := h.repo.GetDriverWallet(r.Context(), driverID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	txs, err := h.repo.ListWalletTransactions(r.Context(), driverID, 10)
	if err != nil {
		log.Printf("ERROR: ListWalletTransactions failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Failed to load transactions"})
		return
	}
	payouts, err := h.repo.ListPayouts(r.Context(), driverID, 10)
	if err != nil {
		log.Printf("ERROR: ListPayouts failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Failed to load payouts"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"available_balance":   wallet.AvailableBalance,
		"pending_balance":     wallet.PendingBalance,
		"debt_balance":        wallet.DebtBalance,
		"currency":            wallet.Currency,
		"recent_transactions": txs,
		"recent_payouts":      payouts,
	})
}

// @Summary      Get driver earnings
// @Description  Returns the driver's real earnings (sum of driver_amount over completed orders) for today/week/month plus current rating. Amounts in kopecks.
// @Tags         driver
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "earnings by period and rating"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Router       /driver/earnings [get]
func (h *PaymentHandler) GetDriverEarnings(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	loc, err := time.LoadLocation("Europe/Moscow")
	if err != nil {
		loc = time.UTC
	}
	now := time.Now().In(loc)
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)

	weekday := int(now.Weekday())
	if weekday == 0 {
		weekday = 7 // Sunday → 7 so the week starts on Monday
	}
	weekStart := todayStart.AddDate(0, 0, -(weekday - 1))

	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc)

	e, err := h.repo.GetDriverEarnings(r.Context(), driverID, todayStart, weekStart, monthStart)
	if err != nil {
		log.Printf("ERROR: GetDriverEarnings failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Failed to load earnings"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"today":  map[string]any{"amount": e.TodayAmount, "orders": e.TodayOrders},
		"week":   map[string]any{"amount": e.WeekAmount, "orders": e.WeekOrders},
		"month":  map[string]any{"amount": e.MonthAmount, "orders": e.MonthOrders},
		"rating": map[string]any{"average": e.RatingAverage, "count": e.RatingCount},
	})
}

// @Summary      List driver wallet transactions
// @Description  Returns the driver's recent wallet transactions.
// @Tags         driver
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "list of transactions"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Router       /driver/wallet/transactions [get]
func (h *PaymentHandler) ListDriverWalletTransactions(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	txs, err := h.repo.ListWalletTransactions(r.Context(), driverID, 50)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"transactions": txs})
}

// @Summary      List driver payouts
// @Description  Returns the driver's recent payout history.
// @Tags         driver
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "list of payouts"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Router       /driver/payouts [get]
func (h *PaymentHandler) ListDriverPayouts(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	payouts, err := h.repo.ListPayouts(r.Context(), driverID, 50)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"payouts": payouts})
}

// @Summary      Request driver payout
// @Description  Creates a payout request from the driver's available balance to their payout method.
// @Tags         driver
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      RequestPayoutRequest  true  "Payout amount in kopecks"
// @Success      201   {object}  map[string]any  "created payout"
// @Failure      400   {object}  ErrorResponse  "validation failed"
// @Failure      401   {object}  ErrorResponse  "unauthorized"
// @Failure      403   {object}  ErrorResponse  "gate check failed"
// @Router       /driver/payouts/request [post]
func (h *PaymentHandler) RequestDriverPayout(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req requestPayoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if h.gates != nil {
		if err := h.gates.EnsureCanRequestPayout(r.Context(), driverID); err != nil {
			h.writeDriverGateError(w, err)
			return
		}
	}
	idempotencyKey := r.Header.Get("Idempotency-Key")
	if idempotencyKey == "" {
		idempotencyKey = r.Header.Get("X-Idempotency-Key")
	}
	payout, err := h.financeUC.RequestDriverPayout(r.Context(), driverID, req.Amount, idempotencyKey)
	if err != nil {
		writePaymentError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"payout": payout})
}

// @Summary      List driver payout methods
// @Description  Returns saved payout methods (bank cards, wallets) for the authenticated driver.
// @Tags         driver
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "list of payout methods"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Router       /driver/payout-methods [get]
func (h *PaymentHandler) ListDriverPayoutMethods(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	methods, err := h.repo.ListPayoutMethods(r.Context(), driverID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"payout_methods": methods})
}

// @Summary      Add payout method
// @Description  Saves a new payout method (bank card or wallet) for the driver.
// @Tags         driver
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      AddPayoutMethodRequest  true  "Payout method payload"
// @Success      201   {object}  map[string]any  "created payout method"
// @Failure      400   {object}  ErrorResponse  "validation failed"
// @Failure      401   {object}  ErrorResponse  "unauthorized"
// @Router       /driver/payout-methods [post]
func (h *PaymentHandler) AddDriverPayoutMethod(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req addPayoutMethodRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	method := paymentdomain.DriverPayoutMethod{
		ID: h.idGen.NewID(), DriverID: driverID, ProviderRecipientID: strings.TrimSpace(req.ProviderRecipientID),
		Type: paymentdomain.PayoutMethodType(req.Type), MaskedValue: strings.TrimSpace(req.MaskedValue),
		IsDefault: req.IsDefault, Status: "active", CreatedAt: h.clock.Now(),
	}
	if method.ProviderRecipientID == "" || method.MaskedValue == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "payout method is invalid"})
		return
	}
	if err := h.repo.AddPayoutMethod(r.Context(), method); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"payout_method": method})
}

// @Summary      Create driver subscription payment
// @Description  Creates a payment for a driver subscription plan (e.g. monthly fee).
// @Tags         driver
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      SubscriptionPaymentRequest  true  "Plan ID"
// @Success      201   {object}  map[string]any  "payment details"
// @Failure      400   {object}  ErrorResponse  "validation failed"
// @Failure      401   {object}  ErrorResponse  "unauthorized"
// @Router       /driver/subscription/payment [post]
func (h *PaymentHandler) CreateDriverSubscriptionPayment(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req subscriptionPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	payment, err := h.financeUC.CreateDriverSubscriptionPayment(r.Context(), driverID, req.PlanID)
	if err != nil {
		writePaymentError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"payment": newFinancePaymentResponse(payment)})
}

// @Summary      Get driver subscription status
// @Description  Returns the driver's current subscription status (active, expired, none).
// @Tags         driver
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "subscription status"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Router       /driver/subscription/status [get]
func (h *PaymentHandler) GetDriverSubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	driverID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	status, err := h.financeUC.GetDriverSubscriptionStatus(r.Context(), driverID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, status)
}

// @Summary      Create refund (admin)
// @Description  Creates a refund for a completed payment. Admin-only endpoint.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      RefundRequest  true  "Refund payload"
// @Success      201   {object}  map[string]any  "created refund"
// @Failure      400   {object}  ErrorResponse  "validation failed"
// @Router       /admin/finance/refunds [post]
func (h *PaymentHandler) AdminCreateRefund(w http.ResponseWriter, r *http.Request) {
	var req refundRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	refund, err := h.financeUC.CreateRefund(r.Context(), req.PaymentID, req.Amount, req.Reason)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"refund": refund})
}

// @Summary      Export finance report (admin)
// @Description  Exports a finance report as CSV. Admin-only endpoint.
// @Tags         admin
// @Produce      text/csv
// @Security     BearerAuth
// @Param        type  query  string  true  "Report type"  Enums(payments,payouts,orders)
// @Success      200  {object}  string  "CSV file"
// @Failure      400  {object}  ErrorResponse  "invalid report type"
// @Router       /admin/finance/export [get]
func (h *PaymentHandler) AdminExportFinance(w http.ResponseWriter, r *http.Request) {
	reportType := r.URL.Query().Get("type")
	records, err := h.repo.ExportFinanceReport(r.Context(), reportType)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", "attachment; filename=\""+reportType+".csv\"")
	if err := csv.NewWriter(w).WriteAll(records); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to write CSV"})
		return
	}
}

// @Summary      Finance report (admin)
// @Description  Returns a finance report as JSON. Admin-only endpoint.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        reportType  path  string  true  "Report type"
// @Success      200  {object}  map[string]any  "report rows"
// @Failure      400  {object}  ErrorResponse  "invalid report type"
// @Router       /admin/finance/report/{reportType} [get]
func (h *PaymentHandler) AdminFinanceReport(w http.ResponseWriter, r *http.Request) {
	reportType := chi.URLParam(r, "reportType")
	records, err := h.repo.ExportFinanceReport(r.Context(), reportType)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"rows": records})
}

type adminRejectPayoutRequest struct {
	Reason string `json:"reason"`
}

// @Summary      List refunds (admin)
// @Description  Returns paginated refunds with optional filters. Admin-only.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        status     query  string  false  "Filter by status"  Enums(pending,succeeded,failed)
// @Param        payment_id query  string  false  "Filter by payment ID"
// @Param        order_id   query  string  false  "Filter by order ID"
// @Param        from       query  string  false  "Start date (RFC3339)"
// @Param        to         query  string  false  "End date (RFC3339)"
// @Param        limit      query  int     false  "Max items (default 50, max 200)"
// @Param        offset     query  int     false  "Pagination offset"
// @Success      200  {object}  map[string]any  "paginated refunds with total count"
// @Failure      400  {object}  ErrorResponse  "validation failed"
// @Router       /admin/finance/refunds [get]
func (h *PaymentHandler) AdminListRefunds(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	filter := paymentdomain.AdminRefundFilter{
		Status:    strings.TrimSpace(q.Get("status")),
		PaymentID: strings.TrimSpace(q.Get("payment_id")),
		OrderID:   strings.TrimSpace(q.Get("order_id")),
		Limit:     parseAdminLimit(r, 50, 200),
		Offset:    parseAdminOffset(r),
	}
	if from, ok := parseAdminTime(q.Get("from")); ok {
		filter.From = &from
	}
	if to, ok := parseAdminTime(q.Get("to")); ok {
		filter.To = &to
	}

	refunds, total, err := h.financeUC.ListAdminRefunds(r.Context(), filter)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	items := make([]map[string]any, 0, len(refunds))
	for _, refund := range refunds {
		items = append(items, adminRefundItemJSON(refund))
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":  items,
		"total":  total,
		"limit":  filter.Limit,
		"offset": filter.Offset,
	})
}

// @Summary      Approve payout (admin)
// @Description  Approves a pending driver payout. Admin-only endpoint.
// @Tags         admin
// @Produce      json
// @Security     BearerAuth
// @Param        payoutID  path  string  true  "Payout ID"
// @Success      200  {object}  map[string]any  "approved payout"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      404  {object}  ErrorResponse  "payout not found"
// @Failure      409  {object}  ErrorResponse  "payout not in approvable status"
// @Router       /admin/finance/payouts/{payoutID}/approve [post]
func (h *PaymentHandler) AdminApprovePayout(w http.ResponseWriter, r *http.Request) {
	payoutID := strings.TrimSpace(chi.URLParam(r, "payoutID"))
	if payoutID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "payout id is required"})
		return
	}
	moderatorID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	payout, err := h.financeUC.ApprovePayout(r.Context(), payoutID, moderatorID)
	if err != nil {
		switch {
		case errors.Is(err, paymentdomain.ErrPayoutNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		case errors.Is(err, paymentdomain.ErrPayoutNotApprovable):
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"payout": adminPayoutJSON(payout)})
}

// @Summary      Reject payout (admin)
// @Description  Rejects a pending driver payout with a reason. Admin-only endpoint.
// @Tags         admin
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        payoutID  path  string  true  "Payout ID"
// @Success      200  {object}  map[string]any  "rejected payout"
// @Failure      400  {object}  ErrorResponse  "reason is required (min 8 chars)"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      404  {object}  ErrorResponse  "payout not found"
// @Failure      409  {object}  ErrorResponse  "payout not in rejectable status"
// @Router       /admin/finance/payouts/{payoutID}/reject [post]
func (h *PaymentHandler) AdminRejectPayout(w http.ResponseWriter, r *http.Request) {
	payoutID := strings.TrimSpace(chi.URLParam(r, "payoutID"))
	if payoutID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "payout id is required"})
		return
	}
	var req adminRejectPayoutRequest
	if r.Body != nil {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
			return
		}
	}
	reason := strings.TrimSpace(req.Reason)
	if len(reason) < 8 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required (min 8 characters)"})
		return
	}
	moderatorID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	payout, err := h.financeUC.RejectPayout(r.Context(), payoutID, moderatorID, reason)
	if err != nil {
		switch {
		case errors.Is(err, paymentdomain.ErrPayoutNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		case errors.Is(err, paymentdomain.ErrPayoutNotRejectable):
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"payout": adminPayoutJSON(payout)})
}

func adminRefundItemJSON(refund paymentdomain.Refund) map[string]any {
	providerRefundID := ""
	if refund.ProviderRefundID != nil {
		providerRefundID = *refund.ProviderRefundID
	}
	return map[string]any{
		"refund_id":          refund.ID,
		"payment_id":         refund.PaymentID,
		"order_id":           "", // resolved via /admin/orders if needed
		"amount":             refund.Amount,
		"currency":           refund.Currency,
		"reason":             refund.Reason,
		"status":             refund.Status,
		"provider_refund_id": providerRefundID,
		"created_at":         refund.CreatedAt.Format(time.RFC3339),
		"updated_at":         refund.UpdatedAt.Format(time.RFC3339),
	}
}

func adminPayoutJSON(payout *paymentdomain.Payout) map[string]any {
	providerPayoutID := ""
	if payout.ProviderPayoutID != nil {
		providerPayoutID = *payout.ProviderPayoutID
	}
	failureReason := ""
	if payout.FailureReason != nil {
		failureReason = *payout.FailureReason
	}
	paidAt := any(nil)
	if payout.PaidAt != nil {
		paidAt = payout.PaidAt.Format(time.RFC3339)
	}
	return map[string]any{
		"id":                 payout.ID,
		"driver_id":          payout.DriverID,
		"wallet_id":          payout.WalletID,
		"provider":           payout.Provider,
		"provider_payout_id": providerPayoutID,
		"amount":             payout.Amount,
		"currency":           payout.Currency,
		"status":             payout.Status,
		"failure_reason":     failureReason,
		"paid_at":            paidAt,
		"created_at":         payout.CreatedAt.Format(time.RFC3339),
		"updated_at":         payout.UpdatedAt.Format(time.RFC3339),
	}
}

func (h *PaymentHandler) AddCard(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusGone, map[string]string{"error": "direct card entry is disabled; use /client/payment-methods/init"})
	return
}

func (h *PaymentHandler) canAccessOrderPayment(r *http.Request, orderID string) bool {
	ord, err := h.orderRepo.GetByID(r.Context(), orderID)
	if err != nil {
		return false
	}
	role, err := roleFromContext(r.Context())
	if err != nil {
		return false
	}
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		return false
	}
	switch role {
	case auth.RoleAdmin:
		return true
	case auth.RoleClient:
		return ord.UserID == userID
	case auth.RoleDriver:
		return ord.DriverID != nil && *ord.DriverID == userID
	default:
		return false
	}
}

func (h *PaymentHandler) writeDriverGateError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, driveruc.ErrDriverDocumentsNotApproved),
		errors.Is(err, driveruc.ErrDriverTaxNotVerified),
		errors.Is(err, driveruc.ErrDriverSubscriptionInactive):
		writeJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
	default:
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
}

func (h *PaymentHandler) addCardLegacyDisabled(w http.ResponseWriter, r *http.Request) {
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if role != auth.RoleClient && role != auth.RoleAdmin {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req addCardRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	method, err := h.paymentMethodFromRequest(userID, req)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if err := h.repo.AddMethod(r.Context(), method); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"card": newPaymentMethodResponse(method)})
}

// @Summary      Set default card
// @Description  Marks a saved card as the default payment method. Client-only endpoint.
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Param        cardID  path  string  true  "Card ID"
// @Success      200  {object}  map[string]any  "updated card"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      404  {object}  ErrorResponse  "card not found"
// @Router       /payments/cards/{cardID}/default [post]
func (h *PaymentHandler) SetDefaultCard(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	cardID := chi.URLParam(r, "cardID")
	method, err := h.repo.SetDefaultMethod(r.Context(), userID, cardID)
	if err != nil {
		if errors.Is(err, paymentdomain.ErrPaymentMethodNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"card": newPaymentMethodResponse(*method)})
}

// @Summary      Delete card
// @Description  Removes a saved payment card. Client-only endpoint.
// @Tags         payments
// @Produce      json
// @Security     BearerAuth
// @Param        cardID  path  string  true  "Card ID"
// @Success      200  {object}  map[string]any  "deleted: true"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      404  {object}  ErrorResponse  "card not found"
// @Router       /payments/cards/{cardID} [delete]
func (h *PaymentHandler) DeleteCard(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	cardID := chi.URLParam(r, "cardID")
	if err := h.repo.DeleteMethod(r.Context(), userID, cardID); err != nil {
		if errors.Is(err, paymentdomain.ErrPaymentMethodNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true})
}

// @Summary      Apply promocode
// @Description  Applies a discount promocode to the client's account.
// @Tags         payments
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Param        body  body      ApplyPromocodeRequest  true  "Promocode code"
// @Success      200  {object}  map[string]any  "promocode details with discount"
// @Failure      400  {object}  ErrorResponse  "invalid promocode"
// @Router       /payments/promocode/apply [post]
func (h *PaymentHandler) ApplyPromocode(w http.ResponseWriter, r *http.Request) {
	var req applyPromocodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	code := strings.ToUpper(strings.TrimSpace(req.Code))
	if code != "EVIK2025" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": paymentdomain.ErrInvalidPromocode.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"promocode": map[string]any{
			"code":         code,
			"description":  "Скидка 10% на следующую поездку",
			"discount_pct": 10,
		},
	})
}

func (h *PaymentHandler) paymentMethodFromRequest(userID string, req addCardRequest) (paymentdomain.PaymentMethod, error) {
	cardNumber := onlyDigits(req.CardNumber)
	holder := strings.TrimSpace(req.Holder)
	if len(cardNumber) < 13 || len(cardNumber) > 19 || !validLuhn(cardNumber) {
		return paymentdomain.PaymentMethod{}, errors.New("invalid card number")
	}
	if req.ExpMonth < 1 || req.ExpMonth > 12 {
		return paymentdomain.PaymentMethod{}, errors.New("invalid expiration month")
	}
	if req.ExpYear < 100 {
		req.ExpYear += 2000
	}
	now := h.clock.Now()
	expiresAt := time.Date(req.ExpYear, time.Month(req.ExpMonth)+1, 1, 0, 0, 0, 0, time.UTC)
	if !expiresAt.After(now) {
		return paymentdomain.PaymentMethod{}, errors.New("card is expired")
	}
	if len(holder) < 3 || len(holder) > 80 {
		return paymentdomain.PaymentMethod{}, errors.New("invalid card holder")
	}
	return paymentdomain.PaymentMethod{
		ID:        h.idGen.NewID(),
		UserID:    userID,
		Brand:     detectCardBrand(cardNumber),
		Last4:     cardNumber[len(cardNumber)-4:],
		ExpMonth:  req.ExpMonth,
		ExpYear:   req.ExpYear,
		Holder:    holder,
		IsDefault: req.SetDefault,
		CreatedAt: now,
	}, nil
}

func newPaymentMethodResponse(method paymentdomain.PaymentMethod) paymentMethodResponse {
	return paymentMethodResponse{
		ID:                      method.ID,
		ProviderPaymentMethodID: method.ProviderPaymentMethodID,
		Brand:                   string(method.Brand),
		Last4:                   method.Last4,
		ExpMonth:                method.ExpMonth,
		ExpYear:                 method.ExpYear,
		Holder:                  method.Holder,
		Status:                  method.Status,
		IsDefault:               method.IsDefault,
		CreatedAt:               method.CreatedAt.Format(time.RFC3339),
	}
}

func newPaymentTransactionResponse(transaction paymentdomain.PaymentTransaction) paymentTransactionResponse {
	return paymentTransactionResponse{
		ID:        transaction.ID,
		OrderID:   transaction.OrderID,
		Title:     transaction.Title,
		Amount:    transaction.Amount,
		Status:    transaction.Status,
		CreatedAt: transaction.CreatedAt.Format(time.RFC3339),
	}
}

func newFinancePaymentResponse(payment *paymentdomain.Payment) map[string]any {
	return map[string]any{
		"id":                  payment.ID,
		"order_id":            payment.OrderID,
		"provider":            payment.Provider,
		"provider_payment_id": payment.ProviderPaymentID,
		"payment_method":      payment.PaymentMethod,
		"purpose":             payment.Purpose,
		"amount":              payment.Amount,
		"currency":            payment.Currency,
		"status":              payment.Status,
		"confirmation_url":    payment.ConfirmationURL,
		"paid_at":             payment.PaidAt,
		"created_at":          payment.CreatedAt.Format(time.RFC3339),
	}
}

func onlyDigits(value string) string {
	var builder strings.Builder
	for _, char := range value {
		if char >= '0' && char <= '9' {
			builder.WriteRune(char)
		}
	}
	return builder.String()
}

func detectCardBrand(cardNumber string) paymentdomain.CardBrand {
	switch {
	case strings.HasPrefix(cardNumber, "4"):
		return paymentdomain.CardBrandVisa
	case strings.HasPrefix(cardNumber, "220"):
		return paymentdomain.CardBrandMir
	case len(cardNumber) >= 2:
		prefix, _ := strconv.Atoi(cardNumber[:2])
		if prefix >= 51 && prefix <= 55 {
			return paymentdomain.CardBrandMastercard
		}
	}
	return paymentdomain.CardBrandUnknown
}

func validLuhn(cardNumber string) bool {
	sum := 0
	alternate := false
	for i := len(cardNumber) - 1; i >= 0; i-- {
		n := int(cardNumber[i] - '0')
		if alternate {
			n *= 2
			if n > 9 {
				n -= 9
			}
		}
		sum += n
		alternate = !alternate
	}
	return sum%10 == 0
}
