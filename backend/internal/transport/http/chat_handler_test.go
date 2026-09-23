package http

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"evik/backend/internal/auth"
	chatdomain "evik/backend/internal/domain/chat"
	"github.com/go-chi/chi/v5"
)

type fakeChatRepo struct {
	created chatdomain.Message
	sender  string
	err     error
}

func (r *fakeChatRepo) CanAccess(context.Context, string, string) (bool, error) { return true, nil }
func (r *fakeChatRepo) Create(_ context.Context, orderID, sender, clientID, text string) (chatdomain.Message, error) {
	r.sender = sender
	if r.err != nil {
		return chatdomain.Message{}, r.err
	}
	r.created = chatdomain.Message{ID: "m1", OrderID: orderID, SenderID: sender, ClientMessageID: clientID, Text: text, CreatedAt: time.Now()}
	return r.created, nil
}
func (r *fakeChatRepo) List(context.Context, string, string, string, int) ([]chatdomain.Message, error) {
	return nil, r.err
}

func TestChatSendUsesAuthenticatedSenderNotRequestBody(t *testing.T) {
	repo := &fakeChatRepo{}
	h := NewChatHandler(repo, nil)
	req := httptest.NewRequest(http.MethodPost, "/orders/o1/chat/messages", strings.NewReader(`{"client_message_id":"retry-1","text":"  На месте  "}`))
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("orderID", "o1")
	req = req.WithContext(context.WithValue(withAuth(req.Context(), "client-1", auth.RoleClient), chi.RouteCtxKey, rctx))
	res := httptest.NewRecorder()
	h.Send(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("status=%d body=%s", res.Code, res.Body.String())
	}
	if repo.sender != "client-1" || repo.created.Text != "На месте" {
		t.Fatalf("created=%+v sender=%s", repo.created, repo.sender)
	}
}

func TestChatSendRejectsFormerDriver(t *testing.T) {
	repo := &fakeChatRepo{err: chatdomain.ErrForbidden}
	h := NewChatHandler(repo, nil)
	req := httptest.NewRequest(http.MethodPost, "/orders/o1/chat/messages", strings.NewReader(`{"client_message_id":"x","text":"hello"}`))
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("orderID", "o1")
	req = req.WithContext(context.WithValue(withAuth(req.Context(), "old-driver", auth.RoleDriver), chi.RouteCtxKey, rctx))
	res := httptest.NewRecorder()
	h.Send(res, req)
	if res.Code != http.StatusForbidden {
		t.Fatalf("status=%d body=%s", res.Code, res.Body.String())
	}
}
