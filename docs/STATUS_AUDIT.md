# Авро (EVIK) — Current-State Audit

**Date:** 2026-08-02 · **Scope:** working tree on disk, `main` branch (dirty), macOS.
**Method:** static code trace + raw commands. Every claim cites `file:line` or raw output. Items that need a running Go toolchain / Postgres / Redis are marked **NOT VERIFIED**.

Environment caveats (verified up front):
- Go toolchain **not installed** on this Mac (`which go` → not found; also absent from `/usr/local/go`, Homebrew, `~/go`). Docker absent. → backend build/tests can't run here.
- `psql` / `redis-cli` / `pg_isready` not installed → no live DB/Redis checks.
- Flutter present (`/Users/rasul/flutter/bin/flutter`); `flutter analyze` ran for real.

---

## SECTION 1 — BUILD HEALTH

### Backend: `go build ./...` && `go test ./...` — NOT VERIFIED
Raw output:
```
(eval):1: command not found: go
exit: 127
(eval):1: command not found: go
exit: 127
```
Compilation status inferred statically only (one **certain compile-blocking logic bug** found, see accept_order swapped args in §4/§7 — it compiles but is wrong; no static evidence of non-compiling Go code).

### Frontend: `flutter analyze` — 147 issues, **1 real error in project code**
Raw tail: `147 issues found. (ran in 7.6s)`, exit code 1.

**Real errors (in `lib/`, excludes vendored `build/**` noise):**
- `lib/features/client/presentation/screens/client_history_screen.dart:136:30` — **error • Undefined name 'ScrollCacheExtent'** (`scrollCacheExtent: ScrollCacheExtent.pixels(200)` — neither the class nor a `scrollCacheExtent` parameter exists on `ListView.separated`; the Flutter API is `cacheExtent: double`). This file is modified and uncommitted in the working tree → **the app does not compile right now.**

Everything else flagged as "error" (≈140) lives in `build/ios|macos/SourcePackages/firebase_messaging-16.2.2/test|example/**` — vendored package sources leaked into analysis scope; not your code. (Fix by excluding `build/**` in `analysis_options.yaml`.)

Project warnings (not errors): unused field `_random` (`lib/features/driver/presentation/providers/new_driver_provider.dart:111`), deprecated/`visibleForTesting` uses in `lib/test_main.dart:29,159`.

### Important TODO/FIXME markers (trivial skipped)
| Where | What |
|---|---|
| `backend/internal/app/dispatch_scheduler.go:285` | Phase 3: offer client a price raise instead of `no_driver_found` |
| `backend/internal/usecase/payment/yookassa_verifier.go:53` | trusted-proxy (X-Real-IP) config needed on VPS move — webhook IP verification caveat |
| `backend/migrations/20260601_init_schema.sql:554` | down-migration must be replaced with explicit DROPs before launch |
| `frontend/lib/core/storage/key_value_storage.dart:15` | storage not persistent — replace with SharedPreferences/SecureStorage |
| `frontend/lib/features/order/screens/payment_confirmation_screen.dart:201` | card charge is a stub until acquiring provider (Точка/Cyclops) is live — PATCH only persists the choice |
| `frontend/lib/features/driver/presentation/providers/driver_earnings_provider.dart:85,90,95` | B-48 rubles/kopecks unit mismatch worked around with `/100` |
| `frontend/lib/main.dart:29,110` | old order-completion route kept commented "until review screen is confirmed" |
| `frontend/lib/features/client/presentation/screens/client_home_screen.dart:302` | UTF-8 encoding bug in geocoding response |
| `frontend/lib/core/error/global_error_handler.dart:31,50` | no crash analytics, errors not surfaced to user |

---

## SECTION 2 — END-TO-END FLOW (traced from code)

