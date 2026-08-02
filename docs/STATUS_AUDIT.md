# STATUS AUDIT — Авро / EVIK (unified main)

**Date:** 2026-08-03
**By:** principal engineer audit (read-only, no code changed)
**Host:** macOS zsh. Go / Docker / Postgres / Redis are **not installed** on this Mac.
⇒ Any claim that requires compiling Go or querying a running DB is marked **NOT VERIFIED** (static source review only).

Legend: ✅ works-as-intended (static evidence) · ⚠️ partial/risky · ❌ broken/missing · **NOT VERIFIED** = needs Go/DB to confirm.

---

## SECTION 1 — BUILD HEALTH

### `flutter analyze` (frontend/, raw)
```
Analyzing frontend...
   info • overrideWithProvider is deprecated … Use overrideWith instead • lib/test_main.dart:29:29 • deprecated_member_use
warning • The member 'state' can only be used within 'package:state_notifier/state_notifier.dart' or a test • lib/test_main.dart:159:39 • invalid_use_of_visible_for_testing_member
warning • The member 'state' can only be used within instance members of subclasses of 'StateNotifier' • lib/test_main.dart:159:39 • invalid_use_of_protected_member
3 issues found.
```
- All 3 issues are in `lib/test_main.dart` (a test helper misplaced under `lib/`). **0 issues** in real app code.
- `build/**` is excluded (`frontend/analysis_options.yaml:13`), so `flutter analyze` is effectively **clean** for shipping code.

### TODO / FIXME / HACK markers
Backend (3, all low-impact):
- `backend/migrations/20260601_init_schema.sql:554` — TODO about explicit DROP TABLE before a down migration.
- `backend/internal/usecase/payment/yookassa_verifier.go:53` — TODO(B-01): trusted-proxy IP (nginx X-Real-IP) when on VPS.
- `backend/internal/app/dispatch_scheduler.go:285` — TODO(Phase 3): offer price-upsell instead of `no_driver_found`.

Frontend (10 markers, mostly intentional):
- `lib/main.dart:29,110` — removable "when review screen is confirmed" (review screen now exists).
- `lib/core/storage/key_value_storage.dart:15` — TODO: replace in-memory KV with SharedPreferences/SecureStorage. **(persistent-store note)**
- `lib/core/error/global_error_handler.dart:31,50` — TODOs crash-analytics + snackbar.
- `lib/features/client/presentation/screens/client_home_screen.dart:302` — TODO: fix UTF-8 in geocoding.
- `lib/features/order/screens/payment_confirmation_screen.dart:201` — TODO(T-point/Cyclops): real card charge (see §2).
- `lib/features/driver/presentation/providers/driver_earnings_provider.dart:85,90,95` — TODO(B-48): DriverStats ruble /100 normalization.

**Build verdict:** Flutter ✅ clean. Go build **NOT VERIFIED** (no Go toolchain).

---

## SECTION 2 — END-TO-END FLOW

### 1. Registration / OTP — ⚠️ (workflow present, delivery broken in production)
- `POST /auth/otp/request` → `AuthHandler.RequestOTP` `backend/internal/transport/http/auth_handler.go:233`; generates 6-digit code (random `:497` or fixed), stores **hashed** in `phone_otps` (`:255-265`), 10-min expiry.
- `POST /auth/otp/verify` → `auth_handler.go:285`; `ConsumePhoneOTP` one-time `:306`; auto-creates user if absent `:311-330`.
- **Security guards ✅** (`config.go:83-88,169-205`): rejects weak codes in prod (`auth_handler.go:298-304`), `DEBUG_MODE` fatal in prod, weak-JWT/test admin rejects.
- **CRITICAL gap ❌:** there is **no SMS/OTP delivery gateway anywhere** in the codebase (`grep -i sms/twilio/vonage…` → only an admin `[sms-stub]` log `admin_handler.go:1373-1375`). The OTP is never actually sent to a phone. In non-prod it is echoed back via `debug_otp` (`auth_handler.go:268-270`); in prod `fixedOTPCode` is forbidden (`config.go:173-175`), so **production users can never receive the code** → OTP path is effectively non-functional in production. Working fallback is password `Register`/`Login`.
- Rate limiting: ✅ wired per-phone (`router.go:59-60`): OTP request 3/min, verify 6/min.
- NB: full DB persistence/consume behavior **NOT VERIFIED** (no Postgres).

### 2. Geolocation — ✅
Geolocator/Geocoding present (client `location_service.dart`, OSM geocoding + OSRM routing). Not the focus of a blocker.

