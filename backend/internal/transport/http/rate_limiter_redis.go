package http

import (
	"context"
	"log"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

// windowSeconds is the size of the fixed window shared by every rate-limit
// bucket. The middleware enforces per-phone (3/min) and per-IP budgets; all of
// them ride on top of the same window.
const windowSeconds int64 = 60

// allowScript atomically increments the bucket, refreshes its TTL and returns
// the new count plus the remaining TTL in seconds. Wrapping INCR and EXPIRE in
// a single script removes the reset race of a plain INCR+EXPIRE pair, where
// two concurrent requests that both observe a fresh key could both skip the
// EXPIRE and leave a permanent (never resetting) counter.
var allowScript = redis.NewScript(`
local count = redis.call('INCR', KEYS[1])
redis.call('EXPIRE', KEYS[1], tonumber(ARGV[1]))
local ttl = redis.call('TTL', KEYS[1])
return {count, ttl}
`)

// RedisLimiter is a distributed fixed-window rate limiter backed by Redis.
// Counters live in Redis keyed per minute-bucket, so every instance pointing at
// the same Redis enforces one shared budget per key — the property needed to
// scale OTP/register throttling across replicas.
//
// Fail-open policy: any Redis error is logged and the request is allowed. On a
// transient Redis outage the limit is not enforced (degraded, not fail-locked),
// which is the right trade-off for the protected endpoints: blocking every OTP
// request because the counter store hiccuped would be worse than briefly
// overrunning the per-key budget. The production default stays in-memory; the
// Redis backend is joined only via an explicit RATE_LIMITER_BACKEND=redis.
type RedisLimiter struct {
	client *redis.Client
	logger *log.Logger
}

// NewRedisRateLimiter builds a Redis-backed Limiter. logger is used purely for
// the fail-open diagnostics; pass log.New(io.Discard, ...) if logging is not
// wanted in tests.
func NewRedisRateLimiter(client *redis.Client, logger *log.Logger) *RedisLimiter {
	return &RedisLimiter{client: client, logger: logger}
}

// keyFor maps the middleware bucket key ("ip:.."/"phone:..") onto a
// namespaced, per-minute Redis key. The minute component makes each window a
// fresh key that resets without any coordination between instances.
func (rl *RedisLimiter) keyFor(key string) string {
	return "rl:" + key + ":" + time.Now().UTC().Format("200601021504")
}

// Allow implements Limiter.
func (rl *RedisLimiter) Allow(ctx context.Context, key string, maxPerMin int) (bool, time.Duration) {
	res, err := allowScript.Run(ctx, rl.client, []string{rl.keyFor(key)}, strconv.FormatInt(windowSeconds, 10)).Result()
	if err != nil {
		rl.logger.Printf("WARN: rate limiter redis error for %q: %v — allowing request (fail-open)", key, err)
		return true, 0
	}
	raw, ok := res.([]interface{})
	if !ok || len(raw) < 2 {
		rl.logger.Printf("WARN: rate limiter redis returned unexpected reply for %q — allowing request (fail-open)", key)
		return true, 0
	}
	count, countOK := raw[0].(int64)
	ttl, ttlOK := raw[1].(int64)
	if !countOK || !ttlOK {
		rl.logger.Printf("WARN: rate limiter redis returned unexpected value types for %q — allowing request (fail-open)", key)
		return true, 0
	}
	if count > int64(maxPerMin) {
		retryAfter := time.Duration(ttl) * time.Second
		if retryAfter <= 0 || retryAfter > time.Minute {
			retryAfter = time.Minute
		}
		return false, retryAfter
	}
	return true, 0
}
