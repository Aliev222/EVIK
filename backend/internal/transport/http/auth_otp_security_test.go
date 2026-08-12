package http

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"evik/backend/internal/auth"
	userdomain "evik/backend/internal/domain/user"
)

// OTP lifecycle, rate limiting and adversarial-input coverage for the auth
// endpoints. OTP tests exercise the REAL RequestOTP/VerifyOTP handlers with
// debugMode=false so ConsumePhoneOTP (expiry / one-time consumption) is real;
// the OTP code is pinned via fixedOTPCode so verification is deterministic.

const testFixedOTP = "424242" // not in knownWeakOTPCodes

type mutableClock struct {
	now time.Time
}

func (c *mutableClock) Now() time.Time { return c.now }

func newOTPHandler(t *testing.T, clock interface{ Now() time.Time }) (*AuthHandler, *fakeUserRepository) {
	t.Helper()
	repo := newFakeUserRepository()
	tokens := newTokens(time.Minute)
	handler := NewAuthHandler(tokens, repo, "admin", "admin-password", &seqID{}, clock, false, testFixedOTP, false, false)
	return handler, repo
}

func sendOTPRequest(handler *AuthHandler, phone, role string) *httptest.ResponseRecorder {
	body := `{"phone":"` + phone + `","role":"` + role + `"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", bytes.NewBufferString(body))
	rec := httptest.NewRecorder()
	handler.RequestOTP(rec, req)
	return rec
}

func sendOTPVerify(handler *AuthHandler, phone, role, code string) *httptest.ResponseRecorder {
	body := `{"phone":"` + phone + `","role":"` + role + `","code":"` + code + `","full_name":"Auto User"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/verify", bytes.NewBufferString(body))
	rec := httptest.NewRecorder()
	handler.VerifyOTP(rec, req)
	return rec
}

func tokensFromBody(t *testing.T, body []byte) (string, string) {
	t.Helper()
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		t.Fatalf("decode response: %v (body=%s)", err, body)
	}
	toks := payload["tokens"].(map[string]any)
	access, _ := toks["access_token"].(string)
	refresh, _ := toks["refresh_token"].(string)
	return access, refresh
}

// --- OTP lifecycle ---

func TestAuthOTP_RequestPersistsAndVerifySucceedsAndIssuesTokens(t *testing.T) {
	clock := &mutableClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	handler, repo := newOTPHandler(t, clock)

	if rec := sendOTPRequest(handler, "+79990000021", "client"); rec.Code != http.StatusAccepted {
		t.Fatalf("request status = %d, body = %s", rec.Code, rec.Body.String())
	}
	if len(repo.otps) != 1 {
		t.Fatalf("otps stored = %d, want 1", len(repo.otps))
	}

	rec := sendOTPVerify(handler, "+79990000021", "client", testFixedOTP)
	if rec.Code != http.StatusOK {
		t.Fatalf("verify status = %d, body = %s", rec.Code, rec.Body.String())
	}
	access, refresh := tokensFromBody(t, rec.Body.Bytes())
	if access == "" || refresh == "" {
		t.Fatal("expected access and refresh tokens in response")
	}
	var anyUserFound bool
	for _, u := range repo.users {
		if u.Phone == "+79990000021" && u.Role == auth.RoleClient && u.Status == userdomain.StatusActive {
			anyUserFound = true
		}
	}
	if !anyUserFound {
		t.Fatal("OTP verification did not auto-create the user")
	}
}

func TestAuthOTP_WrongCodeRejected(t *testing.T) {
	clock := &mutableClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	handler, repo := newOTPHandler(t, clock)
	sendOTPRequest(handler, "+79990000022", "client")

	rec := sendOTPVerify(handler, "+79990000022", "client", "123456")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
	if len(repo.users) != 0 {
		t.Fatal("wrong code must not auto-create a user")
	}
}

