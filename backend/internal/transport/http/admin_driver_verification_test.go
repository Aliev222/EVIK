package http

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"evik/backend/internal/auth"
	admindomain "evik/backend/internal/domain/admin"
)

// verificationRepo is a narrow fake AdminRepository used by the
// SubmitDriverVerification tests. It records the upserted item and returns a
// configurable error so the handler's blocked-guard can be asserted in
// isolation (no database needed).
type verificationRepo struct {
	*fakeAdminRepo
	upsertErr error
	gotItem   admindomain.DriverVerification
	upsertCalls int
}

func (f *verificationRepo) UpsertDriverVerification(_ context.Context, item admindomain.DriverVerification) error {
	f.upsertCalls++
	f.gotItem = item
	return f.upsertErr
}

func newVerificationHandler(repo AdminRepository) *AdminHandler {
	return &AdminHandler{
		repo: repo,
		clock: fixedHTTPClock{
			now: time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC),
		},
	}
}

func verificationSubmitRequest(userID string, role auth.Role) *http.Request {
	req := httptest.NewRequest(
		http.MethodPost,
		"/driver-verifications",
		strings.NewReader(`{"full_name":"Иван","vehicle_model":"GAZ","vehicle_plate":"A000AA77","vehicle_type":"winch","documents":["http://x/1.jpg"],"signals":[]}`),
	)
	req.Header.Set("Content-Type", "application/json")
	return req.WithContext(withAuth(req.Context(), userID, role))
}

// SubmitDriverVerification: when the persisted verification is blocked, the
// handler must refuse the resubmission (403) and never let the driver back
// into pending.
func TestSubmitDriverVerification_BlockedDriverRejectedWith403(t *testing.T) {
	repo := &verificationRepo{
		fakeAdminRepo: &fakeAdminRepo{},
		upsertErr:     admindomain.ErrDriverVerificationBlocked,
	}
	rec := httptest.NewRecorder()
	newVerificationHandler(repo).SubmitDriverVerification(
		rec,
		verificationSubmitRequest("driver-1", auth.RoleDriver),
	)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "заблокирован") {
		t.Errorf("body must mention the block: %s", rec.Body.String())
	}
	if repo.upsertCalls != 1 {
		t.Fatalf("upsert calls = %d, want 1", repo.upsertCalls)
	}
	// The handler still built a pending submission — the 403 came from the
	// repository guard, not from request validation.
	if repo.gotItem.Status != admindomain.VerificationStatusPending {
		t.Errorf("submitted status = %q, want pending (handler intent)", repo.gotItem.Status)
	}
}

// SubmitDriverVerification: an admin submitting on behalf of a blocked driver
// is refused too — admins lift a block via a decision endpoint, not by
// resubmitting the verification form.
func TestSubmitDriverVerification_AdminCannotResubmitBlockedDriver(t *testing.T) {
	repo := &verificationRepo{
		fakeAdminRepo: &fakeAdminRepo{},
		upsertErr:     admindomain.ErrDriverVerificationBlocked,
	}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(
		http.MethodPost,
		"/driver-verifications",
		strings.NewReader(`{"user_id":"driver-1","full_name":"Иван","vehicle_model":"GAZ","vehicle_plate":"A000AA77","vehicle_type":"winch","documents":["http://x/1.jpg"]}`),
	)
	req.Header.Set("Content-Type", "application/json")
	req = req.WithContext(withAuth(req.Context(), "admin", auth.RoleAdmin))
	newVerificationHandler(repo).SubmitDriverVerification(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body=%s)", rec.Code, rec.Body.String())
	}
	if repo.gotItem.UserID != "driver-1" {
		t.Fatalf("upserted user_id = %q, want driver-1", repo.gotItem.UserID)
	}
}

// SubmitDriverVerification: rejected / changes_requested drivers must be able
// to resubmit — the repository returns nil and the handler answers 201.
func TestSubmitDriverVerification_AllowsResubmitWhenNotBlocked(t *testing.T) {
	repo := &verificationRepo{fakeAdminRepo: &fakeAdminRepo{}, upsertErr: nil}
	rec := httptest.NewRecorder()
	newVerificationHandler(repo).SubmitDriverVerification(
		rec,
		verificationSubmitRequest("driver-1", auth.RoleDriver),
	)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201 (body=%s)", rec.Code, rec.Body.String())
	}
	if repo.upsertCalls != 1 {
		t.Fatalf("upsert calls = %d, want 1", repo.upsertCalls)
	}
	if repo.gotItem.ID != "driver-1" || repo.gotItem.UserID != "driver-1" {
		t.Fatalf("upserted id/user_id = %q/%q, want driver-1", repo.gotItem.ID, repo.gotItem.UserID)
	}
}