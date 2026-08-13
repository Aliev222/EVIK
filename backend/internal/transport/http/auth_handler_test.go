package http

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"evik/backend/internal/auth"
	userdomain "evik/backend/internal/domain/user"
)

func TestAuthRegisterIssuesRealUserSubjectAndRefreshSession(t *testing.T) {
	repo := newFakeUserRepository()
	clock := fixedHTTPClock{now: time.Date(2026, 5, 11, 12, 0, 0, 0, time.UTC)}
	tokens := auth.NewTokenManager("test-secret-test-secret-test-secret", time.Minute, time.Hour)
	handler := NewAuthHandler(tokens, repo, "admin", "admin-password", &seqID{}, clock, true, "", false, false)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewBufferString(`{
		"phone":"+79990000001",
		"full_name":"Client One",
		"role":"client",
		"password":"password1"
	}`))
	handler.Register(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	userPayload := payload["user"].(map[string]any)
	if userPayload["id"] == "" {
		t.Fatal("expected real user id in response")
	}
	if len(repo.sessions) != 1 {
		t.Fatalf("sessions = %d, want 1", len(repo.sessions))
	}
}

func TestAuthRefreshRotatesStoredSession(t *testing.T) {
	repo := newFakeUserRepository()
	clock := fixedHTTPClock{now: time.Date(2026, 5, 11, 12, 0, 0, 0, time.UTC)}
	tokens := auth.NewTokenManager("test-secret-test-secret-test-secret", time.Minute, time.Hour)
	handler := NewAuthHandler(tokens, repo, "admin", "admin-password", &seqID{}, clock, true, "", false, false)
	_, refreshToken, err := handler.issueTokens(context.Background(), "user-1", auth.RoleClient)
	if err != nil {
		t.Fatalf("issue tokens: %v", err)
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh", bytes.NewBufferString(`{"refresh_token":"`+refreshToken+`"}`))
	handler.Refresh(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	revoked := 0
	for _, session := range repo.sessions {
		if session.RevokedAt != nil {
			revoked++
		}
	}
	if revoked != 1 || len(repo.sessions) != 2 {
		t.Fatalf("expected one revoked old session and one new session, sessions=%d revoked=%d", len(repo.sessions), revoked)
	}
}

func TestAuthUpsertDeviceTokenRequiresMatchingRole(t *testing.T) {
	repo := newFakeUserRepository()
	clock := fixedHTTPClock{now: time.Date(2026, 5, 11, 12, 0, 0, 0, time.UTC)}
	tokens := auth.NewTokenManager("test-secret-test-secret-test-secret", time.Minute, time.Hour)
	handler := NewAuthHandler(tokens, repo, "admin", "admin-password", &seqID{}, clock, true, "", false, false)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices/fcm-token", bytes.NewBufferString(`{
		"fcm_token":"fcm-token-1",
		"role":"client",
		"platform":"android",
		"app_version":"1.0.0+1"
	}`))
	req = req.WithContext(withAuth(req.Context(), "user-1", auth.RoleDriver))
	handler.UpsertDeviceToken(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	if len(repo.deviceTokens) != 0 {
		t.Fatalf("device tokens = %d, want 0", len(repo.deviceTokens))
	}
}

func TestAuthUpsertDeviceTokenStoresTokenForAuthenticatedRole(t *testing.T) {
	repo := newFakeUserRepository()
	clock := fixedHTTPClock{now: time.Date(2026, 5, 11, 12, 0, 0, 0, time.UTC)}
	tokens := auth.NewTokenManager("test-secret-test-secret-test-secret", time.Minute, time.Hour)
	handler := NewAuthHandler(tokens, repo, "admin", "admin-password", &seqID{}, clock, true, "", false, false)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices/fcm-token", bytes.NewBufferString(`{
		"fcm_token":"fcm-token-1",
		"role":"driver",
		"platform":"android",
		"app_version":"1.0.0+1"
	}`))
	req = req.WithContext(withAuth(req.Context(), "user-1", auth.RoleDriver))
	handler.UpsertDeviceToken(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	token := repo.deviceTokens["fcm-token-1"]
	if token == nil || token.UserID != "user-1" || token.Role != auth.RoleDriver {
		t.Fatalf("stored token = %#v", token)
	}
}

func TestAuthOTPUsesConfiguredFixedCode(t *testing.T) {
	repo := newFakeUserRepository()
	clock := fixedHTTPClock{now: time.Date(2026, 5, 11, 12, 0, 0, 0, time.UTC)}
	tokens := auth.NewTokenManager("test-secret-test-secret-test-secret", time.Minute, time.Hour)
	handler := NewAuthHandler(tokens, repo, "admin", "admin-password", &seqID{}, clock, false, "123456", false, false)

	requestRec := httptest.NewRecorder()
	requestReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", bytes.NewBufferString(`{
		"phone":"+79990000003",
		"role":"client"
	}`))
	handler.RequestOTP(requestRec, requestReq)
	if requestRec.Code != http.StatusAccepted {
		t.Fatalf("request status = %d, body = %s", requestRec.Code, requestRec.Body.String())
	}
	if bytes.Contains(requestRec.Body.Bytes(), []byte("debug_otp")) {
		t.Fatalf("fixed code leaked in production-style response: %s", requestRec.Body.String())
	}

	verifyRec := httptest.NewRecorder()
	verifyReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/verify", bytes.NewBufferString(`{
		"phone":"+79990000003",
		"role":"client",
		"code":"123456",
		"full_name":"Client Three"
	}`))
	handler.VerifyOTP(verifyRec, verifyReq)
	if verifyRec.Code != http.StatusOK {
		t.Fatalf("verify status = %d, body = %s", verifyRec.Code, verifyRec.Body.String())
	}
}

func TestAuthOTPDoesNotExposeConfiguredFixedCode(t *testing.T) {
	repo := newFakeUserRepository()
	clock := fixedHTTPClock{now: time.Date(2026, 5, 11, 12, 0, 0, 0, time.UTC)}
	tokens := auth.NewTokenManager("test-secret-test-secret-test-secret", time.Minute, time.Hour)
	handler := NewAuthHandler(tokens, repo, "admin", "admin-password", &seqID{}, clock, true, "123456", false, false)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", bytes.NewBufferString(`{
		"phone":"+79990000004",
		"role":"client"
	}`))
	handler.RequestOTP(rec, req)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	if bytes.Contains(rec.Body.Bytes(), []byte("debug_otp")) || bytes.Contains(rec.Body.Bytes(), []byte("123456")) {
		t.Fatalf("fixed code leaked in response: %s", rec.Body.String())
	}
}

type fixedHTTPClock struct{ now time.Time }

func (c fixedHTTPClock) Now() time.Time { return c.now }

type seqID struct{ n int }

func (g *seqID) NewID() string {
	g.n++
	return "id-" + string(rune('0'+g.n))
}

type fakeUserRepository struct {
	users        map[string]*userdomain.User
	sessions     map[string]*userdomain.RefreshSession
	otps         map[string]*userdomain.PhoneOTP
	deviceTokens map[string]*userdomain.DeviceToken
}

func newFakeUserRepository() *fakeUserRepository {
	return &fakeUserRepository{
		users:        map[string]*userdomain.User{},
		sessions:     map[string]*userdomain.RefreshSession{},
		otps:         map[string]*userdomain.PhoneOTP{},
		deviceTokens: map[string]*userdomain.DeviceToken{},
	}
}

func (r *fakeUserRepository) GetByID(_ context.Context, id string) (*userdomain.User, error) {
	user := r.users[id]
	if user == nil {
		return nil, userdomain.ErrUserNotFound
	}
	return user, nil
}

func (r *fakeUserRepository) GetByPhoneAndRole(_ context.Context, phone string, role string) (*userdomain.User, error) {
	for _, user := range r.users {
		if user.Phone == phone && string(user.Role) == role {
			return user, nil
		}
	}
	return nil, userdomain.ErrUserNotFound
}

func (r *fakeUserRepository) IsUserActive(_ context.Context, userID string) (bool, error) {
	user := r.users[userID]
	if user == nil {
		return false, nil
	}
	return user.Status == userdomain.StatusActive && user.DeletedAt == nil, nil
}

func (r *fakeUserRepository) Create(_ context.Context, user *userdomain.User) error {
	for _, existing := range r.users {
		if existing.Phone == user.Phone && existing.Role == user.Role {
			return userdomain.ErrUserAlreadyExists
		}
	}
	r.users[user.ID] = user
	return nil
}

func (r *fakeUserRepository) UpdatePasswordHash(_ context.Context, userID string, passwordHash string) error {
	if r.users[userID] == nil {
		return userdomain.ErrUserNotFound
	}
	r.users[userID].PasswordHash = &passwordHash
	return nil
}

func (r *fakeUserRepository) CreateRefreshSession(_ context.Context, session *userdomain.RefreshSession) error {
	cp := *session
	r.sessions[session.ID] = &cp
	return nil
}

func (r *fakeUserRepository) GetActiveRefreshSessionByHash(_ context.Context, tokenHash string) (*userdomain.RefreshSession, error) {
	for _, session := range r.sessions {
		if session.TokenHash == tokenHash && session.RevokedAt == nil {
			return session, nil
		}
	}
	return nil, userdomain.ErrSessionNotFound
}

func (r *fakeUserRepository) RevokeRefreshSession(_ context.Context, sessionID string, revokedAt time.Time) error {
	if r.sessions[sessionID] != nil {
		r.sessions[sessionID].RevokedAt = &revokedAt
	}
	return nil
}

func (r *fakeUserRepository) CreatePhoneOTP(_ context.Context, otp *userdomain.PhoneOTP) error {
	cp := *otp
	r.otps[otp.ID] = &cp
	return nil
}

func (r *fakeUserRepository) ConsumePhoneOTP(_ context.Context, phone string, role string, codeHash string, now time.Time) (*userdomain.PhoneOTP, error) {
	for _, otp := range r.otps {
		if otp.Phone == phone && string(otp.Role) == role && otp.CodeHash == codeHash && otp.ConsumedAt == nil && otp.ExpiresAt.After(now) {
			otp.ConsumedAt = &now
			return otp, nil
		}
	}
	return nil, userdomain.ErrOTPNotFound
}

func (r *fakeUserRepository) UpsertDeviceToken(_ context.Context, token *userdomain.DeviceToken) error {
	cp := *token
	r.deviceTokens[token.FCMToken] = &cp
	return nil
}

func (r *fakeUserRepository) RevokeDeviceToken(_ context.Context, userID string, role string, fcmToken string, revokedAt time.Time) error {
	token := r.deviceTokens[fcmToken]
	if token != nil && token.UserID == userID && string(token.Role) == role {
		token.RevokedAt = &revokedAt
	}
	return nil
}

func (r *fakeUserRepository) UpsertTaxProfile(context.Context, *userdomain.TaxProfile) error {
	return nil
}

func (r *fakeUserRepository) GetTaxProfile(context.Context, string) (*userdomain.TaxProfile, error) {
	return nil, userdomain.ErrTaxProfileNotFound
}

func (r *fakeUserRepository) IsDriverTaxVerified(context.Context, string) (bool, error) {
	return true, nil
}

func (r *fakeUserRepository) IsDriverDocumentsApproved(context.Context, string) (bool, error) {
	return true, nil
}

func (r *fakeUserRepository) IsDriverSubscriptionActive(context.Context, string, time.Time) (bool, error) {
	return true, nil
}

func (r *fakeUserRepository) UpdateNPDConnection(context.Context, string, userdomain.NPDConnectionResult, time.Time) error {
	return nil
}

func (r *fakeUserRepository) MarkNPDRevoked(context.Context, string, time.Time) error {
	return nil
}
