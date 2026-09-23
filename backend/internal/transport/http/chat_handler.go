package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"evik/backend/internal/auth"
	chatdomain "evik/backend/internal/domain/chat"
	orderdomain "evik/backend/internal/domain/order"
	"github.com/go-chi/chi/v5"
)

type ChatEventPublisher interface {
	Publish(ctx context.Context, event orderdomain.Event) error
}

type ChatHandler struct {
	repo   chatdomain.Repository
	events ChatEventPublisher
}

func NewChatHandler(repo chatdomain.Repository, events ChatEventPublisher) *ChatHandler {
	return &ChatHandler{repo: repo, events: events}
}

type sendChatMessageRequest struct {
	ClientMessageID string `json:"client_message_id"`
	Text            string `json:"text"`
}

func (h *ChatHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, role, ok := chatPrincipal(r)
	if !ok {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	limit, err := parseChatLimit(r.URL.Query().Get("limit"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid limit"})
		return
	}
	messages, err := h.repo.List(r.Context(), chi.URLParam(r, "orderID"), userID, r.URL.Query().Get("before_id"), limit+1)
	if err != nil {
		h.writeChatError(w, err)
		return
	}
	_ = role
	var next string
	if len(messages) > limit {
		messages = messages[:limit]
		next = nextBefore(messages)
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": messages, "next_before_id": next})
}

func (h *ChatHandler) Send(w http.ResponseWriter, r *http.Request) {
	userID, _, ok := chatPrincipal(r)
	if !ok {
		writeAuthError(w, http.StatusForbidden, "forbidden")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	var req sendChatMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid chat message"})
		return
	}
	req.Text = strings.TrimSpace(req.Text)
	req.ClientMessageID = strings.TrimSpace(req.ClientMessageID)
	if req.ClientMessageID == "" || len(req.ClientMessageID) > 128 || !utf8.ValidString(req.Text) || utf8.RuneCountInString(req.Text) == 0 || utf8.RuneCountInString(req.Text) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid chat message"})
		return
	}
	m, err := h.repo.Create(r.Context(), chi.URLParam(r, "orderID"), userID, req.ClientMessageID, req.Text)
	if err != nil {
		h.writeChatError(w, err)
		return
	}
	if h.events != nil {
		// Persistence is authoritative; Redis Pub/Sub is a delivery hint. The
		// recipient can recover this message through history after reconnect.
		_ = h.events.Publish(r.Context(), orderdomain.Event{Type: orderdomain.EventChatMessage, OrderID: m.OrderID, Payload: map[string]any{"message": m, "sender_id": m.SenderID, "recipient_id": m.RecipientID}})
	}
	writeJSON(w, http.StatusCreated, map[string]any{"message": m})
}

func chatPrincipal(r *http.Request) (string, auth.Role, bool) {
	userID, userErr := userIDFromContext(r.Context())
	role, roleErr := roleFromContext(r.Context())
	return userID, role, userErr == nil && roleErr == nil && (role == auth.RoleClient || role == auth.RoleDriver)
}
func parseChatLimit(raw string) (int, error) {
	if raw == "" {
		return 50, nil
	}
	var limit int
	limit, err := strconv.Atoi(raw)
	if err != nil || limit < 1 || limit > 100 {
		return 0, errors.New("invalid limit")
	}
	return limit, nil
}
func nextBefore(messages []chatdomain.Message) string {
	if len(messages) == 0 {
		return ""
	}
	return messages[0].ID
}
func (h *ChatHandler) writeChatError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, chatdomain.ErrForbidden):
		writeAuthError(w, http.StatusForbidden, "forbidden")
	case errors.Is(err, chatdomain.ErrClosed):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "chat is closed"})
	case errors.Is(err, chatdomain.ErrRateLimited):
		writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "too many messages"})
	case errors.Is(err, chatdomain.ErrInvalidCursor):
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid cursor"})
	default:
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "chat unavailable"})
	}
}
