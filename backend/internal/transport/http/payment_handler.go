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
	stubMode  bool
}

func NewPaymentHandler(
	repo paymentdomain.Repository,
	financeUC *paymentuc.FinanceUseCase,
	orderRepo orderdomain.Repository,
	gates *driveruc.GateService,
	idGen interface{ NewID() string },
	clock interface{ Now() time.Time },
	stubMode bool,
) *PaymentHandler {
	return &PaymentHandler{repo: repo, financeUC: financeUC, orderRepo: orderRepo, gates: gates, idGen: idGen, clock: clock, stubMode: stubMode}
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
		errors.Is(err, paymentdomain.ErrPayoutMethodNotFound):
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
// Idempotent: replayed webhooks are stored and acknowledged without re-running
// side effects. The request body is the raw YooKassa notification payload.
//
// @Summary      YooKassa webhook
// @Description  Public webhook receiver. Verified via HMAC-SHA256 signature in the configured header. No bearer auth.
// @Tags         webhooks
// @Accept       json
// @Produce      json
// @Param        body  body      YooKassaWebhookRequest  true  "YooKassa event"
// @Success      200   {object}  EmptyResponse
// @Failure      400   {object}  ErrorResponse  "malformed payload"
// @Failure      401   {object}  ErrorResponse  "invalid signature"
// @Router       /webhooks/yookassa [post]
func (h *PaymentHandler) HandleYooKassaWebhook(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	signature := r.Header.Get("X-YooKassa-Signature")
	if signature == "" {
		signature = r.Header.Get("X-Webhook-Signature")
	}
	if err := h.financeUC.HandleYooKassaWebhook(r.Context(), body, signature); err != nil {
		if errors.Is(err, paymentuc.ErrWebhookSignatureRequired) || strings.Contains(err.Error(), "invalid webhook signature") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"processed": true})
}

// DevCompletePayment manually marks a stub payment as succeeded for testing the
// webhook/confirmation flow without real YooKassa. It is a no-op route unless
// YOOKASSA_STUB_MODE is enabled — when disabled it returns 404 so it is
// invisible in production. The {id} path param is the provider payment id
// returned in the payment's confirmation_url (https://stub.local/payment/{id}).
func (h *PaymentHandler) DevCompletePayment(w http.ResponseWriter, r *http.Request) {
	if !h.stubMode {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
		return
	}
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "payment id is required"})
		return
	}
	payment, err := h.financeUC.CompleteStubPayment(r.Context(), id)
	if err != nil {
		if errors.Is(err, paymentdomain.ErrPaymentNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "payment not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to complete payment"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"payment": newFinancePaymentResponse(payment)})
}

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

func (h *PaymentHandler) AdminExportFinance(w http.ResponseWriter, r *http.Request) {
	reportType := r.URL.Query().Get("type")
	records, err := h.repo.ExportFinanceReport(r.Context(), reportType)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set("Content-Disposition", "attachment; filename=\""+reportType+".csv\"")
	_ = csv.NewWriter(w).WriteAll(records)
}

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

// AdminListRefunds serves GET /admin/finance/refunds with filters.
// Money amounts in the response are in kopecks (minor units).
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

// AdminApprovePayout serves POST /admin/finance/payouts/{id}/approve.
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

// AdminRejectPayout serves POST /admin/finance/payouts/{id}/reject.
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
