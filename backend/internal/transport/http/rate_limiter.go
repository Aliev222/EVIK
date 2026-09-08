package http

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

type rateBucket struct {
	count   int
	resetAt time.Time
}

// Limiter is the rate-limiter abstraction consumed by the HTTP middleware. It
// allows swapping the in-memory implementation for a distributed one (e.g.
// Redis) without touching the middleware or router.
type Limiter interface {
	// Allow increments the counter for key and reports whether the request is
	// within the limit. Returns (true, 0) when allowed; (false, retryAfter)
	// when the bucket is exhausted. ctx is honored by implementations that do
	// network I/O (e.g. Redis) and ignored by the in-memory one.
	Allow(ctx context.Context, key string, maxPerMin int) (bool, time.Duration)
}

// CleanupLimiter is implemented by limiters that need periodic background
// eviction of stale state (currently only InMemoryLimiter). The Redis limiter
// relies on key expiry and needs no cleanup.
type CleanupLimiter interface {
	StartCleanup(context.Context)
}

type InMemoryLimiter struct {
	mu      sync.Mutex
	buckets map[string]*rateBucket
}

const maxRateLimitPhoneBodyBytes int64 = 64 << 10

func NewInMemoryLimiter() *InMemoryLimiter {
	return &InMemoryLimiter{buckets: make(map[string]*rateBucket)}
}

// Deprecated: use InMemoryLimiter.
type RateLimiter = InMemoryLimiter

// Deprecated: use NewInMemoryLimiter.
func NewRateLimiter() *InMemoryLimiter {
	return NewInMemoryLimiter()
}

// StartCleanup removes expired buckets every 5 minutes until ctx is done.
func (rl *InMemoryLimiter) StartCleanup(ctx context.Context) {
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

func (rl *InMemoryLimiter) evictExpired() {
	now := time.Now()
	rl.mu.Lock()
	defer rl.mu.Unlock()
	for k, b := range rl.buckets {
		if now.After(b.resetAt) {
			delete(rl.buckets, k)
		}
	}
}

// Allow implements Limiter. ctx is ignored — the window state lives entirely
// in memory.
func (rl *InMemoryLimiter) Allow(ctx context.Context, key string, maxPerMin int) (bool, time.Duration) {
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
	return remoteIP(r.RemoteAddr)
}

func writeRateLimitError(w http.ResponseWriter, retryAfter time.Duration) {
	secs := int(retryAfter.Seconds()) + 1
	w.Header().Set("Retry-After", fmt.Sprintf("%d", secs))
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusTooManyRequests)
	fmt.Fprintf(w, `{"error":"Too many requests. Try again in %d seconds."}`, secs)
}

// RateLimitByIP limits requests per unique client IP address.
func RateLimitByIP(limiter Limiter, maxPerMin int) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := "ip:" + extractClientIP(r)
			if ok, retryAfter := limiter.Allow(r.Context(), key, maxPerMin); !ok {
				writeRateLimitError(w, retryAfter)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// RateLimitByPhone limits requests per phone number extracted from the JSON
// request body. Falls back to client IP when no phone is present.
func RateLimitByPhone(limiter Limiter, maxPerMin int) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := "ip:" + extractClientIP(r)
			if r.Body != nil {
				body, err := io.ReadAll(io.LimitReader(r.Body, maxRateLimitPhoneBodyBytes+1))
				_ = r.Body.Close()
				r.Body = io.NopCloser(bytes.NewReader(body))
				if int64(len(body)) > maxRateLimitPhoneBodyBytes {
					w.Header().Set("Content-Type", "application/json")
					w.WriteHeader(http.StatusRequestEntityTooLarge)
					_, _ = w.Write([]byte(`{"error":"request body too large"}`))
					return
				}
				if err == nil {
					var payload struct {
						Phone string `json:"phone"`
					}
					if json.Unmarshal(body, &payload) == nil && payload.Phone != "" {
						if normalized := normalizePhone(payload.Phone); normalized != "" {
							key = "phone:" + normalized
						}
					}
				}
			}
			if ok, retryAfter := limiter.Allow(r.Context(), key, maxPerMin); !ok {
				writeRateLimitError(w, retryAfter)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
