package chat

import (
	"context"
	"errors"
	"time"
)

var (
	ErrForbidden     = errors.New("chat access forbidden")
	ErrClosed        = errors.New("chat is closed for this order")
	ErrRateLimited   = errors.New("chat message rate limited")
	ErrInvalidCursor = errors.New("invalid chat cursor")
)

type Message struct {
	ID              string    `json:"id"`
	OrderID         string    `json:"order_id"`
	SenderID        string    `json:"sender_id"`
	RecipientID     string    `json:"-"`
	ClientMessageID string    `json:"client_message_id"`
	Text            string    `json:"text"`
	CreatedAt       time.Time `json:"created_at"`
}

// Repository keeps authorization adjacent to the order row. Callers must
// still validate that the authenticated role is client or driver.
type Repository interface {
	CanAccess(ctx context.Context, orderID, userID string) (bool, error)
	Create(ctx context.Context, orderID, senderID, clientMessageID, text string) (Message, error)
	List(ctx context.Context, orderID, userID, beforeID string, limit int) ([]Message, error)
}
