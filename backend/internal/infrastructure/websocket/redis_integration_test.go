//go:build integration

package wsinfra

import (
	"context"
	"fmt"
	"log"
	"strings"
	"testing"
	"time"

	orderdomain "evik/backend/internal/domain/order"
	evikredis "evik/backend/internal/infrastructure/redis"
	"github.com/redis/go-redis/v9"
)

type integrationChatAccess struct{ allowed map[string]bool }

func (c *integrationChatAccess) CanAccess(_ context.Context, orderID, userID string) (bool, error) {
	return c.allowed[orderID+":"+userID], nil
}

func TestRedisRelayIntegrationAcrossInstances(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	channel := fmt.Sprintf("evik:chat:test:%d", time.Now().UnixNano())
	clientA := redis.NewClient(&redis.Options{Addr: "localhost:6379"})
	clientB := redis.NewClient(&redis.Options{Addr: "localhost:6379"})
	t.Cleanup(func() { _ = clientA.Close(); _ = clientB.Close() })
	if err := clientA.Ping(ctx).Err(); err != nil {
		t.Skipf("local Redis unavailable: %v", err)
	}

	hubA, hubB := NewHub(), NewHub()
	go hubA.Run()
	go hubB.Run()
	recipient := &Client{UserID: "driver-b", Role: "driver", Send: make(chan []byte, 4)}
	unsubscribed := &Client{UserID: "driver-b", Role: "driver", Send: make(chan []byte, 4)}
	hubB.Register(recipient)
	hubB.Register(unsubscribed)
	hubB.SubscribeChat(recipient, "order-1")
	access := &integrationChatAccess{allowed: map[string]bool{"order-1:driver-b": true}}
	logger := log.New(&strings.Builder{}, "", 0)
	relay := NewOrderEventRelay(hubB, evikredis.NewOrderEventPublisher(clientB, channel), nil, access, logger)
	go relay.Run(ctx)
	time.Sleep(100 * time.Millisecond)

	event := orderdomain.Event{Type: orderdomain.EventChatMessage, OrderID: "order-1", Payload: map[string]any{
		"recipient_id": "driver-b", "sender_id": "client-a", "message": map[string]any{"id": "m1", "text": "hello"},
	}}
	if err := evikredis.NewOrderEventPublisher(clientA, channel).Publish(ctx, event); err != nil {
		t.Fatal(err)
	}
	select {
	case payload := <-recipient.Send:
		if !strings.Contains(string(payload), "m1") || strings.Contains(string(payload), "token") {
			t.Fatalf("unexpected payload: %s", payload)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for cross-instance delivery")
	}
	select {
	case <-unsubscribed.Send:
		t.Fatal("unsubscribed connection received event")
	case <-time.After(100 * time.Millisecond):
	}

	hubB.UnsubscribeChat(recipient, "order-1")
	if err := evikredis.NewOrderEventPublisher(clientA, channel).Publish(ctx, event); err != nil {
		t.Fatal(err)
	}
	select {
	case <-recipient.Send:
		t.Fatal("unsubscribed recipient received event")
	case <-time.After(150 * time.Millisecond):
	}

	hubB.SubscribeChat(recipient, "order-1")
	access.allowed["order-1:driver-b"] = false
	if err := evikredis.NewOrderEventPublisher(clientA, channel).Publish(ctx, event); err != nil {
		t.Fatal(err)
	}
	select {
	case <-recipient.Send:
		t.Fatal("revoked recipient received queued event")
	case <-time.After(150 * time.Millisecond):
	}
	hubB.Unregister(recipient)
	hubB.Unregister(unsubscribed)
}
