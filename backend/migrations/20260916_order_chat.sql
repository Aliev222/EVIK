-- +goose Up
CREATE TABLE chat_messages (
    id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    recipient_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    client_message_id TEXT NOT NULL,
    text TEXT NOT NULL CHECK (char_length(btrim(text)) BETWEEN 1 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (order_id, sender_id, client_message_id)
);
CREATE INDEX chat_messages_order_cursor_idx ON chat_messages (order_id, created_at DESC, id DESC);
CREATE INDEX chat_messages_sender_created_idx ON chat_messages (sender_id, created_at DESC);

-- +goose Down
DROP TABLE IF EXISTS chat_messages;