1. **Registration / OTP — ✅ works.** `POST /auth/otp/request` → `auth_handler.go:233` (6-digit code, sha256 hash stored, 10-min TTL, `auth_handler.go:260`); `POST /auth/otp/verify` → `auth_handler.go:285` (consumes OTP, auto-creates user, issues JWT pair + refresh session). Rate-limited (router.go:59-60). Frontend: `features/auth/presentation/auth_screen.dart` + `sms_verification_screen.dart`. Caveat: no real SMS provider anywhere in the backend — the code is only delivered via `debug_otp` in the response when `APP_ENV != production` (`auth_handler.go:268-270`) or via `OTP_FIXED_CODE`. **In production nobody receives the code → login impossible until an SMS gateway is integrated.** ⚠️ for prod.
2. **Client geolocation / home — ✅ works.** Runtime permission requested (`client_home_screen.dart:42,161`; `location_service.dart:160-176` handles denied/deniedForever), position with accuracy fallback (`location_service.dart:43-56`). No hardcoded Moscow fallback remains (grep for `55.75`/Moscow → no hits). Note: `tracking_screen.dart:58,67` still defaults to Makhachkala coords (42.9764/47.5024) when no driver position.
3. **Create order — ⚠️ partial.** `POST /orders` (client role, router.go:72) → `create_order.go:80`: price computed **server-side in kopecks** ✅ (`pricing/entity.go:12-14` "in kopecks", `tariff.CalculatePrice` `entity.go:62-80`; client's `pricing_service.dart` is display-only). Tow-truck type validated ✅ (`order/entity.go:20-27`, winch/platform/manipulator). **Blocked wheels + comment: collected in UI (`vehicle_selection_screen.dart:65,91`; `order_flow_provider.dart:198-203,437-446` builds a notes string) but the notes are never put into the HTTP body (`http_order_repository.dart:32-56` — no `notes` key) and the backend `Order` entity has no field for it (`order/entity.go:29-54`). Silently dropped — driver never sees them.** ❌ for this sub-feature. Also: distance for pricing is straight-line haversine, not road distance (`pricing/service.go:98-117`).
4. **Dispatch — ✅ works (offer-only, one driver).** `DispatchScheduler` ticks every 2s (`dispatch_scheduler.go:110-156`), expires pending offers, picks **one** candidate (`candidates[0]`, `dispatch_scheduler.go:209-210`), creates a single offer with TTL (default 15s, settings-clamped 5-60s, `dispatch_scheduler.go:307-316`), sends via WS `hub.SendToDriver` + FCM push (`dispatch_scheduler.go:246-281`). No auto-assign anywhere in `create_order.go` (comment at 179-181 confirms). Escalates radius 2→15 km, then `no_driver_found` (`dispatch_scheduler.go:283-305`).
5. **Driver accept — ✅ works (requires active offer).** `POST /orders/{id}/accept` → `accept_order.go:129-134`: rejects when `GetActiveForOrderAndDriver` returns none. Atomic claim: `AcceptOrder` SQL `WHERE status='searching' AND driver_id IS NULL` (`order_repository.go:95-111`), driver assignment + offer resolution in one tx (`accept_order.go:136-154`). **But the busy-driver recovery path is dead code — swapped arguments** (see §4).
6. **Live tracking — ❌ broken on the client side.** Driver→server works: driver app sends `location_update` with `order_id` (`realtime_location_service.dart:143-151`); server ingests, throttles 2s, saves to Redis, publishes `driver_location` event with lat/lng/user_id (`order_ws_handler.go:184-245`); relay sends it to the order's client (`order_event_relay.go:88-94`). **Server→client rendering fails:** backend emits `{"type":"driver_location", "payload":{...}}` (`event.go:16`, `pubsub.go:20-25`), but (a) the client's `WsEventDispatcher` has no case for `driver_location` — it hits `default:` "event ignored" (`event_dispatcher.dart:86-107`); (b) `RealTimeLocationService` listens for `driver_location_update` with a `location` wrapper that the backend never sends (`realtime_location_service.dart:224-226,267-274`; grep of backend for `driver_location_update|driver_found|new_order_assigned|initial_state` → 0 emitters). `TrackingScreen`'s marker feed is exclusively that dead stream (`tracking_screen.dart:74-91`). Interpolation (`tracking_screen.dart:56-72`) and bearing-based rotation (`animated_driver_marker.dart:127-136,162-165`) are implemented but receive no data. The HTTP fallback (`driverLocationStreamProvider` polling every 5s, `driver_location_provider.dart:46-60`, `http_driver_repository.dart:177-182`) is **not consumed by any screen** (grep for `driverLocationProvider|driverETAProvider` in screens/widgets → 0 hits). Bearing/speed sent by driver are also discarded server-side (`order_ws_handler.go:233-242` publishes only lat/lng).
7. **arrive → in_progress — ✅ works.** Driver app posts `arrived` / `in_progress` (`new_driver_provider.dart:295,314` → `POST /orders/{id}/status`, `http_driver_repository.dart:142-144`); state machine enforces order (`state_machine.go:31-60`); direct `completed` via /status is rejected — must use `/finalize` (`update_status.go:11,27-29`).
8. **complete → awaiting_payment — ✅ works.** Driver `POST /orders/{id}/finalize` with final price (`new_driver_provider.dart:337`, `finalize_order.go:41-86`): ownership + `in_progress` checked, price>0, transitions to `awaiting_payment`, event + push to client.
9. **Client pays cash — ⚠️ works for the money, leaks the driver.** `POST /orders/{id}/confirm-payment` → `finance.go:376-406`: cash → `CompleteOrderFinancially` (transactional, idempotent, `payment_repository.go:475-533`) → `completed` + event. **But the driver is never released**: `FinanceUseCase.driverRepo` (with `ReleaseOrder`) is declared (`finance.go:84,94,120`) and never called — no `ReleaseOrder` call exists anywhere in `usecase/payment/` (grep). `drivers.current_order_id` stays set; driver remains busy (details §4).
10. **Review — ✅ works.** `driver_rating_screen.dart:30-54` → `http_review_repository.dart:29` `POST /api/v1/reviews` → `adminHandler.CreateReview` (router.go:116; insert into `driver_reviews`, `admin_repository.go:540`). Skippable ("Пропустить", `driver_rating_screen.dart:117`).
11. **Driver freed — ❌ broken.** Nothing frees the driver on completion (step 9). Compensations that exist: driver toggling offline→online releases terminal orders (`set_status.go:114-119,257-269`); accept-time recovery would release a stale terminal order but is **dead due to swapped args** (§4); stuck-order reaper only releases drivers for orders stuck in `accepted` (`stuck_order_reaper.go:193-224`), and the presence reaper explicitly **skips** drivers with a `current_order_id` (`driver_presence_reaper.go:98-101`). Net effect: after each completed order the driver stays "busy" until they manually go offline and online again.

---

## SECTION 3 — KNOWN GAPS / MISSING

- **ETA to client — placeholder.** `driverETAProvider` = straight-line haversine ÷ assumed 30 km/h, clamped 2-60 min (`driver_location_provider.dart:70-86`), with `heading: 0, speed: 30` hardcoded (`:37-38`) — and no screen consumes it. `TrackingScreen._calculateETA` feeds off the dead WS stream (§2.6). Backend OSRM routing (`routing/service.go:24-153`, real durations) is exposed only to drivers (`router.go:124-125`).
- **Route polyline — real for both, but half-wired.** Driver: backend OSRM via `/routing/orders/{id}/route` ✅. Client: `TrackingScreen` fetches an OSRM route preview directly from the app (`tracking_screen.dart:122-139`, `openstreetmap_service.dart` `getRoutePreview`) — real road polyline, **but it only refreshes on driver-location updates from the dead stream, so in practice it never draws during tracking.**
- **Driver info to client — ✅ wired.** `GET /drivers/{id}/profile` returns full_name, phone, vehicle_plate/model/type, rating, avatar_url (`driver_handler.go:128-144,536-553`); client fetches on assignment (`order_flow_provider.dart:401-416`) and `driver_info_screen.dart:76-133` renders phone (call/SMS), vehicle, rating.
- **Payment card/SBP — stubbed at two levels.** (1) `YOOKASSA_STUB_MODE=true` only skips prod config validation (`config.go:197-201`); **nothing else consumes the flag** (grep `YooKassaStubMode` outside config.go → 0 hits). The real client is always constructed (`container.go:205`) and with empty creds every card operation returns "not configured" (`yookassa_client.go:86,194`). So current deploy = cash only. (2) The in-app card sheet TODO says the acquiring provider isn't live (`payment_confirmation_screen.dart:201-203`). **Cash path works end-to-end** (§2.9, minus driver release). SBP: no SBP-specific code found anywhere.
- **Push notifications — FCM real-or-noop, no RuStore.** `FIREBASE_CREDENTIALS_JSON` empty (or init error) → `NoopSender` silently (`container.go:212-219`, `fcm/sender.go:243-248`). With credentials, offers/status changes push to the backgrounded driver/client (`dispatch_scheduler.go:266-280`, `update_status.go:78-104`, `finalize_order.go:88-106`). Without them, a backgrounded driver misses offers entirely (WS only). No RuStore push. Device token endpoints exist (`auth_handler.go:561-641`).
- **OTP rate limiting — present.** `RateLimitByPhone(limiter, 3)` on request, `5` on verify (`router.go:59-60`), 1-minute in-memory buckets (`rate_limiter.go:66`). Caveats: in-memory (resets on restart, per-instance), and `/auth/register` + `/auth/refresh` have no limiter (`router.go:57,62`).
- **No SMS provider at all** (see §2.1) — the biggest functional gap for a production launch.

---

## SECTION 4 — RELIABILITY / DATA INTEGRITY

- **Reapers present and wired — ✅ confirmed.** Constructed in `container.go:303-319`, returned at `:330`, started in `cmd/app/main.go:56-60` (`Scheduler`, `ExpansionScheduler`, `DispatchScheduler`, `DriverPresenceReaper`, `StuckOrderReaper`). Behavior: presence reaper offlines stale drivers without orders (`driver_presence_reaper.go:83-107`); stuck reaper cancels expanded-searching and stale-accepted orders (atomically releasing the driver, `stuck_order_reaper.go:193-224`), flags arrived/in_progress/awaiting_payment.
- **Active-order restoration — ✅ both sides.** Client: `order_flow_provider.dart:527-578` (`restoreActiveFlow`: SharedPreferences order-id → `GET /orders/{id}` → resume step + payment state; caveat: depends on locally-saved id, doesn't use `GET /orders/active` which exists at `router.go:74`). Driver: `new_driver_provider.dart:129-146` restores via `getActiveOrder` (`http_driver_repository.dart:149-159`, scans accepted/arrived/in_progress).
- **WebSocket heartbeat — ✅ aligned.** Server: protocol ping every 75s, read deadline 90s reset on pong (`order_ws_handler.go:20-24,153-156`); Dart's WebSocket auto-answers protocol pings. Client also sends an app-level `'HEARTBEAT'` string every 15s (`websocket_client_io.dart:71-73`) — the server fails to JSON-parse it and logs a warning **every 15s per client** (`order_ws_handler.go:167-171`): harmless but log spam. Reconnect: exponential backoff 1s→30s (`websocket_client_io.dart:106-124`) reusing the URL that carries `access_token` (`order_provider.dart:44-47`); the provider rebuilds the URL when the token refreshes, but a reconnect *during* an outage reuses the possibly-expired token (15-min TTL, `config.go:98`) until auth state changes.
- **Swallowed errors on money/state paths (file:line):**
  - **`accept_order.go:157` — swapped arguments (worst one):** call is `tryRecoverAndRetry(ctx, orderID, driverID, now)` but the signature is `(ctx, driverID, targetOrderID, now)` (`accept_order.go:212`). The function looks up a *driver* by *order-ID*, always fails, returns false — so a driver stuck with a stale terminal order can never accept a new one via this path (compounds the driver-release gap below). Not a compile error; pure logic bug.
  - **`finance.go` never calls `driverRepo.ReleaseOrder`** — field declared `finance.go:84,94,120`, zero call sites (grep) → driver not freed on cash or card completion (webhook path `finance.go:317-330` has the same gap).
  - `order_ws_handler.go:233` — `_ =` on publishing `driver_location` (acceptable: best-effort).
  - `stuck_order_reaper.go:158,213` — `_ =` on event publish after state change (state persisted; clients may miss the WS event).
  - `create_order.go:113-126` — order-created event published from a goroutine after a 500 ms sleep with only a log on failure; also if pricing fails (`create_order.go:139-142`) the already-inserted order row stays `created` with `price_total=0` forever (no cleanup path — the stuck reaper only handles `searching`+expanded).
  - Frontend: `payment_confirmation_screen.dart:168` (poll continues — by design), `order_flow_provider.dart:565,575` (restore best-effort — commented), `client_order_provider.dart:200,220` (silent catches worth a look).
- **Money multi-writes in transactions — ✅ confirmed.** `CompleteOrderFinancially`: single tx, `SELECT ... FOR UPDATE` on the order, idempotency-key check before any write (`payment_repository.go:475-533`); webhook processing wrapped in `WithWebhookTx` with processed-event dedup (`finance.go:263-346`); accept order+driver+offer in one tx (`accept_order.go:136-154`); payment repo shows 7+ BeginTx/Commit pairs (`payment_repository.go:69-418`). Live behavior NOT VERIFIED (no DB running).

---

## SECTION 5 — CONFIG / DEPLOY

**Required for prod start** (`config.go:169-205`, `log.Fatal` on violation when `APP_ENV=production`):
- `JWT_SECRET` — ≥32 chars, not the dev default
- `ALLOWED_ORIGINS` — non-empty
- `ADMIN_USER_ID`, `ADMIN_PASSWORD` (≥12 chars)
- `S3_ENDPOINT`/`S3_BUCKET`/`S3_ACCESS_KEY`/`S3_SECRET_KEY`/`S3_PUBLIC_BASE_URL` — unless `S3_STUB_MODE=true`
- `YOOKASSA_SHOP_ID`/`YOOKASSA_SECRET_KEY` — unless `YOOKASSA_STUB_MODE=true`
- Must **not** be set in prod: `OTP_FIXED_CODE` (`config.go:173-175`), `DRIVER_GATE_BYPASS` (`:176-178`), `DEBUG_MODE` (`:84-86`)
- Effectively required too: `POSTGRES_DSN`/`DATABASE_URL` and `REDIS_URL`/`REDIS_ADDR` (defaults point at localhost, `config.go:93-96`). `FIREBASE_CREDENTIALS_JSON` optional (noop sender otherwise).

**What the stub flags actually do — validation-only, nothing is stubbed:**
- `YOOKASSA_STUB_MODE` / `S3_STUB_MODE` are consumed **only** in `validateProductionConfig` (`config.go:192-201`); grep across `internal/` finds no other consumer. With stub mode on: card payments/payouts return "yookassa is not configured" errors at runtime (`yookassa_client.go:86,135,194`); document storage is `nil` → driver document upload unavailable (`admin_handler.go:223-237`). Cash orders and everything non-S3/non-card still work. NPD (tax) provider is a permanent stub pending FNS agreement (`container.go:236-239`).

**Blocking a clean prod boot:** nothing in code, provided the env list above is set — validation is fail-fast by design. Boot NOT VERIFIED live (no Go toolchain/DB here). Functional blockers after boot: no SMS delivery for OTP (§2.1), stub modes disable cards + driver docs.

---

## SECTION 6 — SECURITY QUICK-CHECK

- **Hardcoded secrets — none found.** `grep -rn "AIza|pk_live|sk_live|BEGIN PRIVATE KEY" backend/internal backend/cmd frontend/lib admin-web` → 0 hits; `grep -rn "password=|secret=" backend/internal backend/cmd frontend/lib` → 0 hits. Dev defaults exist but are prod-blocked: `JWT_SECRET` default `evik-dev-insecure-secret` (`config.go:97`, rejected in prod at `:180-181`); localhost DSN default (`config.go:93`).
- **OTP debug exposure — ✅ guarded.** `debug_otp` returned only when `exposeOTPCodes && fixedOTPCode == ""` (`auth_handler.go:268-270`), and `exposeOTPCodes` is wired as `!cfg.IsProduction()` (`container.go:268`). Extra prod hardening: weak-code blocklist (`auth_handler.go:36-40,298-304`), `OTP_FIXED_CODE`/`DEBUG_MODE` fatal in prod (`config.go:84-86,173-175`).
- **Findings worth fixing:**
  - `http_order_repository.dart:57` — `debugPrint('Token: ...')` logs the **JWT access token** on every order creation (reaches logcat/console in debug and profile builds).
  - `auth_handler.go:305-310` — when `DEBUG_MODE=true` OTP verification is **skipped entirely** (any 6 digits log you in). Correctly fatal in prod (`config.go:84-86`), but dangerous on any staging box reachable from the internet.
  - WS auth accepts the JWT as a URL query param (`order_ws_handler.go:92-95`) — tokens can end up in proxy/access logs; standard risk, acceptable short-term.

---

## SECTION 7 — TOP PRIORITIES

**BLOCKER**
1. `frontend/lib/features/client/presentation/screens/client_history_screen.dart:136` — `ScrollCacheExtent` doesn't exist; **the Flutter app does not compile** (uncommitted local edit; use `cacheExtent: 200`).
2. Client live tracking is dead end-to-end: backend emits `driver_location` (`order_event_relay.go:88-94`) but the app ignores it (`event_dispatcher.dart:105-107`) and `TrackingScreen` listens only to a never-fired legacy stream (`realtime_location_service.dart:224`, `tracking_screen.dart:74-91`). Clients never see the truck move — core product promise.
3. No SMS provider integration — in production (`debug_otp` hidden, `auth_handler.go:268`) no user can ever receive an OTP; registration is impossible.

**HIGH**
4. `backend/internal/usecase/order/accept_order.go:157` — swapped `orderID`/`driverID` args into `tryRecoverAndRetry` (sig at `:212`): stale-busy-driver recovery never works.
5. `backend/internal/usecase/payment/finance.go:376-426` — completion (cash & card, also webhook `:317-330`) never calls `driverRepo.ReleaseOrder` (declared `:84`, zero call sites): every completed order leaves its driver "busy" until a manual offline/online toggle — combined with #4, drivers effectively lock up after each ride.
6. Stub modes stub nothing: `YOOKASSA_STUB_MODE`/`S3_STUB_MODE` only relax validation (`config.go:192-201`); card payments error at runtime (`yookassa_client.go:86`) and driver document upload is nil'd out (`admin_handler.go:223-237`). Decide: real creds, or actual stub implementations.

**MEDIUM**
7. Blocked-wheels count + client comment collected in UI but silently dropped — never serialized (`http_order_repository.dart:32-56`) and no backend field (`order/entity.go:29-54`); drivers arrive uninformed.
8. Pricing uses straight-line haversine (`pricing/service.go:98-117`) while OSRM road routing already exists (`routing/service.go`) — systematic underpricing on real roads.
9. ETA shown to client is a placeholder (30 km/h haversine, `driver_location_provider.dart:70-86`) fed by nothing; wire it to OSRM durations after fixing #2.
10. `http_order_repository.dart:57` — stop logging the access token.
11. `create_order.go:98-142` — pricing failure strands a `created`/price-0 order row forever (no reaper covers `created`).
12. Go toolchain absent on this machine — backend build/test cannot be verified anywhere locally; install Go (go.mod pins toolchain 1.26.5 per commit dc3a8a7) or rely on Docker CI.

**LOW**
13. Client app-level `'HEARTBEAT'` string makes the server log a parse warning every 15s per connection (`order_ws_handler.go:167-171`) — send `{"type":"ping"}` instead.
14. WS reconnect during an outage reuses a possibly expired token embedded in the URL (`websocket_client_io.dart:115-117`, 15-min TTL) — refresh token before reconnect.
15. Exclude `build/**` in `frontend/analysis_options.yaml` to de-noise `flutter analyze` (≈140 phantom errors from vendored firebase_messaging).
16. `tracking_screen.dart:58,67` — hardcoded Makhachkala fallback coords; `key_value_storage.dart:15` — non-persistent storage TODO; `test_main.dart:29,159` — deprecated/protected API usage.

---

*Audit only — no code was changed. DB/Redis-dependent runtime behavior remains NOT VERIFIED on this machine.*
