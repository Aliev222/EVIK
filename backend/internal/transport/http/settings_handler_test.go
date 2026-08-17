package http

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"evik/backend/internal/domain/settings"
)

type fakeSettingsRepository struct {
	upserted  map[string]any
	upsertErr error
}

func (f *fakeSettingsRepository) List(context.Context) ([]settings.Setting, error) {
	return nil, nil
}

func (f *fakeSettingsRepository) Upsert(_ context.Context, key string, value any) error {
	if f.upsertErr != nil {
		return f.upsertErr
	}
	if f.upserted == nil {
		f.upserted = map[string]any{}
	}
	f.upserted[key] = value
	return nil
}

// updateSettings performs an Update request through the production handler with
// the given JSON body and returns the recorder and the repository.
func updateSettings(t *testing.T, repo *fakeSettingsRepository, body string) *httptest.ResponseRecorder {
	t.Helper()
	h := NewSettingsHandler(repo)
	req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/settings", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.Update(rec, req)
	return rec
}

func TestSettingsUpdate_ValidValuesArePersisted(t *testing.T) {
	cases := []struct {
		name     string
		key      string
		body     string
		expected any
	}{
		{"commission percent as string", "commission_percent", `{"key":"commission_percent","value":"15.00"}`, "15.00"},
		{"commission percent as number", "commission_percent", `{"key":"commission_percent","value":20}`, float64(20)},
		{"commission percent zero", "commission_percent", `{"key":"commission_percent","value":0}`, float64(0)},
		{"commission percent upper bound", "commission_percent", `{"key":"commission_percent","value":100}`, float64(100)},
		{"daily subscription price", "driver_subscription_daily_price", `{"key":"driver_subscription_daily_price","value":"50000"}`, "50000"},
		{"weekly subscription price", "driver_subscription_weekly_price", `{"key":"driver_subscription_weekly_price","value":250000}`, float64(250000)},
		{"monthly subscription price", "driver_subscription_monthly_price", `{"key":"driver_subscription_monthly_price","value":"900000"}`, "900000"},
		{"min withdrawal", "min_withdrawal_kopecks", `{"key":"min_withdrawal_kopecks","value":100000}`, float64(100000)},
		{"max cash debt", "max_cash_debt_kopecks", `{"key":"max_cash_debt_kopecks","value":100000}`, float64(100000)},
		{"max cash debt zero disables gate", "max_cash_debt_kopecks", `{"key":"max_cash_debt_kopecks","value":0}`, float64(0)},
		{"offer timeout", "offer_timeout_seconds", `{"key":"offer_timeout_seconds","value":30}`, float64(30)},
		{"dispatch round limit", "dispatch_round_limit", `{"key":"dispatch_round_limit","value":"3"}`, "3"},
		{"payout mode", "payout_mode", `{"key":"payout_mode","value":"manual"}`, "manual"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			repo := &fakeSettingsRepository{}
			rec := updateSettings(t, repo, tc.body)
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
			}
			got, ok := repo.upserted[tc.key]
			if !ok {
				t.Fatalf("key %q was not persisted", tc.key)
			}
			if got != tc.expected {
				t.Fatalf("persisted value = %#v, want %#v", got, tc.expected)
			}
		})
	}
}

func TestSettingsUpdate_RejectsUnknownKey(t *testing.T) {
	repo := &fakeSettingsRepository{}
	rec := updateSettings(t, repo, `{"key":"some_garbage_key","value":1}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "some_garbage_key") {
		t.Fatalf("body should mention the key, got %s", rec.Body.String())
	}
	if len(repo.upserted) != 0 {
		t.Fatalf("unknown key should not be persisted, got %#v", repo.upserted)
	}
}

func TestSettingsUpdate_RejectsEmptyKey(t *testing.T) {
	repo := &fakeSettingsRepository{}
	rec := updateSettings(t, repo, `{"key":"","value":1}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body=%s)", rec.Code, rec.Body.String())
	}
	if len(repo.upserted) != 0 {
		t.Fatalf("empty key should not be persisted, got %#v", repo.upserted)
	}
}

