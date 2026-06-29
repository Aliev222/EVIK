package http

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

type rateBucket struct {
	count   int
	resetAt time.Time
}

type RateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*rateBucket
}

func NewRateLimiter() *RateLimiter {
	return &RateLimiter{buckets: make(map[string]*rateBucket)}
}

// StartCleanup removes expired buckets every 5 minutes until ctx is done.
func (rl *RateLimiter) StartCleanup(ctx context.Context) {
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				rl.evictExpired()
			case <-ctx.Done():
				return
			}
		}
	}()
}

func (rl *RateLimiter) evictExpired() {
	now := time.Now()
	rl.mu.Lock()
	defer rl.mu.Unlock()
	for k, b := range rl.buckets {
		if now.After(b.resetAt) {
			delete(rl.buckets, k)
		}
	}
}

// allow increments the counter for key and reports whether the request is
// within the limit. Returns (true, 0) when allowed; (false, retryAfter) when
// the bucket is exhausted.
func (rl *RateLimiter) allow(key string, maxPerMin int) (bool, time.Duration) {
	now := time.Now()
	rl.mu.Lock()
	defer rl.mu.Unlock()

	b, ok := rl.buckets[key]
	if !ok || now.After(b.resetAt) {
		rl.buckets[key] = &rateBucket{count: 1, resetAt: now.Add(time.Minute)}
		return true, 0
	}
	if b.count >= maxPerMin {
		return false, time.Until(b.resetAt)
	}
	b.count++
	return true, 0
}

func extractClientIP(r *http.Request) string {
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if idx := strings.Index(fwd, ","); idx >= 0 {
			return strings.TrimSpace(fwd[:idx])
		}
		return strings.TrimSpace(fwd)
	}
	addr := r.RemoteAddr
	if idx := strings.LastIndex(addr, ":"); idx >= 0 {
		return addr[:idx]
	}
	return addr
}

func writeRateLimitError(w http.ResponseWriter, retryAfter time.Duration) {
	secs := int(retryAfter.Seconds()) + 1
	w.Header().Set("Retry-After", fmt.Sprintf("%d", secs))
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusTooManyRequests)
	fmt.Fprintf(w, `{"error":"Too many requests. Try again in %d seconds."}`, secs)
}

// RateLimitByIP limits requests per unique client IP address.
func RateLimitByIP(limiter *RateLimiter, maxPerMin int) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := "ip:" + extractClientIP(r)
			if ok, retryAfter := limiter.allow(key, maxPerMin); !ok {
				writeRateLimitError(w, retryAfter)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// RateLimitByPhone limits requests per phone number extracted from the JSON
// request body. Falls back to client IP when no phone is present.
func RateLimitByPhone(limiter *RateLimiter, maxPerMin int) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := "ip:" + extractClientIP(r)
			if r.Body != nil {
				body, err := io.ReadAll(r.Body)
				_ = r.Body.Close()
				r.Body = io.NopCloser(bytes.NewReader(body))
				if err == nil {
					var payload struct {
						Phone string `json:"phone"`
					}
					if json.Unmarshal(body, &payload) == nil && payload.Phone != "" {
						key = "phone:" + payload.Phone
					}
				}
			}
			if ok, retryAfter := limiter.allow(key, maxPerMin); !ok {
				writeRateLimitError(w, retryAfter)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
