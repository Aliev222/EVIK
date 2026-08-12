package payment

import (
	"net/http"
	"testing"
)

// Adversarial coverage for the webhook source verification and event parsing
// on top of finance_webhook_test.go and webhook_integration_test.go.

// webhookTestRequest builds a minimal *http.Request the same way the real
// router does (RemoteAddr + optional X-Real-IP header).
func webhookTestRequest(remoteAddr, xRealIP string) *http.Request {
	req := &http.Request{RemoteAddr: remoteAddr}
	if xRealIP != "" {
		req.Header = http.Header{}
		req.Header.Set("X-Real-IP", xRealIP)
	}
	return req
}

// TestYooKassaVerifier_RejectsForgedSources extends the forged-IP coverage
// from TestWebhook_YooKassaVerifier_ForgedIP with IPv6, malformed remote
// addresses and range-edge IPs.
func TestYooKassaVerifier_RejectsForgedSources(t *testing.T) {
	verifier := NewYooKassaVerifier()

	tests := []struct {
		name    string
		remote  string
		xrip    string
		wantErr bool
	}{
		// IPv4 outside the allowlist
		{name: "non-yookassa ipv4", remote: "203.0.113.1:443", wantErr: true},
		{name: "yookassa ipv4 range edge", remote: "185.71.76.0:443", wantErr: false},
		{name: "ipv4 one above allowlist block", remote: "185.71.76.32:443", wantErr: true},
		{name: "private rfc1918", remote: "10.0.0.5:443", wantErr: true},
		// IPv6 outside/inside the allowlist 2a02:5180::/32
		{name: "non-yookassa ipv6", remote: "[2001:db8::1]:443", wantErr: true},
		{name: "yookassa ipv6 allowlisted", remote: "[2a02:5180::1]:443", wantErr: false},
		// Malformed remote addresses
		{name: "remote without port", remote: "203.0.113.1", wantErr: true},
		{name: "remote garbage", remote: "not-an-ip", wantErr: true},
		{name: "empty remote", remote: "", wantErr: true},
		// x-real-ip that is NOT allowlisted while remote is attacker-controlled
		{name: "spoofed non-allowlisted x-real-ip", remote: "203.0.113.1:443", xrip: "203.0.113.9", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := verifier.Verify(webhookTestRequest(tt.remote, tt.xrip), nil)
			if tt.wantErr && err == nil {
				t.Error("expected error, got nil")
			}
			if !tt.wantErr && err != nil {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}
}

// TestYooKassaVerifier_XRealIPBypass documents a source-verification bypass:
// clientIPFromRequest (yookassa_verifier.go:56) trusts the X-Real-IP header
// unconditionally and never cross-checks the caller RemoteAddr. A remote
// attacker who POSTs directly to /webhooks/yookassa with an allowlisted
// X-Real-IP (e.g. 185.71.76.1) passes the check. Safe only when a trusted
// reverse proxy overwrites X-Real-IP (see TODO B-01 in the source).
func TestYooKassaVerifier_XRealIPBypass(t *testing.T) {
	verifier := NewYooKassaVerifier()

	// Attacker from an arbitrary internet IP spoofs an allowlisted X-Real-IP.
	forged := webhookTestRequest("203.0.113.1:443", "185.71.76.1")
	if err := verifier.Verify(forged, nil); err != nil {
		t.Fatalf("forged request rejected: %v", err)
	}

	// The identical request WITHOUT the spoofed header must be rejected.
	plain := webhookTestRequest("203.0.113.1:443", "")
	if err := verifier.Verify(plain, nil); err == nil {
		t.Fatalf("baseline remote request accepted without X-Real-IP, want rejection")
	}
}

// TestYooKassaVerifier_ParseEvent_MalformedPayload proves malformed webhook
// bodies are rejected at parse time and never reach the money pipeline.
func TestYooKassaVerifier_ParseEvent_MalformedPayload(t *testing.T) {
	verifier := NewYooKassaVerifier()

	bad := [][]byte{
		nil,
		[]byte(""),
		[]byte("not json"),
		[]byte(`{"event":`),            // truncated
		[]byte(`{"event": 42}`),        // wrong type
		[]byte(`{"object":{"id": 7}}`), // object.id is a number, not a string
	}

	for _, body := range bad {
		if _, err := verifier.ParseEvent(body); err == nil {
			t.Errorf("ParseEvent(%q) = nil error, want rejection", string(body))
		}
	}
}

// TestYooKassaVerifier_ParseEvent_MissingObjectID characterizes how the parser
// tolerates payloads without a payment object: the EventID becomes
// "payment.succeeded:" and the payment id is empty. Flagged because the
// handler does not validate these fields before touching CheckProcessed.
func TestYooKassaVerifier_ParseEvent_MissingObjectID(t *testing.T) {
	verifier := NewYooKassaVerifier()
	ev, err := verifier.ParseEvent([]byte(`{"event":"payment.succeeded"}`))
	if err != nil {
		t.Fatalf("ParseEvent errored: %v", err)
	}
	if ev.PaymentID != "" {
		t.Errorf("PaymentID = %q, want empty", ev.PaymentID)
	}
	if ev.EventID != "payment.succeeded:" {
		t.Errorf("EventID = %q, want %q", ev.EventID, "payment.succeeded:")
	}
}

// TestVerify_NilRequestPanics documents the crash hazard when Verify receives
// a nil *http.Request: clientIPFromRequest dereferences r.Header. In the real
// router a valid request is always passed (so this is defensive), but a nil
// request crashes instead of returning a clean error.
func TestVerify_NilRequestPanics(t *testing.T) {
	verifier := NewYooKassaVerifier()
	defer func() {
		if r := recover(); r == nil {
			t.Log("Verify(nil) returned without panic")
		}
	}()
	_ = verifier.Verify(nil, nil)
}