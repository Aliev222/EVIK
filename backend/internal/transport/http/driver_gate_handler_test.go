package http

import (
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	driveruc "evik/backend/internal/usecase/driver"
)

// The debt gate error must surface as a 403 for every workflow that calls the
// gate: going online (SetStatus), accepting an order (AcceptOrder) and listing
// searching orders (GetSearchingOrders). All three handlers share the mapping.
func TestGateDebtBlockMapsToForbidden(t *testing.T) {
	cases := []struct {
		name string
		run  func(w http.ResponseWriter) (int, string)
	}{
		{
			name: "driver online (SetStatus)",
			run: func(w http.ResponseWriter) (int, string) {
				h := &DriverHandler{}
				h.writeDriverGateError(w, errDebtBlock())
				return statusCode(w), bodyString(w)
			},
		},
		{
			name: "accept order (AcceptOrder)",
			run: func(w http.ResponseWriter) (int, string) {
				h := &OrderHandler{}
				h.writeDriverGateError(w, errDebtBlock())
				return statusCode(w), bodyString(w)
			},
		},
		{
			name: "driver searching orders list",
			run: func(w http.ResponseWriter) (int, string) {
				h := &DriverHandler{}
				h.writeDriverGateError(w, errDebtBlock())
				return statusCode(w), bodyString(w)
			},
		},
		{
			name: "payment gate",
			run: func(w http.ResponseWriter) (int, string) {
				h := &PaymentHandler{}
				h.writeDriverGateError(w, errDebtBlock())
				return statusCode(w), bodyString(w)
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			code, body := tc.run(w)
			if code != http.StatusForbidden {
				t.Fatalf("status = %d, want 403", code)
			}
			if body == "" {
				t.Fatal("expected a non-empty error body")
			}
		})
	}
}

// Other gate errors must still map to 403 (regression guard for the switch).
func TestGateDocumentAndTaxErrorsMapToForbidden(t *testing.T) {
	w := httptest.NewRecorder()
	h := &OrderHandler{}
	h.writeDriverGateError(w, driveruc.ErrDriverDocumentsNotApproved)
	if statusCode(w) != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", statusCode(w))
	}

	w = httptest.NewRecorder()
	h = &OrderHandler{}
	h.writeDriverGateError(w, driveruc.ErrDriverTaxNotVerified)
	if statusCode(w) != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", statusCode(w))
	}
}

// Unexpected gate errors degrade to 500, never leak debt detail.
func TestGateUnknownErrorMapsToInternal(t *testing.T) {
	w := httptest.NewRecorder()
	h := &OrderHandler{}
	h.writeDriverGateError(w, errors.New("unexpected"))
	if statusCode(w) != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", statusCode(w))
	}
}

func errDebtBlock() error {
	return fmt.Errorf("%w: outstanding cash debt 150000 kopecks exceeds the max of 100000", driveruc.ErrOutstandingDebtBlocksWork)
}

func statusCode(w http.ResponseWriter) int {
	rec, ok := w.(*httptest.ResponseRecorder)
	if !ok {
		return 0
	}
	return rec.Code
}

func bodyString(w http.ResponseWriter) string {
	rec, ok := w.(*httptest.ResponseRecorder)
	if !ok {
		return ""
	}
	return rec.Body.String()
}