### 3. Create order (type · blocked wheels · comment · server-side price in kopecks) — ✅ with a caveat
- Client request: `frontend/.../http_order_repository.dart:32-58` sends `pickup_lat/lng, dropoff_lat/lng, payment_method, auto_dispatch, is_mock, tow_truck_type, pickup/dropoff_address, notes`.
- Backend: `CreateOrderHandler` `order_handler.go:177-239` → `CreateOrderUseCase` `create_order.go:81-184`; **price computed server-side** from route distance → `ord.PriceTotal = calculation.TotalPrice` **in kopecks** (`create_order.go:146`), then `TransitionTo(searching)` + publish `create_order.go:155-175`.
- **Blocked wheels caveat ⚠️:** there is **no structured `blocked_wheels` DB column** (grep `blocked_wheels` in backend → 0 hits). Client packs it into the free-text `notes` string — `order_flow_provider.dart:441-443` → `"Заблокировано колес: N"`, shipped as `order.notes` (`http_order_repository.dart:56-58`) → stored as `orders.notes` (`order_repository.go:22,52`). Driver re-parses it back out of the free text with a substring match (`http_driver_repository.dart:330-33x _blockedWheelsFromNotes`). Works end-to-end but is a **fragile text-encoding hack**, not a typed field.

### 4. Dispatch — offer to ONE driver — ✅
- `DispatchScheduler` `dispatch_scheduler.go`: takes `candidates[0]` only (`:209-210`), creates exactly one offer per round `createOffer :218-244`, excludes already-offered drivers per round (`:177`), expires → next round (`:136-144`), falls back to `no_driver_found` after rounds `:283-305`. Offer timeout default 15 s (`:85`), max radius 15 km / step 2 km (`:103-104`).

### 5. Accept — requires an active offer — ✅
- `accept_order.go:127-134` **requires** `offerResolver.GetActiveForOrderAndDriver(...)` to return a live offer for that driver+order, else errors (`"no active offer …"`).
- ⚠️ In the `ErrDriverBusy` recovery path the arguments are **still swapped** — see §3 item 2.

### 6. Live tracking — driver_location — ✅ **RESOLVED (was broken before)**
- Server: driver WS `location_update` with `data.order_id` → `OrderWSHandler.handleLocationUpdate` `order_ws_handler.go:185-250` (requires `Role=="driver"` `:186`, reads `order_id` `:143/231`), saves location, publishes `EventDriverLocationUpdated` (`type="driver_location"`) `:243-247`.
- Relay: `order_event_relay.go:88-93` → `hub.SendToUser(clientUserID)`.
- Client: **handles `driver_location`** `core/services/realtime_location_service.dart:224` → `_handleServerDriverLocation` `:271-290`, emits `DriverLocationUpdate` to `_driverLocationController` `:38`.
- Client map render with interpolation + rotation: `tracking_screen.dart:100-105` (subscribe), `:171-198` (`_interpolatedDriverLat/Lng` with easeInOut), `:284-312` (`driverMarker`: truck/truck_loaded icon, rotation from bearing, route overlay). The official marker shown only when `_latestDriverLocation != null && _currDriverPos != null` `:284`.
→ The previously-flagged "client drops driver_location as unknown" is **fixed**.

### 7. arrive / on_way / in_progress — ✅
- Client `updateOrderStatus` `http_order_repository.dart:186-194` (maps status), server `update_status.go:26-71` validates state machine + publishes event + pushes to client.

### 8. finalize → awaiting_payment — ✅
- `FinalizeOrderUseCase` `finalize_order.go:41-86` (in_progress→awaiting_payment, sets `PriceTotal = FinalPrice` kopecks, publishes + push).

### 9. awaiting_payment → pay cash (confirm-payment) / card — ⚠️
- Cash: `ConfirmOrderPayment` `finance.go:393-405` → completes finances + `Completed`.
- Card: `CreateOrderPayment` `finance.go:…`, YooKassa webhook path `HandleProviderWebhook` `finance.go:257-348` (transactional via `WithWebhookTx`).
- ❌ **Frontend card charge is a placeholder:** `payment_confirmation_screen.dart:197-206` — comment "…creating a real charge… For now the PATCH only persists the choice." So the client never drives a real 3DS/YooKassa confirmation flow today. Cash works; card payment is not wired end-to-end on the UI.

### 10. review — ✅ `order_review_screen.dart` present (client). // backend review API at `/reviews` (OK).

### 11. Driver freed after completion — ⚠️ **NOT RESOLVED (see §3 item 1)**

---

## SECTION 3 — KNOWN GAPS re-check (on OLD code, now re-verified on main)

