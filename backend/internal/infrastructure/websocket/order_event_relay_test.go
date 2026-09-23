package wsinfra

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"testing"

	orderdomain "evik/backend/internal/domain/order"
)

type relayChatAccess struct{ allowed bool }

func (a relayChatAccess) CanAccess(context.Context, string, string) (bool, error) {
	return a.allowed, nil
}

func TestChatRelayDeliversOnlyToSubscribedCurrentRecipient(t *testing.T) {
	hub := NewHub()
	go hub.Run()
	client := &Client{UserID: "driver-1", Role: "driver", Send: make(chan []byte, 1)}
	hub.Register(client)
	hub.SubscribeChat(client, "o1")
	relay := &OrderEventRelay{hub: hub, chatAccess: relayChatAccess{allowed: true}, logger: log.New(os.Stderr, "test", 0)}
	payload, _ := json.Marshal(orderdomain.Event{Type: orderdomain.EventChatMessage, OrderID: "o1", Payload: map[string]any{"recipient_id": "driver-1"}})
	relay.handleEvent(string(payload))
	if len(client.Send) != 1 {
		t.Fatalf("delivery count=%d, want 1", len(client.Send))
	}
}

func TestChatRelayDropsEventAfterRecipientAccessRevoked(t *testing.T) {
	hub := NewHub()
	go hub.Run()
	client := &Client{UserID: "old-driver", Role: "driver", Send: make(chan []byte, 1)}
	hub.Register(client)
	hub.SubscribeChat(client, "o1")
	relay := &OrderEventRelay{hub: hub, chatAccess: relayChatAccess{allowed: false}, logger: log.New(os.Stderr, "test", 0)}
	payload, _ := json.Marshal(orderdomain.Event{Type: orderdomain.EventChatMessage, OrderID: "o1", Payload: map[string]any{"recipient_id": "old-driver"}})
	relay.handleEvent(string(payload))
	if len(client.Send) != 0 {
		t.Fatalf("revoked recipient received chat event")
	}
}
