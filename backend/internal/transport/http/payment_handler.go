package http

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"evik/backend/internal/auth"
	paymentdomain "evik/backend/internal/domain/payment"
	"github.com/go-chi/chi/v5"
)

type PaymentHandler struct {
	repo  paymentdomain.Repository
	idGen interface{ NewID() string }
	clock interface{ Now() time.Time }
}

func NewPaymentHandler(
	repo paymentdomain.Repository,
	idGen interface{ NewID() string },
	clock interface{ Now() time.Time },
) *PaymentHandler {
	return &PaymentHandler{repo: repo, idGen: idGen, clock: clock}
}

type addCardRequest struct {
	CardNumber string `json:"card_number"`
	ExpMonth   int    `json:"exp_month"`
	ExpYear    int    `json:"exp_year"`
	Holder     string `json:"holder"`
	CVV        string `json:"cvv"`
	SetDefault bool   `json:"set_default"`
}

type applyPromocodeRequest struct {
	Code string `json:"code"`
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
	cvv := onlyDigits(req.CVV)
	holder := strings.TrimSpace(req.Holder)
	if len(cardNumber) < 13 || len(cardNumber) > 19 || !validLuhn(cardNumber) {
		return paymentdomain.PaymentMethod{}, errors.New("invalid card number")
	}
	if len(cvv) < 3 || len(cvv) > 4 {
		return paymentdomain.PaymentMethod{}, errors.New("invalid cvv")
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
