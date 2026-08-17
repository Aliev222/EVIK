package http

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"evik/backend/internal/auth"
	orderdomain "evik/backend/internal/domain/order"
	paymentdomain "evik/backend/internal/domain/payment"
)

// --- fakes ---

// fakeDebtPaymentRepo is a minimal paymentdomain.Repository used by the
// debt/receipt handler tests. It embeds the interface so unrelated methods are
// nil (never called by the handlers under test).
type fakeDebtPaymentRepo struct {
	paymentdomain.Repository
	listDebtFn    func(ctx context.Context, driverID string, limit int) ([]paymentdomain.DriverDebtTransaction, error)
	getPaymentFn  func(ctx context.Context, orderID string) (*paymentdomain.Payment, error)
	gotDriverID   string
	gotLimit      int
}

func (f *fakeDebtPaymentRepo) ListDebtTransactions(ctx context.Context, driverID string, limit int) ([]paymentdomain.DriverDebtTransaction, error) {
	f.gotDriverID = driverID
	f.gotLimit = limit
	return f.listDebtFn(ctx, driverID, limit)
}

func (f *fakeDebtPaymentRepo) GetPaymentByOrderID(ctx context.Context, orderID string) (*paymentdomain.Payment, error) {
	return f.getPaymentFn(ctx, orderID)
}

// fakeDebtOrderRepo is a minimal orderdomain.Repository for the receipt tests.
type fakeDebtOrderRepo struct {
	orderdomain.Repository
	order *orderdomain.Order
	// err is returned by GetByID when set (used to simulate a missing order).
	err        error
	details    *orderdomain.AdminOrderDetails
}

func (f *fakeDebtOrderRepo) GetByID(context.Context, string) (*orderdomain.Order, error) {
	if f.err != nil {
		return nil, f.err
	}
	if f.order == nil {
		return nil, orderdomain.ErrOrderNotFound
	}
	return f.order, nil
}

func (f *fakeDebtOrderRepo) GetAdminOrderDetails(context.Context, string) (*orderdomain.AdminOrderDetails, error) {
	if f.details == nil {
		return nil, orderdomain.ErrOrderNotFound
	}
	return f.details, nil
}

func newTestPaymentHandler(repo paymentdomain.Repository, orderRepo orderdomain.Repository) *PaymentHandler {
	return NewPaymentHandler(
		repo, nil, orderRepo, nil,
		&seqID{},
		fixedHTTPClock{now: time.Date(2026, 8, 15, 12, 0, 0, 0, time.UTC)},
		nil,
	)
}

func driverOrderDetails(driverID string) *orderdomain.AdminOrderDetails {
	completedAt := time.Date(2026, 8, 14, 18, 30, 0, 0, time.UTC)
	order := orderdomain.AdminOrderListItem{
		OrderID:          "order-cash-1",
		DriverID:         driverID,
		DriverName:       "Driver One",
		DriverPhone:      "+79990000002",
		Status:           "completed",
		PaymentMethod:    "cash",
		FinancialStatus:  "completed",
		PriceTotal:       800000,
		CommissionAmount: 120000,
		DriverAmount:     680000,
		CreatedAt:        time.Date(2026, 8, 14, 18, 0, 0, 0, time.UTC),
		CompletedAt:      &completedAt,
	}
	return &orderdomain.AdminOrderDetails{
		Order: order,
		FinancialBreakdown: orderdomain.AdminOrderFinancialBreakdown{
			TotalAmount:      800000,
			CommissionAmount: 120000,
			DriverAmount:     680000,
		},
	}
}

// --- GET /driver/wallet/debt ---

