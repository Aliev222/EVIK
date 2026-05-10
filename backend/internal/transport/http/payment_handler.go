package http

import (
	"encoding/csv"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"evik/backend/internal/auth"
	paymentdomain "evik/backend/internal/domain/payment"
	paymentuc "evik/backend/internal/usecase/payment"
	"github.com/go-chi/chi/v5"
)

type PaymentHandler struct {
	repo      paymentdomain.Repository
	financeUC *paymentuc.FinanceUseCase
	idGen     interface{ NewID() string }
	clock     interface{ Now() time.Time }
}

func NewPaymentHandler(
	repo paymentdomain.Repository,
	financeUC *paymentuc.FinanceUseCase,
	idGen interface{ NewID() string },
	clock interface{ Now() time.Time },
) *PaymentHandler {
	return &PaymentHandler{repo: repo, financeUC: financeUC, idGen: idGen, clock: clock}
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
	ID        string `json:"id"`
	Brand     string `json:"brand"`
	Last4     string `json:"last4"`
	ExpMonth  int    `json:"exp_month"`
	ExpYear   int    `json:"exp_year"`
	Holder    string `json:"holder"`
	IsDefault bool   `json:"is_default"`
	CreatedAt string `json:"created_at"`
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
	transactions, err := h.repo.ListTransactions(r.Context(), userID, 20)
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
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"payment": newFinancePaymentResponse(payment)})
}

func (h *PaymentHandler) GetOrderPaymentStatus(w http.ResponseWriter, r *http.Request) {
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
	payment, err := h.repo.GetPaymentByOrderID(r.Context(), chi.URLParam(r, "orderID"))
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		return
	}
	commission := payment.Amount * 15 / 100
	writeJSON(w, http.StatusOK, map[string]any{
		"order_id":      payment.OrderID,
		"payment_id":    payment.ID,
		"amount":        payment.Amount,
		"currency":      payment.Currency,
		"commission":    commission,
		"driver_amount": payment.Amount - commission,
		"status":        payment.Status,
		"paid_at":       payment.PaidAt,
	})
}

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
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"processed": true})
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
	txs, _ := h.repo.ListWalletTransactions(r.Context(), driverID, 10)
	payouts, _ := h.repo.ListPayouts(r.Context(), driverID, 10)
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
	idempotencyKey := r.Header.Get("Idempotency-Key")
	if idempotencyKey == "" {
		idempotencyKey = r.Header.Get("X-Idempotency-Key")
	}
	payout, err := h.financeUC.RequestDriverPayout(r.Context(), driverID, req.Amount, idempotencyKey)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
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
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"payment": newFinancePaymentResponse(payment)})
}

func (h *PaymentHandler) GetDriverSubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "unknown"})
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

func (h *PaymentHandler) AddCard(w http.ResponseWriter, r *http.Request) {
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
		ID:        method.ID,
		Brand:     string(method.Brand),
		Last4:     method.Last4,
		ExpMonth:  method.ExpMonth,
		ExpYear:   method.ExpYear,
		Holder:    method.Holder,
		IsDefault: method.IsDefault,
		CreatedAt: method.CreatedAt.Format(time.RFC3339),
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
