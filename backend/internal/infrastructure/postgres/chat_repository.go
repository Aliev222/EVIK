package postgres

import (
	"context"
	"database/sql"
	"errors"

	chatdomain "evik/backend/internal/domain/chat"
)

type ChatRepository struct{ db *sql.DB }

func NewChatRepository(db *sql.DB) *ChatRepository { return &ChatRepository{db: db} }

func (r *ChatRepository) CanAccess(ctx context.Context, orderID, userID string) (bool, error) {
	var ok bool
	err := r.db.QueryRowContext(ctx, `
SELECT EXISTS(SELECT 1 FROM orders WHERE id=$1 AND (user_id=$2 OR driver_id=$2))`, orderID, userID).Scan(&ok)
	return ok, err
}

func (r *ChatRepository) Create(ctx context.Context, orderID, senderID, clientMessageID, text string) (chatdomain.Message, error) {
	// The order predicate is evaluated by PostgreSQL at insert time: a stale or
	// reassigned driver cannot write after the assignment changed.
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return chatdomain.Message{}, err
	}
	defer tx.Rollback()
	// PostgreSQL advisory locking makes the rate limit global across API/WS
	// handlers and deployment replicas without storing message text in Redis.
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, senderID); err != nil {
		return chatdomain.Message{}, err
	}
	const q = `
WITH permitted AS (
  SELECT id, user_id, driver_id FROM orders
  WHERE id=$1 AND (user_id=$2 OR driver_id=$2)
    AND status IN ('accepted','arrived','in_progress','awaiting_payment')
), recent AS (
  SELECT 1 FROM chat_messages WHERE sender_id=$2 AND created_at > NOW() - INTERVAL '750 milliseconds' LIMIT 1
), existing AS (
  SELECT id, order_id, sender_id, recipient_id, client_message_id, text, created_at FROM chat_messages
  WHERE order_id=$1 AND sender_id=$2 AND client_message_id=$3
	AND EXISTS (SELECT 1 FROM (SELECT id FROM orders WHERE id=$1 AND (user_id=$2 OR driver_id=$2)) current_order)
), inserted AS (
  INSERT INTO chat_messages (id, order_id, sender_id, recipient_id, client_message_id, text, created_at)
  SELECT gen_random_uuid()::text, id, $2,
    CASE WHEN user_id=$2 THEN driver_id ELSE user_id END, $3, $4, NOW() FROM permitted
  WHERE NOT EXISTS (SELECT 1 FROM recent) AND NOT EXISTS (SELECT 1 FROM existing)
  ON CONFLICT (order_id, sender_id, client_message_id) DO UPDATE
    SET client_message_id = EXCLUDED.client_message_id
  RETURNING id, order_id, sender_id, recipient_id, client_message_id, text, created_at
)
SELECT id, order_id, sender_id, recipient_id, client_message_id, text, created_at FROM existing
UNION ALL
SELECT id, order_id, sender_id, recipient_id, client_message_id, text, created_at FROM inserted
	LIMIT 1`
	var m chatdomain.Message
	err = tx.QueryRowContext(ctx, q, orderID, senderID, clientMessageID, text).Scan(
		&m.ID, &m.OrderID, &m.SenderID, &m.RecipientID, &m.ClientMessageID, &m.Text, &m.CreatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		var allowed bool
		if accessErr := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM orders WHERE id=$1 AND (user_id=$2 OR driver_id=$2))`, orderID, senderID).Scan(&allowed); accessErr != nil {
			return m, accessErr
		}
		if !allowed {
			return m, chatdomain.ErrForbidden
		}
		var status string
		if statusErr := tx.QueryRowContext(ctx, `SELECT status FROM orders WHERE id=$1`, orderID).Scan(&status); statusErr != nil {
			return m, statusErr
		}
		if status != "accepted" && status != "arrived" && status != "in_progress" && status != "awaiting_payment" {
			return m, chatdomain.ErrClosed
		}
		return m, chatdomain.ErrRateLimited
	}
	if err != nil {
		return m, err
	}
	if err := tx.Commit(); err != nil {
		return m, err
	}
	return m, nil
}

func (r *ChatRepository) List(ctx context.Context, orderID, userID, beforeID string, limit int) ([]chatdomain.Message, error) {
	const q = `
WITH permitted AS (
 SELECT id FROM orders WHERE id=$1 AND (user_id=$2 OR driver_id=$2)
), cursor AS (
 SELECT created_at, id FROM chat_messages WHERE id=$3 AND order_id=$1
)
SELECT id, order_id, sender_id, recipient_id, client_message_id, text, created_at
FROM chat_messages
WHERE order_id=$1 AND EXISTS (SELECT 1 FROM permitted)
  AND ($3='' OR (created_at,id) < (SELECT created_at,id FROM cursor))
ORDER BY created_at DESC, id DESC LIMIT $4`
	rows, err := r.db.QueryContext(ctx, q, orderID, userID, beforeID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var reverse []chatdomain.Message
	for rows.Next() {
		var m chatdomain.Message
		if err := rows.Scan(&m.ID, &m.OrderID, &m.SenderID, &m.RecipientID, &m.ClientMessageID, &m.Text, &m.CreatedAt); err != nil {
			return nil, err
		}
		reverse = append(reverse, m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(reverse) == 0 {
		allowed, err := r.CanAccess(ctx, orderID, userID)
		if err != nil {
			return nil, err
		}
		if !allowed {
			return nil, chatdomain.ErrForbidden
		}
		if beforeID != "" {
			var exists bool
			if err := r.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM chat_messages WHERE id=$1 AND order_id=$2)`, beforeID, orderID).Scan(&exists); err != nil {
				return nil, err
			}
			if !exists {
				return nil, chatdomain.ErrInvalidCursor
			}
		}
	}
	for left, right := 0, len(reverse)-1; left < right; left, right = left+1, right-1 {
		reverse[left], reverse[right] = reverse[right], reverse[left]
	}
	return reverse, nil
}

var _ chatdomain.Repository = (*ChatRepository)(nil)