func TestAuthOTP_ReplayConsumedCodeRejected(t *testing.T) {
	clock := &mutableClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	handler, repo := newOTPHandler(t, clock)
	sendOTPRequest(handler, "+79990000023", "client")

	if rec := sendOTPVerify(handler, "+79990000023", "client", testFixedOTP); rec.Code != http.StatusOK {
		t.Fatalf("first verify = %d, body = %s", rec.Code, rec.Body.String())
	}
	// The same (already consumed) code must be rejected on reuse.
	if rec := sendOTPVerify(handler, "+79990000023", "client", testFixedOTP); rec.Code != http.StatusUnauthorized {
		t.Fatalf("replay verify = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
	if len(repo.users) != 1 {
		t.Fatalf("users = %d, want exactly 1", len(repo.users))
	}
}

func TestAuthOTP_ExpiredCodeRejected(t *testing.T) {
	clock := &mutableClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	handler, repo := newOTPHandler(t, clock)
	sendOTPRequest(handler, "+79990000024", "client")

	// Advance beyond the 10-minute lifetime and try the correct code.
	clock.now = clock.now.Add(11 * time.Minute)
	rec := sendOTPVerify(handler, "+79990000024", "client", testFixedOTP)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
	if len(repo.users) != 0 {
		t.Fatal("expired code must not create a user")
	}
}

func TestAuthOTP_CodeForOtherPhoneRejected(t *testing.T) {
	clock := &mutableClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	handler, _ := newOTPHandler(t, clock)
	sendOTPRequest(handler, "+79990000025", "client")

	// Same code, different phone — must fail (the stored hash is bound to the phone).
	if rec := sendOTPVerify(handler, "+79990000099", "client", testFixedOTP); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestAuthOTP_CodeForOtherRoleRejected(t *testing.T) {
	clock := &mutableClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	handler, _ := newOTPHandler(t, clock)
	sendOTPRequest(handler, "+79990000026", "client")

	if rec := sendOTPVerify(handler, "+79990000026", "driver", testFixedOTP); rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestAuthOTP_WeakCodeRejectedInProduction(t *testing.T) {
	clock := &mutableClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	repo := newFakeUserRepository()
	handler := NewAuthHandler(newTokens(time.Minute), repo, "admin", "admin-password", &seqID{}, clock, false, testFixedOTP, true, false)
	sendOTPRequest(handler, "+79990000027", "client")

	// A trivially guessable code must be rejected outright in production.
	if rec := sendOTPVerify(handler, "+79990000027", "client", "123456"); rec.Code != http.StatusUnauthorized {
		t.Fatalf("weak code status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
	}
	// A strong code that actually matches still works in production.
	if rec := sendOTPVerify(handler, "+79990000027", "client", testFixedOTP); rec.Code != http.StatusOK {
		t.Fatalf("strong code status = %d, want 200 (body=%s)", rec.Code, rec.Body.String())
	}
}

// --- Rate limiting (real middleware factory + real router wiring) ---

func TestAuthOTP_RateLimit_ExhaustsAfterThreePerPhone(t *testing.T) {
	clock := fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	router := newRealRouter(newTokens(time.Minute), seededUsers(), clock)
	want := []int{http.StatusAccepted, http.StatusAccepted, http.StatusAccepted, http.StatusTooManyRequests}
	for i, expected := range want {
		rec := doRequestJSON(router, http.MethodPost, "/api/v1/auth/otp/request", `{"phone":"+79990000031","role":"client"}`)
		if rec.Code != expected {
			t.Fatalf("call #%d: status = %d, want %d (body=%s)", i+1, rec.Code, expected, rec.Body.String())
		}
	}
}

func TestAuthOTP_RateLimit_IsPerPhoneNotGlobal(t *testing.T) {
	router := newFocusedSecurityRouter(newTokens(time.Minute), NewRateLimiter(), probeOK)
	// Exhaust phone A.
	for i := 0; i < 3; i++ {
		rec := doRequestJSON(router, http.MethodPost, "/api/v1/auth/otp/request", `{"phone":"+79990000032","role":"client"}`)
		if rec.Code != http.StatusOK {
			t.Fatalf("phone A call #%d: status = %d, want 200", i+1, rec.Code)
		}
	}
	if rec := doRequestJSON(router, http.MethodPost, "/api/v1/auth/otp/request", `{"phone":"+79990000032","role":"client"}`); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("phone A 4th call: status = %d, want 429", rec.Code)
	}
	// Phone B still has its own budget.
	if rec := doRequestJSON(router, http.MethodPost, "/api/v1/auth/otp/request", `{"phone":"+79990000033","role":"client"}`); rec.Code != http.StatusOK {
		t.Fatalf("phone B call: status = %d, want 200", rec.Code)
	}
}

// TestAuthOTP_RateLimit_PhoneVariantBypass guards against rate-limit evasion by
// phone-format variants. RateLimitByPhone buckets on normalizePhone(...) so all
// spellings of the same number ('+79990000001', '89990000001', '9990000001',
// '+7 (999) 000-00-01') collapse to one +7... key and share the 3/min bucket.
func TestAuthOTP_RateLimit_PhoneVariantBypass(t *testing.T) {
	router := newFocusedSecurityRouter(newTokens(time.Minute), NewRateLimiter(), probeOK)
	variants := []string{"+79990000001", "89990000001", "9990000001", "+7 (999) 000-00-01"}
	// All four raw spellings of the SAME number must share one bucket: the
	// 3/min per-phone cap is reached on the 4th request regardless of format.
	for i, phone := range variants {
		want := http.StatusOK
		if i == 3 {
			want = http.StatusTooManyRequests
		}
		rec := doRequestJSON(router, http.MethodPost, "/api/v1/auth/otp/request", `{"phone":"`+phone+`","role":"client"}`)
		if rec.Code != want {
			t.Fatalf("variant %q (call #%d): status = %d, want %d (body=%s)", phone, i+1, rec.Code, want, rec.Body.String())
		}
	}
}

// --- Adversarial inputs: no 500s, no panics — proper 4xx validation ---

func TestAuthAdversarial_RegisterRejectsMaliciousInput(t *testing.T) {
	clock := fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	handler := NewAuthHandler(newTokens(time.Minute), newFakeUserRepository(), "admin", "admin-password", &seqID{}, clock, false, testFixedOTP, false, false)

	hugeDigits := make([]byte, 600)
	for i := range hugeDigits {
		hugeDigits[i] = '7'
	}
	hugeName := make([]byte, 200)
	for i := range hugeName {
		hugeName[i] = 'n'
	}

	cases := []struct {
		name, body string
	}{
		{"role outside enum", `{"phone":"+79990000041","full_name":"A","role":"superadmin","password":"password1"}`},
		{"empty phone", `{"phone":"","full_name":"A","role":"client","password":"password1"}`},
		{"unicode phone", `{"phone":"📱📱📱","full_name":"A","role":"client","password":"password1"}`},
		{"600-digit phone", `{"phone":"` + string(hugeDigits) + `","full_name":"A","role":"client","password":"password1"}`},
		{"short password", `{"phone":"+79990000042","full_name":"A","role":"client","password":"short"}`},
		{"empty name", `{"phone":"+79990000042","full_name":"  ","role":"client","password":"password1"}`},
		{"garbage json", `{not json`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := doRequestJSON(http.HandlerFunc(handler.Register), http.MethodPost, "/api/v1/auth/register", tc.body)
			if rec.Code == http.StatusInternalServerError || rec.Code == 0 {
				t.Fatalf("status = %d (500/panic), body = %s", rec.Code, rec.Body.String())
			}
		})
	}

	// A very long (but non-empty) name is validated gracefully, never a 500.
	rec := doRequestJSON(http.HandlerFunc(handler.Register), http.MethodPost, "/api/v1/auth/register",
		`{"phone":"+79990000043","full_name":"`+string(hugeName)+`","role":"client","password":"password1"}`)
	if rec.Code == http.StatusInternalServerError {
		t.Fatalf("long name produced 500: %s", rec.Body.String())
	}
}

func TestAuthAdversarial_OTPRejectsMaliciousInput(t *testing.T) {
	clock := fixedHTTPClock{now: time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)}
	handler := NewAuthHandler(newTokens(time.Minute), newFakeUserRepository(), "admin", "admin-password", &seqID{}, clock, false, testFixedOTP, false, false)

	reqCases := []struct {
		name, body string
	}{
		{"empty phone", `{"phone":"","role":"client"}`},
		{"role admin on otp", `{"phone":"+79990000051","role":"admin"}`},
		{"unicode phone", `{"phone":"+++ %s","role":"client"}`},
	}
	for _, tc := range reqCases {
		t.Run("request/"+tc.name, func(t *testing.T) {
			rec := doRequestJSON(http.HandlerFunc(handler.RequestOTP), http.MethodPost, "/api/v1/auth/otp/request", tc.body)
			if rec.Code == http.StatusInternalServerError {
				t.Fatalf("status = 500, body = %s", rec.Body.String())
			}
		})
	}

	verCases := []struct {
		name, body string
	}{
		{"unicode code", `{"phone":"+79990000052","role":"client","code":"абвгде"}`},
		{"seven digit code", `{"phone":"+79990000052","role":"client","code":"4242427"}`},
		{"short code", `{"phone":"+79990000052","role":"client","code":"42"}`},
		{"empty code", `{"phone":"+79990000052","role":"client","code":""}`},
		{"role superadmin", `{"phone":"+79990000052","role":"superadmin","code":"424242"}`},
	}
	for _, tc := range verCases {
		t.Run("verify/"+tc.name, func(t *testing.T) {
			rec := doRequestJSON(http.HandlerFunc(handler.VerifyOTP), http.MethodPost, "/api/v1/auth/otp/verify", tc.body)
			if rec.Code == http.StatusInternalServerError {
				t.Fatalf("status = 500, body = %s", rec.Body.String())
			}
		})
	}
}

// compile-time guard: fakeUserRepository must satisfy the user Repository
// contract used by every auth handler.
var _ userdomain.Repository = (*fakeUserRepository)(nil)