// ListDriverDebt returns the calling driver's cash-commission debt history with
// order_id, and only the calling driver's data is ever requested from the repo.
func TestListDriverDebt_ReturnsDriverDebtTransactionsWithOrderID(t *testing.T) {
	created := time.Date(2026, 8, 14, 18, 30, 0, 0, time.UTC)
	repo := &fakeDebtPaymentRepo{
		listDebtFn: func(_ context.Context, driverID string, _ int) ([]paymentdomain.DriverDebtTransaction, error) {
			if driverID != "driver-1" {
				t.Fatalf("ListDebtTransactions driverID = %q, want driver-1 (privacy: only own data)", driverID)
			}
			orderID := "order-cash-1"
			return []paymentdomain.DriverDebtTransaction{
				{
					ID:          "tx-debt-1",
					OrderID:     &orderID,
					Type:        paymentdomain.WalletTypeCashCommissionDebt,
					Direction:   paymentdomain.WalletDirectionCredit,
					Amount:      120000,
					Currency:    "RUB",
					Status:      paymentdomain.WalletTxStatusSucceeded,
					Description: "Tow Truck commission debt for cash order",
					OrderAmount: 800000,
					CreatedAt:   created,
				},
			}, nil
		},
	}
	h := newTestPaymentHandler(repo, &fakeDebtOrderRepo{})
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/driver/wallet/debt", "", "", "driver-1", auth.RoleDriver)

	h.ListDriverDebt(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	items, ok := body["transactions"].([]any)
	if !ok || len(items) != 1 {
		t.Fatalf("transactions = %#v, want 1 item", body["transactions"])
	}
	item := items[0].(map[string]any)
	if item["order_id"] != "order-cash-1" {
		t.Errorf("order_id = %v, want order-cash-1", item["order_id"])
	}
	if item["type"] != string(paymentdomain.WalletTypeCashCommissionDebt) {
		t.Errorf("type = %v, want cash_commission_debt", item["type"])
	}
	if item["amount"] != float64(120000) {
		t.Errorf("amount = %v, want 120000", item["amount"])
	}
	if item["order_amount"] != float64(800000) {
		t.Errorf("order_amount = %v, want 800000", item["order_amount"])
	}
	if body["accrued"] != float64(120000) {
		t.Errorf("accrued = %v, want 120000", body["accrued"])
	}
	if body["repaid"] != float64(0) {
		t.Errorf("repaid = %v, want 0", body["repaid"])
	}
	if repo.gotDriverID != "driver-1" {
		t.Errorf("repo received driverID %q, want driver-1", repo.gotDriverID)
	}
}

// ListDriverDebt includes debt_repayment (reductions) and rolls them into the
// repaid total.
func TestListDriverDebt_IncludesRepayments(t *testing.T) {
	created := time.Date(2026, 8, 14, 18, 30, 0, 0, time.UTC)
	repo := &fakeDebtPaymentRepo{
		listDebtFn: func(_ context.Context, _ string, _ int) ([]paymentdomain.DriverDebtTransaction, error) {
			orderA := "order-cash-1"
			orderB := "order-card-2"
			return []paymentdomain.DriverDebtTransaction{
				{
					ID: "tx-debt-1", OrderID: &orderA, Type: paymentdomain.WalletTypeCashCommissionDebt,
					Amount: 120000, Currency: "RUB", Status: paymentdomain.WalletTxStatusSucceeded,
					OrderAmount: 800000, CreatedAt: created,
				},
				{
					ID: "tx-repay-1", OrderID: &orderB, Type: paymentdomain.WalletTypeDebtRepayment,
					Amount: 50000, Currency: "RUB", Status: paymentdomain.WalletTxStatusSucceeded,
					OrderAmount: 700000, CreatedAt: created.Add(time.Hour),
				},
			}, nil
		},
	}
	h := newTestPaymentHandler(repo, &fakeDebtOrderRepo{})
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/driver/wallet/debt", "", "", "driver-1", auth.RoleDriver)

	h.ListDriverDebt(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	items := body["transactions"].([]any)
	if len(items) != 2 {
		t.Fatalf("transactions len = %d, want 2", len(items))
	}
	if body["accrued"] != float64(120000) {
		t.Errorf("accrued = %v, want 120000", body["accrued"])
	}
	if body["repaid"] != float64(50000) {
		t.Errorf("repaid = %v, want 50000", body["repaid"])
	}
}

// ListDriverDebt is unauthorized without a valid auth context.
func TestListDriverDebt_Unauthorized(t *testing.T) {
	h := newTestPaymentHandler(&fakeDebtPaymentRepo{}, &fakeDebtOrderRepo{})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/driver/wallet/debt", nil)

	h.ListDriverDebt(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

// --- GET /orders/{orderID}/receipt ---

// GetOrderReceipt returns a 200 for a cash order even though no payments row
// exists: the receipt is assembled from order data (task #7).
func TestGetOrderReceipt_CashOrderNoPaymentRow_Returns200(t *testing.T) {
	repo := &fakeDebtPaymentRepo{
		getPaymentFn: func(context.Context, string) (*paymentdomain.Payment, error) {
			return nil, paymentdomain.ErrPaymentNotFound
		},
	}
	orderRepo := &fakeDebtOrderRepo{
		order:   &orderdomain.Order{ID: "order-cash-1", UserID: "client-1", DriverID: strPtr("driver-1"), PaymentMethod: "cash"},
		details: driverOrderDetails("driver-1"),
	}
	h := newTestPaymentHandler(repo, orderRepo)
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-cash-1/receipt", "orderID", "order-cash-1", "driver-1", auth.RoleDriver)

	h.GetOrderReceipt(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("cash receipt status = %d, want 200 (not 404), body=%s", rec.Code, rec.Body.String())
	}
	if containsStr(rec.Body.String(), "payment not found") {
		t.Fatalf("cash receipt must not report 'payment not found': %s", rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body["order_id"] != "order-cash-1" {
		t.Errorf("order_id = %v", body["order_id"])
	}
	if body["payment_method"] != "cash" {
		t.Errorf("payment_method = %v, want cash", body["payment_method"])
	}
	if body["payment_status"] != "succeeded" {
		t.Errorf("payment_status = %v, want succeeded", body["payment_status"])
	}
	if body["price_total"] != float64(800000) {
		t.Errorf("price_total = %v, want 800000", body["price_total"])
	}
	if body["commission_amount"] != float64(120000) {
		t.Errorf("commission_amount = %v, want 120000", body["commission_amount"])
	}
	if body["driver_amount"] != float64(680000) {
		t.Errorf("driver_amount = %v, want 680000", body["driver_amount"])
	}
	if body["driver_id"] != "driver-1" {
		t.Errorf("driver_id = %v, want driver-1", body["driver_id"])
	}
}

// GetOrderReceipt for a card order keeps using the payment row when present.
func TestGetOrderReceipt_CardOrderUsesPaymentRow(t *testing.T) {
	paidAt := time.Date(2026, 8, 14, 18, 35, 0, 0, time.UTC)
	repo := &fakeDebtPaymentRepo{
		getPaymentFn: func(context.Context, string) (*paymentdomain.Payment, error) {
			return &paymentdomain.Payment{
				ID: "payment-card-1", Amount: 800000, Currency: "RUB",
				PaymentMethod: paymentdomain.PaymentMethodCard, Status: paymentdomain.PaymentStatusSucceeded,
				PaidAt: &paidAt,
			}, nil
		},
	}
	orderRepo := &fakeDebtOrderRepo{
		order:   &orderdomain.Order{ID: "order-card-1", UserID: "client-1", DriverID: strPtr("driver-1"), PaymentMethod: "card"},
		details: driverOrderDetails("driver-1"),
	}
	h := newTestPaymentHandler(repo, orderRepo)
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-card-1/receipt", "orderID", "order-card-1", "client-1", auth.RoleClient)

	h.GetOrderReceipt(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body["payment_id"] != "payment-card-1" {
		t.Errorf("payment_id = %v, want payment-card-1", body["payment_id"])
	}
	if body["payment_method"] != "card" {
		t.Errorf("payment_method = %v, want card", body["payment_method"])
	}
	if body["price_total"] != float64(800000) {
		t.Errorf("price_total = %v, want 800000 (order total)", body["price_total"])
	}
	if body["amount"] != float64(800000) {
		t.Errorf("amount = %v, want 800000 (from payment)", body["amount"])
	}
}

// GetOrderReceipt: a driver cannot view another driver's order (privacy).
func TestGetOrderReceipt_AnotherDriversOrder_Forbidden(t *testing.T) {
	repo := &fakeDebtPaymentRepo{}
	orderRepo := &fakeDebtOrderRepo{
		order: &orderdomain.Order{ID: "order-other", UserID: "client-1", DriverID: strPtr("driver-2")},
	}
	h := newTestPaymentHandler(repo, orderRepo)
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-other/receipt", "orderID", "order-other", "driver-1", auth.RoleDriver)

	h.GetOrderReceipt(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 for another driver's receipt", rec.Code)
	}
}

// GetOrderReceipt: a client cannot view an order they do not own.
func TestGetOrderReceipt_OtherClientsOrder_Forbidden(t *testing.T) {
	repo := &fakeDebtPaymentRepo{}
	orderRepo := &fakeDebtOrderRepo{
		order: &orderdomain.Order{ID: "order-other", UserID: "client-2", DriverID: strPtr("driver-1")},
	}
	h := newTestPaymentHandler(repo, orderRepo)
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-other/receipt", "orderID", "order-other", "client-1", auth.RoleClient)

	h.GetOrderReceipt(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 for another client's receipt", rec.Code)
	}
}

// GetOrderReceipt: a driver can view their own order's receipt (positive path).
func TestGetOrderReceipt_OwnCashOrder_DriverAllowed(t *testing.T) {
	repo := &fakeDebtPaymentRepo{
		getPaymentFn: func(context.Context, string) (*paymentdomain.Payment, error) {
			return nil, paymentdomain.ErrPaymentNotFound
		},
	}
	orderRepo := &fakeDebtOrderRepo{
		order:   &orderdomain.Order{ID: "order-cash-1", UserID: "client-1", DriverID: strPtr("driver-1"), PaymentMethod: "cash"},
		details: driverOrderDetails("driver-1"),
	}
	h := newTestPaymentHandler(repo, orderRepo)
	rec := httptest.NewRecorder()
	req := requestWithRoute(http.MethodGet, "/api/v1/orders/order-cash-1/receipt", "orderID", "order-cash-1", "driver-1", auth.RoleDriver)

	h.GetOrderReceipt(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("own cash order receipt status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
}

func strPtr(s string) *string { return &s }

func containsStr(haystack, needle string) bool {
	return strings.Contains(haystack, needle)
}
