//go:build loadtest

package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math"
	"math/rand"
	"net/http"
	"os"
	"sort"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	_ "github.com/jackc/pgx/v5/stdlib"
)

// ---------------------------------------------------------------------------
// Flags
// ---------------------------------------------------------------------------

var (
	flagDrivers         = flag.Int("drivers", 10, "number of driver accounts")
	flagClients         = flag.Int("clients", 10, "number of client accounts")
	flagBaseURL         = flag.String("baseURL", "http://localhost:8080", "base HTTP URL")
	flagWSURL           = flag.String("wsURL", "ws://localhost:8080", "base WebSocket URL")
	flagOTPCode         = flag.String("otpCode", "000000", "fixed OTP code (dev only)")
	flagDBDSN           = flag.String("dbDSN", "postgres://evik:evik@localhost:5432/evik?sslmode=disable", "PostgreSQL DSN")
	flagOfferAcceptProb = flag.Float64("offerAcceptProb", 1.0, "probability 0..1 that a driver accepts an offer")
	flagOfferAcceptMin  = flag.Duration("offerAcceptDelayMin", 0, "min delay before accepting")
	flagOfferAcceptMax  = flag.Duration("offerAcceptDelayMax", time.Second, "max delay before accepting")
	flagBurst           = flag.Bool("burst", false, "create all orders simultaneously instead of staggered")
	flagBasePhone       = flag.Int64("basePhone", 79990000000, "base phone number (incremented per account)")
	flagRunSeconds      = flag.Duration("runTime", 120*time.Second, "max test run duration")
)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func phoneFor(idx int, role string) string {
	n := *flagBasePhone + int64(idx)
	return fmt.Sprintf("+%d", n)
}

func nameFor(idx int, role string) string {
	if role == "driver" {
		return fmt.Sprintf("Driver_%d", idx)
	}
	return fmt.Sprintf("Client_%d", idx)
}

// ---------------------------------------------------------------------------
// API response types (partial — only fields we need)
// ---------------------------------------------------------------------------

type authTokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
}

type otpVerifyResponse struct {
	Tokens authTokens `json:"tokens"`
	User   struct {
		ID   string `json:"id"`
		Role string `json:"role"`
	} `json:"user"`
}

type orderCreateResponse struct {
	Order struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	} `json:"order"`
}

type errorResponse struct {
	Error string `json:"error"`
}

// ---------------------------------------------------------------------------
// WebSocket incoming offer shape (from dispatch_scheduler.go:sendOfferPush)
// ---------------------------------------------------------------------------

type wsOfferMsg struct {
	Type          string  `json:"type"`
	OfferID       string  `json:"offer_id"`
	OrderID       string  `json:"order_id"`
	ExpiresAt     string  `json:"expires_at"`
	PickupLat     float64 `json:"pickup_lat"`
	PickupLng     float64 `json:"pickup_lng"`
	DropoffLat    float64 `json:"dropoff_lat"`
	DropoffLng    float64 `json:"dropoff_lng"`
	PickupAddress string  `json:"pickup_address"`
	DropoffAddr   string  `json:"dropoff_address"`
	DistanceKM    float64 `json:"distance_km"`
	PriceTotal    int64   `json:"price_total"`
	TowTruckType  string  `json:"tow_truck_type"`
}

// ---------------------------------------------------------------------------
// Per-order result
// ---------------------------------------------------------------------------

type orderResult struct {
	OrderID     string
	ClientIdx   int
	Created     time.Time
	Offered     time.Time
	Accepted    time.Time
	Matched     bool
	AcceptedBy  string
	NoDriver    bool
	Errored     bool
	ErrorMsg    string
}

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------

type driverState struct {
	idx           int
	userID        string
	token         string
	phone         string
	conn          *websocket.Conn
	connMu        sync.Mutex
	offers        chan wsOfferMsg
	acceptedOrder string
	mu            sync.Mutex
}

type testRun struct {
	mu      sync.Mutex
	results []orderResult
}