1. **Driver released on completion? — NOT RESOLVED.**
   - The completion paths in `finance.go` do **not** call `driverRepo.ReleaseOrder`:
     - cash/subdirect: `finance.go:393-405` (CompleteOrderFinancially → `UpdateStatus(Completed)`; no Release).
     - card: `finance.go:412-423`.
     - webhook: `finance.go:326-344` (order → Completed; no Release).
   - `ReleaseOrder` is only invoked in: `set_status.go:262,268,277` (driver toggling), `cancel_order.go:41`, `update_status.go:49` (only when going through UI /status, which finalization forbids for Completed), `accept_order.go:227,238` (recovery), and `stuck_order_reaper.go:203` (accepted only).
   - `StuckOrderReaper` **never** releases a `Completed` driver; it only flags `arrived/in_progress/awaiting_payment` and auto-cancels `accepted`. `releasesDriver()` in `update_status.go:107` returns true for Completed, but that code path is a separate route from the finance completion.
   ⇒ After cash/webhook/card completion the driver's `CurrentOrderId` stays held; they stay `busy` until they toggle offline→online (`set_status.go:257-269`). **Medium operational bug**, previously flagged, still present.
   - (DB-level behavior NOT VERIFIED without Postgres.)

2. **accept_order.go `tryRecoverAndRetry` — the arguments are STILL swapped vs signature.**
   - Signature: `func (uc *AcceptOrderUseCase) tryRecoverAndRetry(ctx, driverID string, targetOrderID string, now time.Time)` `accept_order.go:212`.
   - Call: `uc.tryRecoverAndRetry(ctx, orderID, driverID, now)` `accept_order.go:157`.
   - ⇒ Inside the body, `driverRepository.GetByID(ctx, driverID)` receives **orderID** (`:213`), and `currentOrderID == targetOrderID` compares against the **driverID** (`:219`). The recovery path looks up the driver-repo by an order ID. Logic mismatch — previously flagged, still present. (Runtime consequence NOT VERIFIED; static arg mismatch is factual.)

