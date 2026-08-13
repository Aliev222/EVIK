package http

import (
	"bytes"
	"context"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func newRedisLimiter(t *testing.T) (*miniredis.Miniredis, *RedisLimiter, *redis.Client) {
	t.Helper()
	mr := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{
		Addr:         mr.Addr(),
		MaxRetries:   0,
		DialTimeout:  500 * time.Millisecond,
		ReadTimeout:  time.Second,
		WriteTimeout: time.Second,
	})
	t.Cleanup(func() { _ = client.Close() })
	limiter := NewRedisRateLimiter(client, log.New(io.Discard, "", 0))
	return mr, limiter, client
}

// TestRedisLimiter_EnforcesLimit checks the 1:1 semantics of the in-memory
// limiter: exactly maxPerMin requests pass, the next one is denied with a
// bounded retryAfter, and unrelated keys keep their own budget.
func TestRedisLimiter_EnforcesLimit(t *testing.T) {
	_, limiter, _ := newRedisLimiter(t)
	ctx := context.Background()
	const key = "phone:+79990000001"

	for i := 0; i < 3; i++ {
		if ok, _ := limiter.Allow(ctx, key, 3); !ok {
			t.Fatalf("call #%d: denied, want allowed", i+1)
		}
	}
	if ok, retryAfter := limiter.Allow(ctx, key, 3); ok {
		t.Fatal("4th call: allowed, want denied")
	} else if retryAfter <= 0 || retryAfter > time.Minute {
		t.Fatalf("4th call retryAfter = %v, want in (0, 1m]", retryAfter)
	}

	if ok, _ := limiter.Allow(ctx, "ip:203.0.113.9", 3); !ok {
		t.Fatal("unrelated key denied, want allowed")
	}
}

// TestRedisLimiter_SetsTTL verifies every bucket carries the 60s TTL so stale
// keys are garbage-collected by Redis itself (no cleanup goroutine needed).
func TestRedisLimiter_SetsTTL(t *testing.T) {
	mr, limiter, _ := newRedisLimiter(t)
	ctx := context.Background()

	_, _ = limiter.Allow(ctx, "phone:+79990000002", 3)

	found := false
	for _, k := range mr.Keys() {
		if !strings.HasPrefix(k, "rl:phone:") {
			continue
		}
		found = true
		ttl := mr.TTL(k)
		if ttl <= 0 || ttl > time.Minute {
			t.Fatalf("key %q TTL = %v, want in (0, 1m]", k, ttl)
		}
	}
	if !found {
		t.Fatal("no rl:phone: key stored in redis")
	}
}

// TestRedisLimiter_WindowResets advances miniredis by one minute and checks the
// exhausted bucket starts fresh in the next fixed window.
func TestRedisLimiter_WindowResets(t *testing.T) {
	mr, limiter, _ := newRedisLimiter(t)
	ctx := context.Background()
	const key = "phone:+79990000003"

	for i := 0; i < 3; i++ {
		if ok, _ := limiter.Allow(ctx, key, 3); !ok {
			t.Fatalf("call #%d: denied, want allowed", i+1)
		}
	}
	if ok, _ := limiter.Allow(ctx, key, 3); ok {
		t.Fatal("4th call in same window: allowed, want denied")
	}

	mr.FastForward(time.Minute)

	if ok, _ := limiter.Allow(ctx, key, 3); !ok {
		t.Fatal("call after window reset: denied, want allowed")
	}
}

// TestRedisLimiter_SharedCounterAcrossInstances proves the counters are
// distributed: two independent limiter instances pointing at the same Redis
// enforce one global budget, which is the whole point of the Redis backend.
func TestRedisLimiter_SharedCounterAcrossInstances(t *testing.T) {
	_, _, client := newRedisLimiter(t)
	a := NewRedisRateLimiter(client, log.New(io.Discard, "", 0))
	b := NewRedisRateLimiter(client, log.New(io.Discard, "", 0))
	ctx := context.Background()
	const key = "ip:203.0.113.7"

	for i := 0; i < 3; i++ {
		l := a
		if i%2 == 1 {
			l = b
		}
		if ok, _ := l.Allow(ctx, key, 3); !ok {
			t.Fatalf("call #%d via instance: denied, want allowed", i+1)
		}
	}
	if ok, _ := a.Allow(ctx, key, 3); ok {
		t.Fatal("4th call via instance A: allowed, want denied — counters not shared")
	}
	if ok, _ := b.Allow(ctx, key, 3); ok {
		t.Fatal("4th call via instance B: allowed, want denied — counters not shared")
	}
}

// discardRedisLogger silences go-redis's global stderr logger for the
// deliberately-broken client in the fail-open test.
type discardRedisLogger struct{}

func (discardRedisLogger) Printf(context.Context, string, ...interface{}) {}

// TestRedisLimiter_FailOpenOnRedisError checks the fail-open policy: when Redis
// is unreachable the request is allowed (and logged), never rejected.
func TestRedisLimiter_FailOpenOnRedisError(t *testing.T) {
	redis.SetLogger(discardRedisLogger{})
	var logBuf bytes.Buffer
	client := redis.NewClient(&redis.Options{
		Addr:         "127.0.0.1:1", // nothing listens on port 1
		MaxRetries:   0,
		DialTimeout:  200 * time.Millisecond,
		ReadTimeout:  300 * time.Millisecond,
		WriteTimeout: 300 * time.Millisecond,
	})
	t.Cleanup(func() { _ = client.Close() })
	limiter := NewRedisRateLimiter(client, log.New(&logBuf, "", 0))

	if ok, retryAfter := limiter.Allow(context.Background(), "phone:+79990000004", 3); !ok {
		t.Fatalf("redis down: denied, want fail-open allow (retryAfter=%v)", retryAfter)
	}
	if logged := logBuf.String(); !strings.Contains(logged, "fail-open") {
		t.Fatalf("expected fail-open warning logged, got: %q", logged)
	}
}

// TestRateLimitByPhone_WithRedisLimiter wires a RedisLimiter through the real
// production middleware factory to prove the interface boundary holds end to
// end (Router → RateLimitByPhone → Limiter).
func TestRateLimitByPhone_WithRedisLimiter(t *testing.T) {
	_, limiter, _ := newRedisLimiter(t)
	router := newFocusedSecurityRouter(newTokens(time.Minute), limiter, probeOK)
	body := `{"phone":"+79990000055","role":"client"}`

	for i := 0; i < 3; i++ {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", bytes.NewBufferString(body))
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("call #%d: status %d, want 200", i+1, rec.Code)
		}
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", bytes.NewBufferString(body))
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("4th call: status %d, want 429 (body=%s)", rec.Code, rec.Body.String())
	}
}
