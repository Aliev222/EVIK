package http

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestTrustedProxyRealIPRejectsForwardedHeaderFromUntrustedPeer(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "203.0.113.1:4321"
	req.Header.Set("X-Real-IP", "185.71.76.1")

	var got string
	handler := TrustedProxyRealIP([]string{"127.0.0.0/8"})(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		got = extractClientIP(r)
	}))
	handler.ServeHTTP(httptest.NewRecorder(), req)

	if got != "203.0.113.1" {
		t.Fatalf("client IP = %q, want direct peer", got)
	}
}

func TestTrustedProxyRealIPAcceptsForwardedHeaderFromTrustedPeer(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "127.0.0.1:4321"
	req.Header.Set("X-Real-IP", "185.71.76.1")

	var got string
	handler := TrustedProxyRealIP([]string{"127.0.0.0/8"})(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		got = extractClientIP(r)
	}))
	handler.ServeHTTP(httptest.NewRecorder(), req)

	if got != "185.71.76.1" {
		t.Fatalf("client IP = %q, want trusted forwarded IP", got)
	}
}

func TestExtractClientIPHandlesIPv6(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "[2a02:5180::1]:443"
	if got := extractClientIP(req); got != "2a02:5180::1" {
		t.Fatalf("client IP = %q, want IPv6 without port", got)
	}
}
