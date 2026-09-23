//go:build integration

package ws_test

import (
	"context"
	"database/sql"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"evik/backend/internal/auth"
	chatrepo "evik/backend/internal/infrastructure/postgres"
	evikredis "evik/backend/internal/infrastructure/redis"
	wsinfra "evik/backend/internal/infrastructure/websocket"
	httptransport "evik/backend/internal/transport/http"
	ws "evik/backend/internal/transport/ws"
	"github.com/go-chi/chi/v5"
	"github.com/gorilla/websocket"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/redis/go-redis/v9"

	evik "evik/backend"
)

func TestOrderChatProductionE2ETwoSessions(t *testing.T) {
	dsn := getenvOrSkip(t, "TEST_DATABASE_URL")
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if err := db.Ping(); err != nil {
		t.Fatal(err)
	}
	goose.SetBaseFS(evik.EmbedMigrations)
	goose.SetLogger(goose.NopLogger())
	_ = goose.SetDialect("postgres")
	if err := goose.Up(db, "migrations"); err != nil {
		t.Fatal(err)
	}
	clientID, driverID, orderID := "e2e-client", "e2e-driver", "e2e-order"
	cleanupChatFixture(t, db, orderID, driverID, clientID)
	seedE2EFixture(t, db, clientID, driverID, orderID)

	redisClient := redis.NewClient(&redis.Options{Addr: "localhost:6379"})
	if err := redisClient.Ping(context.Background()).Err(); err != nil {
		t.Skipf("Redis unavailable: %v", err)
	}
	defer redisClient.Close()
	channel := fmt.Sprintf("evik:e2e:%d", time.Now().UnixNano())
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hub := wsinfra.NewHub()
	go hub.Run()
	repo := chatrepo.NewChatRepository(db)
	publisher := evikredis.NewOrderEventPublisher(redisClient, channel)
	access := repo
	relay := wsinfra.NewOrderEventRelay(hub, publisher, nil, access, log.New(io.Discard, "", 0))
	go relay.Run(ctx)
	tokens := auth.NewTokenManager("e2e-chat-secret", time.Hour, 2*time.Hour)
	clientToken, _, _ := tokens.Issue(clientID, auth.RoleClient)
	driverToken, _, _ := tokens.Issue(driverID, auth.RoleDriver)
	chatHandler := httptransport.NewChatHandler(repo, publisher)
	wsHandler := ws.NewOrderWSHandler(hub, nil, log.New(io.Discard, "", 0), tokens, nil, nil, publisher, time.Now)
	wsHandler.SetChatRepository(repo)
	r := chi.NewRouter()
	r.With(httptransport.AuthMiddleware(tokens)).Get("/api/v1/orders/{orderID}/chat/messages", chatHandler.List)
	r.With(httptransport.AuthMiddleware(tokens)).Post("/api/v1/orders/{orderID}/chat/messages", chatHandler.Send)
	r.With(httptransport.WSAuthMiddleware(tokens)).Get("/ws/orders", wsHandler.Handle)
	server := httptest.NewServer(r)
	defer server.Close()
	wsURL := "ws" + server.URL[len("http"):] + "/ws/orders?access_token="
	clientWS := dialE2E(t, wsURL+url.QueryEscape(clientToken))
	defer clientWS.Close()
	driverWS := dialE2E(t, wsURL+url.QueryEscape(driverToken))
	defer driverWS.Close()
	sendE2E(t, clientWS, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": orderID}})
	sendE2E(t, driverWS, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": orderID}})
	expectE2EType(t, clientWS, "chat.subscribed", orderID)
	expectE2EType(t, driverWS, "chat.subscribed", orderID)
	sendE2E(t, clientWS, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": orderID, "client_message_id": "c1", "text": "hello"}})
	ack := expectE2EType(t, clientWS, "chat.ack", orderID)
	expectE2EType(t, driverWS, "chat.message", orderID)
	sendE2E(t, clientWS, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": orderID, "client_message_id": "c1", "text": "changed"}})
	replay := expectE2EType(t, clientWS, "chat.ack", orderID)
	if ack["payload"].(map[string]any)["message"].(map[string]any)["id"] != replay["payload"].(map[string]any)["message"].(map[string]any)["id"] {
		t.Fatal("replay returned a different server id")
	}
	var count int
	if err := db.QueryRow(`SELECT count(*) FROM chat_messages WHERE order_id=$1`, orderID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("message count=%d err=%v", count, err)
	}

	_ = clientWS.Close()
	sendE2E(t, clientWS, nil)
	// The persisted history is the recovery contract after a lost realtime event.
	req, _ := http.NewRequest(http.MethodGet, server.URL+"/api/v1/orders/"+orderID+"/chat/messages?limit=100", nil)
	req.Header.Set("Authorization", "Bearer "+clientToken)
	resp, err := server.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("history status=%d", resp.StatusCode)
	}

	if _, err := db.Exec(`UPDATE orders SET status='cancelled' WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	for _, token := range []string{clientToken, driverToken} {
		cancelledHistory, _ := http.NewRequest(http.MethodGet, server.URL+"/api/v1/orders/"+orderID+"/chat/messages?limit=100", nil)
		cancelledHistory.Header.Set("Authorization", "Bearer "+token)
		cancelledResp, err := server.Client().Do(cancelledHistory)
		if err != nil {
			t.Fatal(err)
		}
		cancelledResp.Body.Close()
		if cancelledResp.StatusCode != http.StatusOK {
			t.Fatalf("cancelled history status=%d", cancelledResp.StatusCode)
		}
	}
	replayReq, _ := http.NewRequest(http.MethodPost, server.URL+"/api/v1/orders/"+orderID+"/chat/messages", strings.NewReader(`{"client_message_id":"c1","text":"changed"}`))
	replayReq.Header.Set("Authorization", "Bearer "+clientToken)
	replayResp, err := server.Client().Do(replayReq)
	if err != nil {
		t.Fatal(err)
	}
	replayBody, _ := io.ReadAll(replayResp.Body)
	replayResp.Body.Close()
	if replayResp.StatusCode != http.StatusCreated || !strings.Contains(string(replayBody), fmt.Sprint(messageID(ack))) {
		t.Fatalf("cancelled replay status=%d body=%s", replayResp.StatusCode, replayBody)
	}
	replayWS := dialE2E(t, wsURL+url.QueryEscape(clientToken))
	defer replayWS.Close()
	sendE2E(t, replayWS, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": orderID, "client_message_id": "c1", "text": "changed"}})
	if got := expectE2EType(t, replayWS, "chat.ack", orderID); messageID(got) != messageID(ack) {
		t.Fatal("cancelled WS replay changed id")
	}
	closeReq, _ := http.NewRequest(http.MethodPost, server.URL+"/api/v1/orders/"+orderID+"/chat/messages", strings.NewReader(`{"client_message_id":"new","text":"no"}`))
	closeReq.Header.Set("Authorization", "Bearer "+clientToken)
	closeResp, err := server.Client().Do(closeReq)
	if err != nil {
		t.Fatal(err)
	}
	defer closeResp.Body.Close()
	if closeResp.StatusCode != http.StatusConflict {
		t.Fatalf("closed status=%d", closeResp.StatusCode)
	}
	sendE2E(t, replayWS, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": orderID, "client_message_id": "new-ws", "text": "no"}})
	closedEvent := expectE2ETypeOnly(t, replayWS, "chat.error")
	if closedEvent["payload"].(map[string]any)["code"] != "chat_closed" {
		t.Fatalf("cancelled WS event=%v", closedEvent)
	}
	assertMessageCount(t, db, orderID, 1)
}

type e2eEnv struct {
	db                          *sql.DB
	server                      *httptest.Server
	wsURL                       string
	clientID, driverID, orderID string
	clientToken, driverToken    string
	cancel                      context.CancelFunc
}

func newE2EEnv(t *testing.T, suffix string) *e2eEnv {
	t.Helper()
	db, err := sql.Open("pgx", getenvOrSkip(t, "TEST_DATABASE_URL"))
	if err != nil {
		t.Fatal(err)
	}
	goose.SetBaseFS(evik.EmbedMigrations)
	goose.SetLogger(goose.NopLogger())
	_ = goose.SetDialect("postgres")
	if err := goose.Up(db, "migrations"); err != nil {
		t.Fatal(err)
	}
	clientID, driverID, orderID := "e2e-client-"+suffix, "e2e-driver-"+suffix, "e2e-order-"+suffix
	cleanupChatFixture(t, db, orderID, driverID, clientID)
	seedE2EFixture(t, db, clientID, driverID, orderID)
	rc := redis.NewClient(&redis.Options{Addr: "localhost:6379"})
	if err := rc.Ping(context.Background()).Err(); err != nil {
		t.Skipf("Redis unavailable: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	hub := wsinfra.NewHub()
	go hub.Run()
	repo := chatrepo.NewChatRepository(db)
	publisher := evikredis.NewOrderEventPublisher(rc, fmt.Sprintf("evik:e2e:%s:%d", suffix, time.Now().UnixNano()))
	go wsinfra.NewOrderEventRelay(hub, publisher, nil, repo, log.New(io.Discard, "", 0)).Run(ctx)
	tokens := auth.NewTokenManager("e2e-chat-secret", time.Hour, 2*time.Hour)
	clientToken, _, _ := tokens.Issue(clientID, auth.RoleClient)
	driverToken, _, _ := tokens.Issue(driverID, auth.RoleDriver)
	ch := httptransport.NewChatHandler(repo, publisher)
	wh := ws.NewOrderWSHandler(hub, nil, log.New(io.Discard, "", 0), tokens, nil, nil, publisher, time.Now)
	wh.SetChatRepository(repo)
	r := chi.NewRouter()
	r.With(httptransport.AuthMiddleware(tokens)).Get("/api/v1/orders/{orderID}/chat/messages", ch.List)
	r.With(httptransport.AuthMiddleware(tokens)).Post("/api/v1/orders/{orderID}/chat/messages", ch.Send)
	r.With(httptransport.WSAuthMiddleware(tokens)).Get("/ws/orders", wh.Handle)
	server := httptest.NewServer(r)
	t.Cleanup(func() { cancel(); server.Close(); _ = rc.Close(); _ = db.Close() })
	return &e2eEnv{db: db, server: server, wsURL: "ws" + server.URL[len("http"):] + "/ws/orders?access_token=", clientID: clientID, driverID: driverID, orderID: orderID, clientToken: clientToken, driverToken: driverToken, cancel: cancel}
}

func (e *e2eEnv) authRequest(t *testing.T, method, path, token, body string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest(method, e.server.URL+path, strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := e.server.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestOrderChatProductionE2EReconnectCatchUp(t *testing.T) {
	e := newE2EEnv(t, "reconnect")
	client := dialE2E(t, e.wsURL+url.QueryEscape(e.clientToken))
	defer client.Close()
	driver := dialE2E(t, e.wsURL+url.QueryEscape(e.driverToken))
	for _, c := range []*websocket.Conn{client, driver} {
		sendE2E(t, c, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": e.orderID}})
		expectE2EType(t, c, "chat.subscribed", e.orderID)
	}
	sendE2E(t, client, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "before", "text": "before"}})
	expectE2EType(t, client, "chat.ack", e.orderID)
	expectE2EType(t, driver, "chat.message", e.orderID)
	_, _ = e.db.Exec(`UPDATE chat_messages SET created_at=NOW()-INTERVAL '2 seconds' WHERE order_id=$1`, e.orderID)
	_ = driver.Close()
	sendE2E(t, client, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "offline", "text": "offline"}})
	expectE2EType(t, client, "chat.ack", e.orderID)
	assertMessageCount(t, e.db, e.orderID, 2)
	reconnected := dialE2E(t, e.wsURL+url.QueryEscape(e.driverToken))
	defer reconnected.Close()
	sendE2E(t, reconnected, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": e.orderID}})
	expectE2EType(t, reconnected, "chat.subscribed", e.orderID)
	resp := e.authRequest(t, http.MethodGet, "/api/v1/orders/"+e.orderID+"/chat/messages?limit=100", e.driverToken, "")
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 || !strings.Contains(string(data), "offline") {
		t.Fatalf("history status=%d body=%s", resp.StatusCode, data)
	}
	_, _ = e.db.Exec(`UPDATE chat_messages SET created_at=NOW()-INTERVAL '2 seconds' WHERE order_id=$1`, e.orderID)
	sendE2E(t, client, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "after", "text": "after"}})
	expectE2EType(t, client, "chat.ack", e.orderID)
	expectE2EType(t, reconnected, "chat.message", e.orderID)
	assertMessageCount(t, e.db, e.orderID, 3)
}

func TestOrderChatProductionE2ECompletedOrder(t *testing.T) {
	e := newE2EEnv(t, "completed")
	client := dialE2E(t, e.wsURL+url.QueryEscape(e.clientToken))
	defer client.Close()
	sendE2E(t, client, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "saved", "text": "saved"}})
	ack := expectE2EType(t, client, "chat.ack", e.orderID)
	// The production completion endpoint requires payment settlement; this
	// focused chat fixture supplies the same persisted completion invariants.
	if _, err := e.db.Exec(`UPDATE orders SET status='completed', commission_amount=0, driver_amount=price_total, financially_completed_at=NOW() WHERE id=$1`, e.orderID); err != nil {
		t.Fatal(err)
	}
	for _, token := range []string{e.clientToken, e.driverToken} {
		resp := e.authRequest(t, http.MethodGet, "/api/v1/orders/"+e.orderID+"/chat/messages", token, "")
		if resp.StatusCode != 200 {
			t.Fatalf("history=%d", resp.StatusCode)
		}
		resp.Body.Close()
	}
	httpReplay := e.authRequest(t, http.MethodPost, "/api/v1/orders/"+e.orderID+"/chat/messages", e.clientToken, `{"client_message_id":"saved","text":"changed"}`)
	httpReplayBody, _ := io.ReadAll(httpReplay.Body)
	httpReplay.Body.Close()
	if httpReplay.StatusCode != http.StatusCreated || !strings.Contains(string(httpReplayBody), fmt.Sprint(messageID(ack))) {
		t.Fatalf("HTTP replay status=%d body=%s", httpReplay.StatusCode, httpReplayBody)
	}
	sendE2E(t, client, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "saved", "text": "changed"}})
	replay := expectE2EType(t, client, "chat.ack", e.orderID)
	if messageID(ack) != messageID(replay) {
		t.Fatal("completed replay changed id")
	}
	assertMessageCount(t, e.db, e.orderID, 1)
	closedHTTP := e.authRequest(t, http.MethodPost, "/api/v1/orders/"+e.orderID+"/chat/messages", e.clientToken, `{"client_message_id":"new-http","text":"new"}`)
	closedHTTP.Body.Close()
	if closedHTTP.StatusCode != http.StatusConflict {
		t.Fatalf("new HTTP message status=%d", closedHTTP.StatusCode)
	}
	driver := dialE2E(t, e.wsURL+url.QueryEscape(e.driverToken))
	defer driver.Close()
	sendE2E(t, driver, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": e.orderID}})
	expectE2EType(t, driver, "chat.subscribed", e.orderID)
	sendE2E(t, client, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "new", "text": "new"}})
	errEvent := expectE2ETypeOnly(t, client, "chat.error")
	if errEvent["payload"].(map[string]any)["code"] != "chat_closed" {
		t.Fatalf("event=%v", errEvent)
	}
	assertNoE2EMessage(t, driver)
	assertMessageCount(t, e.db, e.orderID, 1)
}

func TestOrderChatProductionE2EDriverReassignment(t *testing.T) {
	e := newE2EEnv(t, "reassign")
	oldActive := dialE2E(t, e.wsURL+url.QueryEscape(e.driverToken))
	defer oldActive.Close()
	sendE2E(t, oldActive, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": e.orderID}})
	expectE2EType(t, oldActive, "chat.subscribed", e.orderID)
	driver2 := "e2e-driver2-reassign"
	_, _ = e.db.Exec(`DELETE FROM drivers WHERE id=$1`, driver2)
	_, _ = e.db.Exec(`DELETE FROM users WHERE id=$1`, driver2)
	if _, err := e.db.Exec(`INSERT INTO users(id,phone,full_name,role,status,created_at,updated_at) VALUES($1,'+79990000099',$1,'driver','active',NOW(),NOW())`, driver2); err != nil {
		t.Fatal(err)
	}
	if _, err := e.db.Exec(`INSERT INTO drivers(id,user_id,status,last_seen_at,updated_at) VALUES($1,$1,'online',NOW(),NOW())`, driver2); err != nil {
		t.Fatal(err)
	}
	tokens := auth.NewTokenManager("e2e-chat-secret", time.Hour, 2*time.Hour)
	driver2Token, _, _ := tokens.Issue(driver2, auth.RoleDriver)
	if _, err := e.db.Exec(`UPDATE orders SET driver_id=$1 WHERE id=$2`, driver2, e.orderID); err != nil {
		t.Fatal(err)
	}
	resp := e.authRequest(t, http.MethodGet, "/api/v1/orders/"+e.orderID+"/chat/messages", e.driverToken, "")
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("old driver history=%d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = e.authRequest(t, http.MethodPost, "/api/v1/orders/"+e.orderID+"/chat/messages", e.driverToken, `{"client_message_id":"old-http","text":"denied"}`)
	resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("old driver send=%d", resp.StatusCode)
	}
	old := dialE2E(t, e.wsURL+url.QueryEscape(e.driverToken))
	defer old.Close()
	sendE2E(t, old, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": e.orderID}})
	forbidden := expectE2ETypeOnly(t, old, "chat.error")
	if forbidden["payload"].(map[string]any)["code"] != "forbidden" {
		t.Fatalf("event=%v", forbidden)
	}
	sendE2E(t, oldActive, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "old-ws", "text": "denied"}})
	forbidden = expectE2ETypeOnly(t, oldActive, "chat.error")
	if forbidden["payload"].(map[string]any)["code"] != "forbidden" {
		t.Fatalf("event=%v", forbidden)
	}
	newConn := dialE2E(t, e.wsURL+url.QueryEscape(driver2Token))
	defer newConn.Close()
	sendE2E(t, newConn, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": e.orderID}})
	expectE2EType(t, newConn, "chat.subscribed", e.orderID)
	resp = e.authRequest(t, http.MethodGet, "/api/v1/orders/"+e.orderID+"/chat/messages", driver2Token, "")
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("new driver history=%d", resp.StatusCode)
	}
	client := dialE2E(t, e.wsURL+url.QueryEscape(e.clientToken))
	defer client.Close()
	sendE2E(t, client, map[string]any{"type": "chat.subscribe", "data": map[string]any{"order_id": e.orderID}})
	expectE2EType(t, client, "chat.subscribed", e.orderID)
	sendE2E(t, client, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "new-driver", "text": "hello new"}})
	expectE2EType(t, client, "chat.ack", e.orderID)
	expectE2EType(t, newConn, "chat.message", e.orderID)
	assertNoE2EMessage(t, oldActive)
	sendE2E(t, newConn, map[string]any{"type": "chat.send", "data": map[string]any{"order_id": e.orderID, "client_message_id": "driver2-reply", "text": "reply"}})
	expectE2EType(t, newConn, "chat.ack", e.orderID)
	expectE2EType(t, client, "chat.message", e.orderID)
}

func assertMessageCount(t *testing.T, db *sql.DB, orderID string, want int) {
	t.Helper()
	var got int
	if err := db.QueryRow(`SELECT count(*) FROM chat_messages WHERE order_id=$1`, orderID).Scan(&got); err != nil || got != want {
		t.Fatalf("message count=%d want=%d err=%v", got, want, err)
	}
}

func assertNoE2EMessage(t *testing.T, c *websocket.Conn) {
	t.Helper()
	_ = c.SetReadDeadline(time.Now().Add(250 * time.Millisecond))
	var event map[string]any
	err := c.ReadJSON(&event)
	if err == nil {
		t.Fatalf("unexpected realtime event: %v", event)
	}
	if netErr, ok := err.(interface{ Timeout() bool }); !ok || !netErr.Timeout() {
		t.Fatalf("expected read deadline, got %v", err)
	}
}

func messageID(event map[string]any) any {
	return event["payload"].(map[string]any)["message"].(map[string]any)["id"]
}
func expectE2ETypeOnly(t *testing.T, c *websocket.Conn, typ string) map[string]any {
	t.Helper()
	_ = c.SetReadDeadline(time.Now().Add(2 * time.Second))
	var v map[string]any
	if err := c.ReadJSON(&v); err != nil {
		t.Fatal(err)
	}
	if v["type"] != typ {
		t.Fatalf("event=%v expected=%s", v, typ)
	}
	return v
}

func dialE2E(t *testing.T, raw string) *websocket.Conn {
	t.Helper()
	c, _, err := websocket.DefaultDialer.Dial(raw, nil)
	if err != nil {
		t.Fatal(err)
	}
	return c
}
func sendE2E(t *testing.T, c *websocket.Conn, v any) {
	t.Helper()
	if v == nil {
		return
	}
	if err := c.WriteJSON(v); err != nil {
		t.Fatal(err)
	}
}
func expectE2EType(t *testing.T, c *websocket.Conn, typ, orderID string) map[string]any {
	t.Helper()
	_ = c.SetReadDeadline(time.Now().Add(2 * time.Second))
	var v map[string]any
	if err := c.ReadJSON(&v); err != nil {
		t.Fatal(err)
	}
	actualOrder := v["order_id"]
	if actualOrder == nil {
		if payload, ok := v["payload"].(map[string]any); ok {
			actualOrder = payload["order_id"]
			if actualOrder == nil {
				if message, ok := payload["message"].(map[string]any); ok {
					actualOrder = message["order_id"]
				}
			}
		}
	}
	if v["type"] != typ || actualOrder != orderID {
		t.Fatalf("event=%v expected %s/%s", v, typ, orderID)
	}
	return v
}
func getenvOrSkip(t *testing.T, key string) string {
	v := os.Getenv(key)
	if v == "" {
		t.Skip(key + " is required")
	}
	return v
}
func cleanupChatFixture(t *testing.T, db *sql.DB, order, driver, client string) {
	_, _ = db.Exec(`DELETE FROM chat_messages WHERE order_id=$1`, order)
	_, _ = db.Exec(`DELETE FROM orders WHERE id=$1`, order)
	_, _ = db.Exec(`DELETE FROM drivers WHERE id=$1`, driver)
	_, _ = db.Exec(`DELETE FROM users WHERE id IN ($1,$2)`, client, driver)
}
func seedE2EFixture(t *testing.T, db *sql.DB, client, driver, order string) {
	for i, u := range []struct{ id, role string }{{client, "client"}, {driver, "driver"}} {
		phone := fmt.Sprintf("+7999%07d", time.Now().UnixNano()%10000000+int64(i))
		if _, err := db.Exec(`INSERT INTO users(id,phone,full_name,role,status,created_at,updated_at) VALUES($1,$2,$3,$4,'active',NOW(),NOW())`, u.id, phone, u.id, u.role); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`INSERT INTO drivers(id,user_id,status,last_seen_at,updated_at) VALUES($1,$1,'online',NOW(),NOW())`, driver); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO orders(id,user_id,driver_id,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,tow_truck_type,status,price_total,created_at,updated_at) VALUES($1,$2,$3,42,47,42.1,47.1,'winch','accepted',100,NOW(),NOW())`, order, client, driver); err != nil {
		t.Fatal(err)
	}
}
