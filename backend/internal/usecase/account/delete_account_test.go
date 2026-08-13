package account

import (
	"context"
	"errors"
	"testing"
	"time"

	"evik/backend/internal/auth"
)

type fakeRepo struct {
	deleteErr error
	calls     int
	lastUser  string
	lastRole  auth.Role
}

func (f *fakeRepo) Delete(_ context.Context, userID string, role auth.Role, _ time.Time) error {
	f.calls++
	f.lastUser = userID
	f.lastRole = role
	return f.deleteErr
}

func TestUseCaseDeletesClientAccount(t *testing.T) {
	repo := &fakeRepo{}
	uc := NewUseCase(repo)

	if err := uc.Execute(context.Background(), "client-1", auth.RoleClient); err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if repo.calls != 1 || repo.lastUser != "client-1" || repo.lastRole != auth.RoleClient {
		t.Fatalf("repo call mismatch: calls=%d user=%q role=%q", repo.calls, repo.lastUser, repo.lastRole)
	}
}

func TestUseCaseDeletesDriverAccount(t *testing.T) {
	repo := &fakeRepo{}
	uc := NewUseCase(repo)

	if err := uc.Execute(context.Background(), "driver-1", auth.RoleDriver); err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if repo.lastRole != auth.RoleDriver {
		t.Fatalf("role = %q, want driver", repo.lastRole)
	}
}

func TestUseCasePropagatesGuardErrors(t *testing.T) {
	cases := []struct {
		name string
		err  error
	}{
		{"active order", ErrActiveOrder},
		{"outstanding balance", ErrOutstandingDriverBalance},
		{"account not found", ErrAccountNotFound},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uc := NewUseCase(&fakeRepo{deleteErr: tc.err})
			err := uc.Execute(context.Background(), "user-1", auth.RoleClient)
			if !errors.Is(err, tc.err) {
				t.Fatalf("Execute err = %v, want %v", err, tc.err)
			}
		})
	}
}

func TestUseCaseRejectsAdminAndEmptyUserID(t *testing.T) {
	repo := &fakeRepo{}

	uc := NewUseCase(repo)
	if err := uc.Execute(context.Background(), "admin-1", auth.RoleAdmin); err == nil {
		t.Fatal("admin deletion must be refused")
	}
	if repo.calls != 0 {
		t.Fatalf("repo called for admin: %d", repo.calls)
	}

	if err := uc.Execute(context.Background(), "", auth.RoleClient); err == nil {
		t.Fatal("empty user id must be refused")
	}
	if repo.calls != 0 {
		t.Fatalf("repo called for empty id: %d", repo.calls)
	}
}