func (tr *testRun) add(r orderResult) {
	tr.mu.Lock()
	tr.results = append(tr.results, r)
	tr.mu.Unlock()
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

var httpClient = &http.Client{Timeout: 30 * time.Second}

func apiPOST(url string, body any, token string) (*http.Response, []byte, error) {
	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(body); err != nil {
		return nil, nil, err
	}
	req, err := http.NewRequest("POST", url, &buf)
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	return resp, data, err
}

func apiGET(url string, token string) (*http.Response, []byte, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, nil, err
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	return resp, data, err
}

// ---------------------------------------------------------------------------
// Auth: OTP request + verify
// ---------------------------------------------------------------------------

func registerAndVerify(ctx context.Context, baseURL, phone, role, code, fullName string) (string, string, error) {
	// Step 1: request OTP
	reqBody := map[string]string{"phone": phone, "role": role}
	_, body, err := apiPOST(baseURL+"/api/v1/auth/otp/request", reqBody, "")
	if err != nil {
		return "", "", fmt.Errorf("otp request: %w", err)
	}
	var e errorResponse
	if json.Unmarshal(body, &e); e.Error != "" {
		return "", "", fmt.Errorf("otp request error: %s", e.Error)
	}

	// Step 2: verify OTP
	verifyBody := map[string]string{
		"phone":    phone,
		"code":     code,
		"role":     role,
		"full_name": fullName,
	}
	resp, body, err := apiPOST(baseURL+"/api/v1/auth/otp/verify", verifyBody, "")
	if err != nil {
		return "", "", fmt.Errorf("otp verify: %w", err)
	}
	if resp.StatusCode != 200 {
		if json.Unmarshal(body, &e); e.Error != "" {
			return "", "", fmt.Errorf("otp verify error (HTTP %d): %s", resp.StatusCode, e.Error)
		}
		return "", "", fmt.Errorf("otp verify HTTP %d", resp.StatusCode)
	}
	var vr otpVerifyResponse
	if err := json.Unmarshal(body, &vr); err != nil {
		return "", "", fmt.Errorf("otp verify parse: %w", err)
	}
	return vr.User.ID, vr.Tokens.AccessToken, nil
}

// ---------------------------------------------------------------------------
// Driver: go online
// ---------------------------------------------------------------------------

func driverGoOnline(ctx context.Context, baseURL, driverID, token string) error {
	body := map[string]string{"status": "online"}
	resp, data, err := apiPOST(baseURL+"/api/v1/drivers/"+driverID+"/status", body, token)
	if err != nil {
		return fmt.Errorf("go online: %w", err)
	}
	if resp.StatusCode != 200 {
		var e errorResponse
		if json.Unmarshal(data, &e); e.Error != "" {
			return fmt.Errorf("go online error (HTTP %d): %s", resp.StatusCode, e.Error)
		}
		return fmt.Errorf("go online HTTP %d", resp.StatusCode)
	}
	return nil
}

// ---------------------------------------------------------------------------
// Driver: WebSocket lifecycle
// ---------------------------------------------------------------------------

func driverConnectWS(ctx context.Context, wsURL, token string) (*websocket.Conn, error) {
	u := wsURL + "/ws/orders?access_token=" + token
	dialer := websocket.Dialer{HandshakeTimeout: 10 * time.Second}
	conn, _, err := dialer.DialContext(ctx, u, nil)
	if err != nil {
		return nil, fmt.Errorf("ws dial: %w", err)
	}
	return conn, nil
}

// wsReadLoop reads messages from the WebSocket and dispatches offers to the channel.
func wsReadLoop(d *driverState, logPrefix string) {
	defer d.conn.Close()
	for {
		_, msgBytes, err := d.conn.ReadMessage()
		if err != nil {
			return
		}
		var generic struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(msgBytes, &generic); err != nil {
			continue
		}
		switch generic.Type {
		case "offer":
			var offer wsOfferMsg
			if err := json.Unmarshal(msgBytes, &offer); err != nil {
				continue
			}
			select {
			case d.offers <- offer:
			default:
			}
		case "pong":
		case "ping":
			d.connMu.Lock()
			d.conn.WriteMessage(websocket.PongMessage, nil)
			d.connMu.Unlock()
		}
	}
}

// sendLocationUpdate sends a location_update message to the server.
func sendLocationUpdate(conn *websocket.Conn, driverID string, lat, lng float64) error {
	msg := map[string]any{
		"type":      "location_update",
		"driver_id": driverID,
		"data": map[string]any{
			"lat":    lat,
			"lng":    lng,
			"bearing": 0.0,
			"speed":   0.0,
			"status":  "online",
			"is_mock": true,
		},
		"timestamp": time.Now().UTC().Format(time.RFC3339Nano),
	}
	return conn.WriteJSON(msg)
}

// ---------------------------------------------------------------------------
// Client: create order
// ---------------------------------------------------------------------------

func clientCreateOrder(ctx context.Context, baseURL, token string, pickupLat, pickupLng, dropoffLat, dropoffLng float64) (string, bool, error) {
	body := map[string]any{
		"pickup_lat":      pickupLat,
		"pickup_lng":      pickupLng,
		"dropoff_lat":     dropoffLat,
		"dropoff_lng":     dropoffLng,
		"pickup_address":  "ул. Ленина, 1",
		"dropoff_address": "ул. Советская, 10",
		"tow_truck_type":  "winch",
		"payment_method":  "cash",
		"auto_dispatch":   true,
		"is_mock":         true,
	}
	resp, data, err := apiPOST(baseURL+"/api/v1/orders", body, token)
	if err != nil {
		return "", false, fmt.Errorf("create order: %w", err)
	}
	if resp.StatusCode == 201 {
		var cr orderCreateResponse
		if err := json.Unmarshal(data, &cr); err != nil {
			return "", false, fmt.Errorf("parse create order: %w", err)
		}
		return cr.Order.ID, true, nil
	}
	var e errorResponse
	if json.Unmarshal(data, &e); e.Error != "" {
		return "", false, fmt.Errorf("create order HTTP %d: %s", resp.StatusCode, e.Error)
	}
	return "", false, fmt.Errorf("create order HTTP %d", resp.StatusCode)
}

// ---------------------------------------------------------------------------
// Driver: accept order via HTTP
// ---------------------------------------------------------------------------

func driverAcceptOrder(ctx context.Context, baseURL, orderID, token string) error {
	body := map[string]string{"driver_id": ""}
	resp, data, err := apiPOST(baseURL+"/api/v1/orders/"+orderID+"/accept", body, token)
	if err != nil {
		return fmt.Errorf("accept: %w", err)
	}
	if resp.StatusCode != 200 {
		var e errorResponse
		if json.Unmarshal(data, &e); e.Error != "" {
			return fmt.Errorf("accept error (HTTP %d): %s", resp.StatusCode, e.Error)
		}
		return fmt.Errorf("accept HTTP %d", resp.StatusCode)
	}
	return nil
}

// ---------------------------------------------------------------------------
// Coordinates: Makhachkala area
// ---------------------------------------------------------------------------

const (
	baseLat = 42.9764
	baseLng = 47.5024
)

func randomOffset() (float64, float64) {
	latOff := (rand.Float64() - 0.5) * 0.02 // ±0.01 deg ≈ ±1.1 km
	lngOff := (rand.Float64() - 0.5) * 0.02
	return baseLat + latOff, baseLng + lngOff
}

// ---------------------------------------------------------------------------
// DB verification
// ---------------------------------------------------------------------------

func verifyDB(ctx context.Context, dsn string) error {
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		return fmt.Errorf("db open: %w", err)
	}
	defer db.Close()
	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("db ping: %w", err)
	}

	// Check 1: no driver has >1 accepted active order
	rows, err := db.QueryContext(ctx, `
		SELECT driver_id, COUNT(*) as cnt
		FROM orders
		WHERE status IN ('accepted','arrived','in_progress')
		GROUP BY driver_id
		HAVING COUNT(*) > 1
	`)
	if err != nil {
		return fmt.Errorf("db query 1: %w", err)
	}
	defer rows.Close()
	var violations int
	for rows.Next() {
		var driverID string
		var cnt int
		if err := rows.Scan(&driverID, &cnt); err != nil {
			return fmt.Errorf("db scan 1: %w", err)
		}
		violations++
		fmt.Fprintf(os.Stderr, "!!! CORRECTNESS VIOLATION: driver %s assigned to %d active orders\n", driverID, cnt)
	}
	if violations == 0 {
		fmt.Println("[DB CHECK 1/3 OK] No driver with multiple active orders")
	}

	// Check 2: no order has more than one offer with outcome='accepted'
	rows2, err := db.QueryContext(ctx, `
		SELECT oo.order_id, COUNT(*) as cnt
		FROM order_offers oo
		WHERE oo.outcome = 'accepted'
		GROUP BY oo.order_id
		HAVING COUNT(*) > 1
	`)
	if err != nil {
		return fmt.Errorf("db query 2: %w", err)
	}
	defer rows2.Close()
	violations = 0
	for rows2.Next() {
		var orderID string
		var cnt int
		if err := rows2.Scan(&orderID, &cnt); err != nil {
			return fmt.Errorf("db scan 2: %w", err)
		}
		violations++
		fmt.Fprintf(os.Stderr, "!!! CORRECTNESS VIOLATION: order %s accepted by %d drivers\n", orderID, cnt)
	}
	if violations == 0 {
		fmt.Println("[DB CHECK 2/3 OK] No order with multiple acceptors")
	}

	// Check 3: no accepted order without an accepted offer
	rows3, err := db.QueryContext(ctx, `
		SELECT o.id, o.driver_id
		FROM orders o
		WHERE o.status IN ('accepted','arrived','in_progress')
		AND o.driver_id IS NOT NULL
		AND NOT EXISTS (
			SELECT 1 FROM order_offers oo
			WHERE oo.order_id = o.id
			AND oo.driver_id = o.driver_id
			AND oo.outcome = 'accepted'
		)
	`)
	if err != nil {
		return fmt.Errorf("db query 3: %w", err)
	}
	defer rows3.Close()
	violations = 0
	for rows3.Next() {
		var orderID, driverID string
		if err := rows3.Scan(&orderID, &driverID); err != nil {
			return fmt.Errorf("db scan 3: %w", err)
		}
		violations++
		fmt.Fprintf(os.Stderr, "!!! CORRECTNESS VIOLATION: order %s accepted by driver %s without an accepted offer\n", orderID, driverID)
	}
	if violations == 0 {
		fmt.Println("[DB CHECK 3/3 OK] Every accepted order has a corresponding accepted offer")
	}

	return nil
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func main() {
	flag.Parse()
	fmt.Printf("=== Avro dispatch load test ===\n")
	fmt.Printf("Drivers: %d, Clients: %d\n", *flagDrivers, *flagClients)
	fmt.Printf("Base URL: %s, WS URL: %s\n", *flagBaseURL, *flagWSURL)
	fmt.Printf("Offer accept prob: %.2f, accept delay: %s..%s\n",
		*flagOfferAcceptProb, *flagOfferAcceptMin, *flagOfferAcceptMax)
	fmt.Printf("Burst mode: %t\n", *flagBurst)
	fmt.Println()

	ctx, cancel := context.WithTimeout(context.Background(), *flagRunSeconds)
	defer cancel()

	// ---- Phase 1: Register and auth N drivers + N clients ----
	fmt.Println("=== Phase 1: Registration & Auth ===")
	type account struct {
		idx   int
		id    string
		token string
	}
	drivers := make([]*driverState, *flagDrivers)
	clients := make([]account, *flagClients)

	for i := 0; i < *flagDrivers; i++ {
		phone := phoneFor(i+1, "driver")
		name := nameFor(i+1, "driver")
		userID, token, err := registerAndVerify(ctx, *flagBaseURL, phone, "driver", *flagOTPCode, name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "[DRIVER %d] register/verify failed: %v\n", i+1, err)
			continue
		}
		drivers[i] = &driverState{
			idx:    i + 1,
			userID: userID,
			token:  token,
			phone:  phone,
			offers: make(chan wsOfferMsg, 16),
		}
		fmt.Printf("[DRIVER %d] registered: user=%s phone=%s\n", i+1, userID, phone)
	}

	for i := 0; i < *flagClients; i++ {
		phone := phoneFor(i+1+*flagDrivers, "client")
		name := nameFor(i+1, "client")
		userID, token, err := registerAndVerify(ctx, *flagBaseURL, phone, "client", *flagOTPCode, name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "[CLIENT %d] register/verify failed: %v\n", i+1, err)
			continue
		}
		clients[i] = account{idx: i + 1, id: userID, token: token}
		fmt.Printf("[CLIENT %d] registered: user=%s phone=%s\n", i+1, userID, phone)
	}

	// Count successful registrations
	activeDrivers := 0
	for _, d := range drivers {
		if d != nil {
			activeDrivers++
		}
	}
	activeClients := 0
	for _, c := range clients {
		if c.token != "" {
			activeClients++
		}
	}
	fmt.Printf("Active drivers: %d, Active clients: %d\n", activeDrivers, activeClients)
	fmt.Println()

	if activeDrivers == 0 || activeClients == 0 {
		fmt.Fprintf(os.Stderr, "FATAL: no active drivers or clients\n")
		os.Exit(1)
	}

	// ---- Phase 2: Drivers go online + connect WS + send location ----
	fmt.Println("=== Phase 2: Drivers go online & connect WebSocket ===")
	var driverMu sync.Mutex
	var wg sync.WaitGroup

	for _, d := range drivers {
		if d == nil {
			continue
		}
		wg.Add(1)
		go func(drv *driverState) {
			defer wg.Done()

			// Go online
			if err := driverGoOnline(ctx, *flagBaseURL, drv.userID, drv.token); err != nil {
				fmt.Fprintf(os.Stderr, "[DRIVER %d] go online failed: %v\n", drv.idx, err)
				return
			}

			// Connect WS
			conn, err := driverConnectWS(ctx, *flagWSURL, drv.token)
			if err != nil {
				fmt.Fprintf(os.Stderr, "[DRIVER %d] WS connect failed: %v\n", drv.idx, err)
				return
			}
			drv.connMu.Lock()
			drv.conn = conn
			drv.connMu.Unlock()

			// Start read loop
			go wsReadLoop(drv, fmt.Sprintf("[DRIVER %d]", drv.idx))

			// Send location update
			lat, lng := randomOffset()
			if err := sendLocationUpdate(conn, drv.userID, lat, lng); err != nil {
				fmt.Fprintf(os.Stderr, "[DRIVER %d] first location update failed: %v\n", drv.idx, err)
				return
			}

			driverMu.Lock()
			fmt.Printf("[DRIVER %d] online + WS connected, location: %.4f,%.4f\n", drv.idx, lat, lng)
			driverMu.Unlock()
		}(d)
	}
	wg.Wait()

	// Start periodic location updates for all drivers
	locCtx, locCancel := context.WithCancel(ctx)
	defer locCancel()
	for _, d := range drivers {
		if d == nil || d.conn == nil {
			continue
		}
		go func(drv *driverState) {
			lat, lng := randomOffset()
			ticker := time.NewTicker(5 * time.Second)
			defer ticker.Stop()
			for {
				select {
				case <-locCtx.Done():
					return
				case <-ticker.C:
					drv.connMu.Lock()
					conn := drv.conn
					drv.connMu.Unlock()
					if conn == nil {
						return
					}
					sendLocationUpdate(conn, drv.userID, lat, lng)
				}
			}
		}(d)
	}

	// Wait for drivers to be "fresh" — the dispatch scheduler needs locations
	// within the geo freshness window (default 60s).
	fmt.Println("\nWaiting 15s for location freshness...")
	select {
	case <-time.After(15 * time.Second):
	case <-ctx.Done():
		fmt.Fprintf(os.Stderr, "Context cancelled during wait\n")
		return
	}

	// ---- Phase 3: Create orders ----
	fmt.Println("=== Phase 3: Create orders ===")
	run := &testRun{}

	type orderToCreate struct {
		clientIdx int
		token     string
	}

	var orderCreateQueue []orderToCreate
	for i, c := range clients {
		if c.token == "" {
			continue
		}
		orderCreateQueue = append(orderCreateQueue, orderToCreate{clientIdx: i, token: c.token})
	}

	if *flagBurst {
		// Burst: create all orders at once (goroutines)
		var createWg sync.WaitGroup
		for _, oc := range orderCreateQueue {
			createWg.Add(1)
			go func(oc orderToCreate) {
				defer createWg.Done()
				start := time.Now()
				pickupLat, pickupLng := randomOffset()
				dropoffLat, dropoffLng := randomOffset()
				orderID, ok, err := clientCreateOrder(ctx, *flagBaseURL, oc.token, pickupLat, pickupLng, dropoffLat, dropoffLng)
				elapsed := time.Since(start)
				r := orderResult{
					ClientIdx: oc.clientIdx + 1,
					Created:   start,
				}
				if err != nil {
					r.Errored = true
					r.ErrorMsg = err.Error()
				} else if !ok {
					r.NoDriver = true
				} else {
					r.OrderID = orderID
				}
				run.add(r)
				if err != nil {
					fmt.Printf("[ORDER %d] BURST create FAILED: %v (%.0fms)\n", oc.clientIdx+1, err, elapsed.Seconds()*1000)
				} else {
					fmt.Printf("[ORDER %d] BURST created: %s (%.0fms)\n", oc.clientIdx+1, orderID, elapsed.Seconds()*1000)
				}
			}(oc)
		}
		createWg.Wait()
	} else {
		// Staggered: each order with 200ms delay
		for _, oc := range orderCreateQueue {
			select {
			case <-ctx.Done():
				return
			default:
			}
			start := time.Now()
			pickupLat, pickupLng := randomOffset()
			dropoffLat, dropoffLng := randomOffset()
			orderID, ok, err := clientCreateOrder(ctx, *flagBaseURL, oc.token, pickupLat, pickupLng, dropoffLat, dropoffLng)
			elapsed := time.Since(start)
			r := orderResult{
				ClientIdx: oc.clientIdx + 1,
				Created:   start,
			}
			if err != nil {
				r.Errored = true
				r.ErrorMsg = err.Error()
			} else if !ok {
				r.NoDriver = true
			} else {
				r.OrderID = orderID
			}
			run.add(r)
			if err != nil {
				fmt.Printf("[ORDER %d] create FAILED: %v (%.0fms)\n", oc.clientIdx+1, err, elapsed.Seconds()*1000)
			} else {
				fmt.Printf("[ORDER %d] created: %s (%.0fms)\n", oc.clientIdx+1, orderID, elapsed.Seconds()*1000)
			}
			time.Sleep(200 * time.Millisecond)
		}
	}

	// ---- Phase 4: Collect offers and accept ----
	fmt.Println("\n=== Phase 4: Listening for offers & accepting ===")

	// Map order IDs to result entries
	type resultPtr struct {
		r    *orderResult
		idx  int
	}
	orderMap := make(map[string]*resultPtr)
	run.mu.Lock()
	for i := range run.results {
		r := &run.results[i]
		if r.OrderID != "" && !r.Errored {
			orderMap[r.OrderID] = &resultPtr{r: r, idx: i}
		}
	}
	run.mu.Unlock()

	// Start goroutines to listen for offers and accept on each driver
	var acceptWg sync.WaitGroup
	for _, d := range drivers {
		if d == nil || d.conn == nil {
			continue
		}
		acceptWg.Add(1)
		go func(drv *driverState) {
			defer acceptWg.Done()
			for {
				select {
				case <-ctx.Done():
					return
				case offer, ok := <-drv.offers:
					if !ok {
						return
					}
					now := time.Now()

					// Record the offer time
					run.mu.Lock()
					if rp, exists := orderMap[offer.OrderID]; exists {
						if rp.r.Offered.IsZero() {
							rp.r.Offered = now
							rp.r.Matched = true
						}
					}
					run.mu.Unlock()

					// Decide whether to accept
					if rand.Float64() > *flagOfferAcceptProb {
						continue
					}
					if *flagOfferAcceptMax > 0 {
						delay := *flagOfferAcceptMin
						if *flagOfferAcceptMax > *flagOfferAcceptMin {
							delay += time.Duration(rand.Int63n(int64(*flagOfferAcceptMax - *flagOfferAcceptMin)))
						}
						time.Sleep(delay)
					}

					// Accept the order
					if err := driverAcceptOrder(ctx, *flagBaseURL, offer.OrderID, drv.token); err != nil {
						fmt.Fprintf(os.Stderr, "[DRIVER %d] accept %s FAILED: %v\n", drv.idx, offer.OrderID, err)
						continue
					}

					acceptTime := time.Now()
					run.mu.Lock()
					if rp, exists := orderMap[offer.OrderID]; exists {
						if rp.r.Accepted.IsZero() {
							rp.r.Accepted = acceptTime
							rp.r.AcceptedBy = drv.userID
						} else {
							fmt.Fprintf(os.Stderr, "!!! DOUBLE-ACCEPT: order %s accepted by both %s and %s\n",
								offer.OrderID, rp.r.AcceptedBy, drv.userID)
						}
					}
					drv.mu.Lock()
					drv.acceptedOrder = offer.OrderID
					drv.mu.Unlock()
					run.mu.Unlock()

					fmt.Printf("[DRIVER %d] ACCEPTED order %s\n", drv.idx, offer.OrderID)
				}
			}
		}(d)
	}

	// Wait for results or timeout
	fmt.Println("Waiting for orders to be matched (max 60s)...")
	deadline := time.Now().Add(60 * time.Second)
	for {
		run.mu.Lock()
		allDone := true
		matched := 0
		for _, r := range run.results {
			if r.Errored || r.NoDriver {
				continue
			}
			if r.Accepted.IsZero() {
				allDone = false
			} else {
				matched++
			}
		}
		run.mu.Unlock()
		if allDone || time.Now().After(deadline) {
			fmt.Printf("Done: %d/%d orders matched\n", matched, len(run.results))
			break
		}
		time.Sleep(500 * time.Millisecond)
	}

	// Cancel location updates
	locCancel()

	// ---- Phase 5: Results ----
	fmt.Println("\n==============================================")
	fmt.Println("=== PHASE 5: RESULTS ===")
	fmt.Println("==============================================")

	var total, matched, accepted, noDriver, errored int
	var offerLatencies []float64
	var acceptLatencies []float64

	run.mu.Lock()
	for _, r := range run.results {
		total++
		if r.Errored {
			errored++
			fmt.Printf("  ORDER client-%d: ERROR %s\n", r.ClientIdx, r.ErrorMsg)
			continue
		}
		if r.NoDriver || r.OrderID == "" {
			noDriver++
			fmt.Printf("  ORDER client-%d: NO DRIVER FOUND\n", r.ClientIdx)
			continue
		}
		matched++
		offerLat := r.Offered.Sub(r.Created).Seconds()
		if !r.Offered.IsZero() {
			offerLatencies = append(offerLatencies, offerLat)
		}
		if !r.Accepted.IsZero() {
			accepted++
			acceptLat := r.Accepted.Sub(r.Created).Seconds()
			acceptLatencies = append(acceptLatencies, acceptLat)
		}
	}
	run.mu.Unlock()

	fmt.Println()
	fmt.Printf("Total orders created:     %d\n", total)
	fmt.Printf("Orders matched (offered): %d\n", matched)
	fmt.Printf("Orders accepted:          %d\n", accepted)
	fmt.Printf("No driver found:          %d\n", noDriver)
	fmt.Printf("Errored:                  %d\n", errored)
	fmt.Println()

	if len(offerLatencies) > 0 {
		sort.Float64s(offerLatencies)
		p50 := percentile(offerLatencies, 50)
		p95 := percentile(offerLatencies, 95)
		max := offerLatencies[len(offerLatencies)-1]
		fmt.Printf("Time to offer: p50=%.2fs p95=%.2fs max=%.2fs\n", p50, p95, max)
	}
	if len(acceptLatencies) > 0 {
		sort.Float64s(acceptLatencies)
		p50 := percentile(acceptLatencies, 50)
		p95 := percentile(acceptLatencies, 95)
		max := acceptLatencies[len(acceptLatencies)-1]
		fmt.Printf("Time to accept: p50=%.2fs p95=%.2fs max=%.2fs\n", p50, p95, max)
	}

	// ---- Phase 6: DB verification ----
	fmt.Println("\n=== PHASE 6: DB CORRECTNESS VERIFICATION ===")
	if err := verifyDB(ctx, *flagDBDSN); err != nil {
		fmt.Fprintf(os.Stderr, "DB verification ERROR: %v\n", err)
	}

	fmt.Println("\n=== Load test complete ===")
}

func percentile(data []float64, p int) float64 {
	if len(data) == 0 {
		return 0
	}
	idx := int(math.Ceil(float64(p)/100.0*float64(len(data))) - 1)
	if idx < 0 {
		idx = 0
	}
	if idx >= len(data) {
		idx = len(data) - 1
	}
	return data[idx]
}