func TestSettingsUpdate_RejectsInvalidBody(t *testing.T) {
	repo := &fakeSettingsRepository{}
	rec := updateSettings(t, repo, `{not json`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestSettingsUpdate_MoneyKeys(t *testing.T) {
	cases := []struct {
		name string
		body string
	}{
		{"zero price rejects", `{"key":"driver_subscription_daily_price","value":0}`},
		{"negative price rejects", `{"key":"driver_subscription_weekly_price","value":-100}`},
		{"fractional price rejects", `{"key":"driver_subscription_monthly_price","value":50000.5}`},
		{"non-numeric price rejects", `{"key":"driver_subscription_daily_price","value":"abc"}`},
		{"null price rejects", `{"key":"driver_subscription_daily_price","value":null}`},
		{"bool price rejects", `{"key":"driver_subscription_daily_price","value":true}`},
		{"string negative min withdrawal rejects", `{"key":"min_withdrawal_kopecks","value":"-10"}`},
		{"negative max cash debt rejects", `{"key":"max_cash_debt_kopecks","value":-100}`},
		{"fractional max cash debt rejects", `{"key":"max_cash_debt_kopecks","value":1000.5}`},
		{"non-numeric max cash debt rejects", `{"key":"max_cash_debt_kopecks","value":"abc"}`},
		{"null max cash debt rejects", `{"key":"max_cash_debt_kopecks","value":null}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			repo := &fakeSettingsRepository{}
			rec := updateSettings(t, repo, tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body=%s)", rec.Code, rec.Body.String())
			}
			if len(repo.upserted) != 0 {
				t.Fatalf("invalid money value should not be persisted, got %#v", repo.upserted)
			}
		})
	}
}

func TestSettingsUpdate_CommissionPercent(t *testing.T) {
	cases := []struct {
		name string
		body string
	}{
		{"below zero rejects", `{"key":"commission_percent","value":-1}`},
		{"above 100 rejects", `{"key":"commission_percent","value":101}`},
		{"negative string rejects", `{"key":"commission_percent","value":"-5"}`},
		{"fractional rejects", `{"key":"commission_percent","value":10.5}`},
		{"non-numeric rejects", `{"key":"commission_percent","value":"abc"}`},
		{"null rejects", `{"key":"commission_percent","value":null}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			repo := &fakeSettingsRepository{}
			rec := updateSettings(t, repo, tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body=%s)", rec.Code, rec.Body.String())
			}
			if len(repo.upserted) != 0 {
				t.Fatalf("invalid commission should not be persisted, got %#v", repo.upserted)
			}
		})
	}
}

func TestSettingsUpdate_OtherNumericKeys(t *testing.T) {
	cases := []struct {
		name string
		key  string
		body string
	}{
		{"negative offer timeout rejects", "offer_timeout_seconds", `{"key":"offer_timeout_seconds","value":-1}`},
		{"non-numeric offer timeout rejects", "offer_timeout_seconds", `{"key":"offer_timeout_seconds","value":"abc"}`},
		{"fractional offer timeout rejects", "offer_timeout_seconds", `{"key":"offer_timeout_seconds","value":2.5}`},
		{"negative round limit rejects", "dispatch_round_limit", `{"key":"dispatch_round_limit","value":-3}`},
		{"string negative round limit rejects", "dispatch_round_limit", `{"key":"dispatch_round_limit","value":"-3"}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			repo := &fakeSettingsRepository{}
			rec := updateSettings(t, repo, tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body=%s)", rec.Code, rec.Body.String())
			}
			if len(repo.upserted) != 0 {
				t.Fatalf("invalid value for %s should not be persisted, got %#v", tc.key, repo.upserted)
			}
		})
	}
}

func TestSettingsUpdate_PayoutMode(t *testing.T) {
	valid := []string{`{"key":"payout_mode","value":"auto"}`, `{"key":"payout_mode","value":"manual"}`}
	for _, body := range valid {
		repo := &fakeSettingsRepository{}
		rec := updateSettings(t, repo, body)
		if rec.Code != http.StatusOK {
			t.Fatalf("payout_mode %s: status = %d, want 200 (body=%s)", body, rec.Code, rec.Body.String())
		}
	}
	invalid := []struct {
		name string
		body string
	}{
		{"unknown mode", `{"key":"payout_mode","value":"fast"}`},
		{"number not string", `{"key":"payout_mode","value":5}`},
		{"null", `{"key":"payout_mode","value":null}`},
	}
	for _, tc := range invalid {
		t.Run(tc.name, func(t *testing.T) {
			repo := &fakeSettingsRepository{}
			rec := updateSettings(t, repo, tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400 (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestSettingsUpdate_ErrorResponseMentionsKeyAndProblem(t *testing.T) {
	repo := &fakeSettingsRepository{}
	rec := updateSettings(t, repo, `{"key":"driver_subscription_daily_price","value":0}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	msg, _ := payload["error"].(string)
	if !strings.Contains(msg, "driver_subscription_daily_price") {
		t.Fatalf("error should mention the key, got %q", msg)
	}
	if !strings.Contains(msg, "0") || !strings.Contains(msg, "greater than 0") {
		t.Fatalf("error should explain the violation, got %q", msg)
	}
}

func TestSettingsUpdate_RepositoryError(t *testing.T) {
	repo := &fakeSettingsRepository{upsertErr: context.Canceled}
	rec := updateSettings(t, repo, `{"key":"commission_percent","value":15}`)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500 (body=%s)", rec.Code, rec.Body.String())
	}
}