3. **Blocked-wheels count + comment in `notes`:**
   - Client serializes `notes`: ✅ `http_order_repository.dart:56-58`.
   - Backend `Order` has `Notes` field + stores it: ✅ `entity.go:53`, `create_order.go:94`, `order_repository.go:22,52 ... insert + scan).
   - BUT structured `blocked_wheels` column/target field: ❌ none (see §2.3). It is encoded into/from free text. **Partially resolved — notes flow, but wheels count is a text-hack.**

4. **Tracking `driver_location` handled on client — ✅ RESOLVED** (see §2.6).

5. **ETA / route — real (OSRM) or placeholder — ✅ real.**
   - Backend: `OSRMRoutingService` `routing/service.go:37-89`, base URL `router.project-osrm.org`, GeoJSON polyline `:120-149`, real distance/duration/steps.
   - Client: `OpenStreetMapService.getRoutePreview` hits OSRM (`openstreetmap_service.dart:134`, `app_constants.dart:18/20`); used in `tracking_screen.dart:176`. Not a straight line. **RESOLVED.**

6. **Push notifications — FCM (real), not RuStore.**
   - `fcm/sender.go` wraps the Firebase Admin SDK (real, `firebase.google.com/go/v4`), `NewNoop` for local/dev (`backend/.../fcm/sender.go`). Requires `FIREBASE_CREDENTIALS_JSON` secret (`config.go:138`).
   - ⚠️ No RuStore / Huawei PushKit — in Russia, Google FCM delivery is unreliable, so push delivery risk is a real production concern. **Code exists, delivery to RU unreliable** — NOT VERIFIED (need a real device/Emdley).

7. **OTP rate limiting — ✅ RESOLVED**: `router.go:59-60` per-phone limits (3/min req, 5/min verify) + weak-code block in prod + one-time consume.

---

## SECTION 4 — RELIABILITY

- **Reapers / background jobs wired — ✅** `backend/cmd/app/main.go:55-60`: `Scheduler` (balance release + stuck payouts), `ExpansionScheduler`, `DispatchScheduler`, `DriverPresenceReaper`, `StuckOrderReaper` all running; `RateLimiter.StartCleanup` `:61`.
- **Driver-presence reaper:** `driver_presence_reaper.go` exists (NOT VERIFIED runtime), `DriverPresenceGracePeriod` config `config.go:127`.
- **Stuck-order reaper:** `stuck_order_reaper.go` (Ø flags arrived/in_progress/awaiting_payment; auto-cancels accepted/searching) — limited, see §3.1.
- **Active-order restoration — ✅ client both sides:** client `order_flow_provider.dart:29,537-586` (reads `_activeOrderIdKey` from SharedPreferences + payment status); driver `new_driver_provider.dart:130-170` (`getActiveOrder`, reconnects as driver, `restoreOrder`, `goOnline`).
- **WS heartbeat alignment — ✅** server handles `"ping","pong","heartbeat"` `order_ws_handler.go:175-177`; client pings with `"ping"/heartbeat` `websocket_client_channel.dart:73`/`websocket_client_io.dart:73`. PingSide aligned (both sides accept). — 2s → 15s. Server pingPeriod 75s, pong wait 90s (`order_ws_handler.go:21-23`).

- **Swallowed/ignored errors on money/state paths — ⚠️**
  - Webhook completion: financial+order state is wrapped in `WithWebhookTx` (transactional) `finance.go:263`. Good. Broadcast failure after commit logged `CRITICAL` `:341-343` (non-fatal, intentional).
  - HTTP `/confirm-payment` (cash/card UI path) is **not an atomic transaction** — `CompleteOrderFinancially(ctx)` then `orderRepo.UpdateStatus(...)` as **two separate DB ops** `finance.go:393-423`. A crash between them → finances completed but order still `awaiting_payment` (or vice versa). **Medium money-atomicity risk.** Re-dispatch scheduler can crowd new orders meanwhile.
  - Many publisher calls are best-effort `log…`+continue (dispatch `:233,236`, etc.) — acceptable (order already persisted in Postgres).

- **Money multi-write in a transaction — ⚠️:** webhook path yes (`WithWebhookTx`); manual `/confirm-payment` path sequence no (see above). Finalize order handles its own single `Update` — ok.

---

## SECTION 5 — SECURITY QUICK-CHECK

- **No hardcoded secrets — ✅ (config is env-driven)**
  - `AIza:` → only `frontend/android/app/google-services.json:18` (Firebase config payload, expected for FCM). Nothing else commits a Google key.
  - `pk_live`/`sk_live`: none.
  - `BEGIN …PRIVATE KEY`: none committed.
  - JWT secret default is a throwaway dev value (`config.go:97`) but **refused in production** by `validateProductionConfig` (`config.go:180-182` requires ≥32 chars, non-default). Same guards for admin password, S3/YooKassa credentials (`config.go:169-205`). ✅

- **Access token no longer logged — ✅ RESOLVED (both files)**
  - `order_provider.dart` — removed (line removed; no `debugPrint('Token:…')` remains). Grep for `accessToken`+log prints → 0 hits.
  - `http_order_repository.dart` — `debugPrint('Token: …')` removed earlier; `import 'package:flutter/foundation.dart';` also dropped. Clean. ✅

- **OTP debug code guarded by `APP_ENV != production` — ✅**
  - `config.go:80-86` (`isProduction`), `:88` gate `driverGateBypass` = `otpFixedCode != "" && !isProduction`; `:140` `AllowMockLocation` default `!isProduction`; `:83-85` `DEBUG_MODE` fatal if production; `validateProductionConfig` rejects `OTP_FIXED_CODE` `:173-175`. `debug_otp` echo only when `exposeOTPCodes` (`auth_handler.go:268-270`). ✅

---

## SECTION 6 — TOP PRIORITIES

**RESOLVED (previously flagged)**: notes client serialize + backend Notes column; client handling of `driver_location`; OSRM real ETA/route; OTP rate-limit + weak-code guards; reapers wired; access-token logging removed in both files.

**BLOCKER**
- Production OTP can never be delivered — no SMS/OTP delivery gateway exists; `debug_otp`/`fixedOTPCode` are dev-only and refused in prod. (`auth_handler.go:245-271`, `config.go:148,173-175`). Block auth-by-OTP in prod; only password register/login works.

**HIGH**
- 2 `accept_order.go:157` vs `:212` — swapped `tryRecoverAndRetry(orderID, driverID)` args: recovery path queries driver-repo using an order ID. Active-order surgery when a driver's `busy` goes sideways.
- 2 `finance.go:393-423` `/confirm-payment` cash/card money-order multi-write is not in one transaction (webhook path is). Crash between `CompleteOrderFinancially` and `UpdateStatus(Completed)` → inconsistent state.

**MEDIUM**
- 3. Driver not released on completion in money paths (§3.1). Keeps drivers `busy` until manual offline/online. Combine with a reaper/transition release for `Completed`.
- 4. Blocked-wheels count is free-text-hack (`Order` order-line) rather than a real column (`order_flow_provider.dart:441-443`, `http_driver_repository.dart:330`). Fragile across text changes.
- 5. Client has no real card/3DS charge — payment UI only persists the method (`payment_confirmation_screen.dart:201-203`). Card collection E2E incomplete.

**LOW**
- 6. `key_value_storage.dart:15` in-memory store (persist tokens safely with SecureStorage).
- 7. `client_home_screen.dart:302` UTF-8 geocoding bug.
- 8. FCM-only push, no RuStore/PSP — RU device delivery unreliable.
- 9. `lib/test_main.dart` misplaced under `lib/` (Flutter analyze shows 3 warnings there) — it to `test/` skip inference issues.

---

*All file:line refs are to the current working tree on `main` (commit `5b0cbef`). Backend run/lint/DB behavior labeled NOT VERIFIED was not executed (no Go/Docker on this host). Audit was read-only — no code changed.*