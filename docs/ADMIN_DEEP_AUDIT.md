# ADMIN DEEP AUDIT — Avro (EVIK) admin panel & backend money/moderation paths

Adversarial principal-engineer + security review. Every finding cites `file:line`.
Where a claim needs a running DB it is marked **NOT VERIFIED** with the code-based risk.
No fixes were applied — this is diagnosis only.

Scope: `backend/internal` (Go) admin routes + `admin-web/` (Go proxy + static JS).
Money = kopecks (`int64` / `NUMERIC`).

---

## SECTION 1 — AUTHORIZATION & SECURITY

### 1.1 Every admin endpoint is behind admin auth — VERIFIED
All admin routes are mounted under `secured.Route("/admin", ...)` with
`admin.Use(RequireRoles(auth.RoleAdmin))` (`router.go:127-128`), and the whole `secured`
group sits behind `AuthMiddleware` (`router.go:66-67`). Read back the full route table:
`router.go:129-180` covers overview, driver verification approve/reject/block + batch,
orders, finance refunds/payouts/export, tax profiles, cities, drivers, finance-v2,
settings, audit-log. Money/approval endpoints are all admin-protected. **VERIFIED.**

### 1.2 Can a normal user token hit admin endpoints? — No escalation path found, VERIFIED
`RequireRoles` trusts the `role` JWT claim read from context (`auth_middleware.go:37-56`).
Only `AdminLogin` mints `RoleAdmin` (`auth_handler.go:382`) and it requires a
constant-time match against the configured admin id/password (`auth_handler.go:376-377`).
No other token-issuing path can produce the `admin` role:
- Register: `role` must be `client`/`driver` (`auth_handler.go:184`).
- Password Login: same restriction (`auth_handler.go:127`).
- OTP verify: `phone, 6-digit code and valid role` — restricted to client/driver (`auth_handler.go:294`).
- Refresh: re-signs from the **refresh-token claims** (`auth_handler.go:417-446`) — cannot upgrade a client/driver into admin.
- JWT library pins `HS256` and refuses other alg (`tokens.go:100-117`).

Residual risks (NOT VERIFIED against live config):
- Admin auth is a **single static env password** (`config.go:25`, `auth_handler.go:26-47`),
  brute-force login limited only to 5 req/min/IP (`router.go:61`). Distributed brute force /
  weak password is viable. Password strength unknown.
- `debugMode` bypasses OTP consumption (`auth_handler.go:305`) and `exposeOTPCodes`
  returns the OTP in the body (`auth_handler.go:268-270`). If toggled in prod → critical, config-gated only.

### 1.3 SQL injection — none found; all dynamic SQL is parameterized, VERIFIED
Searched every `fmt.Sprintf`-built query:
- `admin_repository.go:478-506` (ListReviews): `driverQuery` bound as an arg (`:467-469`),
  `strings.Join` only of `$N` placeholders. Safe.
- `admin_repository.go:820-831, 863-884, 913-923, 952-973` (wallets/tx/subscriptions/audit): same pattern, args bound. Safe.
- `order_repository.go:655-800` (ListAdminOrders): `argRef` placeholders, values are args. Safe.
- `payment_repository.go:1147-1213` (ListAdminRefunds), `:1277-1296` (ExportFinanceReport):
  report type is a **whitelist map key** (`:1292-1295`), never concatenated into SQL. Safe.
- `driver_repository.go:411-414` (FindNearestAvailable): driver IDs are placeholders + args. Safe.

**Verdict: no injection.** Values never reach SQL text; only generated `$N` refs are interpolated.

### 1.4 Input validation on money/approval admin writes — **weak**
| Endpoint | Validation | Verdict |
|---|---|---|
| `PUT /admin/settings` (`settings_handler.go:27-45`) | **none** — no key whitelist, no range, no type check | **HIGH** — can write commission/subscription prices ≤0 |
| `POST /admin/finance/refunds` (`payment_handler.go:723-735`) | amount >0 in usecase (`finance.go:628-630`) only | payment-status/over-refund uncapped → see §2.1 |
| `POST /admin/finance/payouts/{id}/approve` (`payment_handler.go:844-867`) | none at handler; repo debits unbounded | negative balance → see §2.2 |
| `POST /admin/finance/payouts/{id}/reject` | reason ≥8 chars (`payment_handler.go:897-900`) | ok |
| `POST /admin/moderation/batch/approve` (`admin_handler.go:1160-1192`) | **no vehicle validation** (`admin_handler.go:1325-1341` requires it) | approve can carry empty vehicle |
| `POST /admin/tax-profiles/{id}/verify` | none (status-only) | ok |
| `PATCH /admin/cities/{id}` | `is_active` bool only | deactivation not gated on active orders |
| `POST /admin/finance/export` | type whitelisted | ok |
| `GET /admin/*` limits | clamped (`admin_handler.go:1674-1714`) | ok |

### 1.5 Secrets / PII in responses — no credential leaks found, VERIFIED
`log.Printf` calls log order/driver/payout ids and errors, no credentials. `admin-web`
stores the JWT in `localStorage` (`admin-web/static/app.js:182-188`) and is served by a
reverse proxy (`admin-web/main.go:56-75`) that adds **no CSP/security headers** — one
un-escaped injection point in the hand-rolled HTML template = token theft. Proxied requests
pass the Authorization header straight through to the backend. No auth added in the proxy
itself (fine, since backend enforces it).

## SECTION 2 — MONEY PATHS

### 2.1 Refunds — **they never execute** (CRITICAL functional money hole)
`AdminCreateRefund` → `financeUC.CreateRefund` (`finance.go:627-643`) only INSERTs a row in
status `created` (`payment_repository.go:1268-1275`). Grep across all non-test Go code finds:
- a provider refund call: **none** (YooKassa client has no refund method wired here),
- a scheduler/reaper that turns `created→succeeded`: **none** (`app/*` only handles balances & stuck payouts).

So an admin clicking "Создать refund" (`admin-web/static/app.js:3778`) gets HTTP 201 + `"Refund создан"`
while **no money moves**. The refund row sits forever. If an executor is ever added, the idempotency
key is `refund:{paymentID}:{amount}:{reason}` (`finance.go:639`) — a **different reason string yields a
different key**, so `ON CONFLICT (idempotency_key)` (`payment_repository.go:1272`) does **not** dedupe,
and there is **no `CHECK`/cap** tying `SUM(refunds.amount) ≤ payment.amount`, **no** requirement that the
payment is `succeeded`. Latent **double-refund / over-refund**; currently masked by the fact nothing runs.
**Status: author of the logic correct for exact-replay only; the money path is broken.**

### 2.2 Payout approval can push the wallet **negative** (HIGH/CRITICAL)
- `payoutIsApprovable` includes **`failed`** (`payment_repository.go:1126`). A payout that failed
  at the provider may be approved by admin.
- `ApprovePayout` debits `available_balance = available_balance - amount` **unconditionally**, with no
  `available >= amount` guard (`payment_repository.go:1003`); wallet columns have **no `CHECK >= 0`**
  (`migrations/20260601_init_schema.sql:255-257`).
- Concrete: driver has 300₽; a 400₽ payout failed ("failed"); admin approves it → balance = -100₽, and the
  platform "paid out" 400₽ it never had confirmed.

### 2.3 Multiple in-flight payouts double-spend the same balance — CRITICAL
`CreatePayout` checks `available_balance >= amount` but **does not reserve/debit** funds
(`payment_repository.go:869-878`). The default client-side idempotency key is
`payout:{driverID}:{amount}:{now.Unix()}` (`finance.go:502-504`) — two requests in different seconds
yield two distinct keys, both INSERT. Admin approving both debits `amount` twice against the single
balance → **negative balance**. No reservation/lock of pending payouts exists.

### 2.4 Transactionality — money moves are single-tx, GOOD
`CompleteOrderFinancially` (`payment_repository.go:487-608`) — wallet + order + driver release in one
`BeginTx/Commit`. `MarkPayoutPaid`/`ApprovePayout`/`RejectPayout` each lock row `FOR UPDATE`
(`payment_repository.go:982`, `1065`). **At-least-once gap** on card payment: `CreatePayment` hits the
provider before the local `INSERT` (`finance.go:184-206`); if the insert fails the provider holds a live
charge with no local row, and the idempotent webhook `UpdatePaymentFromProvider` returns ErrPaymentNotFound,
so the event is never marked processed (`finance.go:275-285`). **NOT VERIFIED live; code path allows it.**

### 2.5 Tariff edit bounds — NOT reachable via admin API, GOOD
`router.go` exposes only `GET /pricing/tariffs` (`router.go:120-121`); there is **no** admin tariff
create/update/delete route. So "admin sets price_per_km to 0/negative" is **not reachable over HTTP**.
**BUT** subscription prices = editable via `PUT /admin/settings` with no bounds and consumed unclamped:
`subscriptionAmount` does `int64(v)` with no range check (`finance.go:697-726`) — a 0/negative value
makes a driver "pay" 0 or breaks `CreatePayout` inserting payment. Commission, by contrast, is clamped
0..100 (`finance.go:359-363`).

## SECTION 3 — DRIVER MODERATION EDGE CASES

### 3.1 Approve/reject idempotency — VERIFIED-ish, but no "must be pending" precondition
`DecideAccount` is a blind `UPDATE ... SET status = $2` with no expected-status clause
(`admin_repository.go:324-386`). Approve-an-approved and reject-an-rejected are stable. But because there
is no precondition, an admin can **re-approve a driver who was rejected/blocked** without a new document
submission; the gate immediately passes again (`IsDriverDocumentsApproved` =
`user_repository.go:364-368` → table status). Approve→reject→approve rapidly is idempotent in outcome but
re-grants work rights with no re-review. MEDIUM.

### 3.2 Block/reject does NOT stop active work — MEDIUM/HIGH (launch-critical)
`DecideDriverVerification` writes **only** `driver_verifications.status`
(`admin_repository.go:353-360`). Blocking/rejecting does **not**:
- set `drivers.status = offline`,
- clear `drivers.current_order_id`, or
- cancel/reassign the active order.

Consequences:
- A blocked driver keeps their in-flight order; `CompleteOrderFinancially` ignores verification status, so
  order completes and income is credited (`payment_repository.go:487-608`). The funds then sit un-­withdrawable
  while blocked (the payout gate `EnsureCanRequestPayout` → `gate.go:63-81` checks docs approved).
- Matching keeps offering orders to them: `FindNearestAvailable` filters `status='online'`
  (`driver_repository.go:411-414`) and `IsAvailable` checks only `online && no current` (`driver_repository.go:282-290`);
  verification is **not** consulted in dispatch (`dispatch_scheduler.go:194`, `matching/service.go:88`).
  The driver receives offer pushes but acceptance is blocked at the handler gate (`order_handler.go:517-522` → 403).
  A blocked driver is therefore not removed from the live dispatch pool.

### 3.3 driver_verifications vs usable state — one split-brain source
- Gate reads table `driver_verifications` (`is_approved`); driver list derives "blocked"/"moderation" from it
  (`admin_repository.go:399-406`); these agree. OK.
- Two competing write paths to the same table: `UpsertDriverVerification` keys on `id` (`admin_repo.go:282-322`)
  vs `CreateVerification` keys on `user_id` for `ON CONFLICT` (`driver_verification_repository.go:99-105`).
  If the driver app created the record (so `id` is a fresh UUID ≠ `user_id`), an admin `SubmitDriverVerification`
  for the same user does `INSERT` with `id = user_id` while `user_id` is a **unique index** (`migrations/…:520`)
  → `ERORR: duplicate key` → 500 on every re-submit. Data-path split between moderation and the app.

## SECTION 4 — DATA CONSISTENCY / CASCADES

### 4.1 Delete service area — geo check ≠ FK; delete of any referenced area 500s
`ServiceAreaRepo.Delete` refuses only if **geo ancestor orders** via pickup/dropoff bbox
(`service_area_repository.go:22-31`, `:180-186`) — it ignores `orders.city_id`. Meanwhile `orders.city_id`
is `REFERENCES service_areas(id)` with default `NO ACTION` (`migrations/…/20260601_init_schema.sql:191`).
So:
- deleting an area that ever had an **order** (any status) hits the FK, returns a raw **internal error / 500**,
  not a clean 409 — the geographic osSent check passes but FK blocks (`service_area_repository.go:188`).
- `PATCH is_active=false` (`city_handler.go:224-253` → `service_area_repository.go:164-171`) is **not** gated,
  so a city with live orders can be deactivated mid-flight (new orders stop, in-flight continue) — arguably intended.

### 4.2 Delete tariff type — not reachable, GOOD (see §2.5).

### 4.3 Minimal DB guards — NOTE
Money columns (`payouts.amount`, `refunds.amount`, `wallet_transactions.amount`, `payments.amount`,
`driver_wallets.*_balance`, `pricing_tariffs.*`) have **no CHECK >= 0** and negative values can be stored;
the guard must live in code, and §2.2/2.3 show code does not guard.

## SECTION 5 — ERROR HANDLING & FAILURE MODES

### 5.1 Endpoints that swallow/leak
- Batch approve/reject (`admin_handler.go:1160-1236`): per-item errors collected into a `results` array and
  HTTP **200 is returned even when every item failed**. Confirmed partial/full failure invisible in bulk.
- `AdminCreateRefund`: **all** errors → 400 with the raw error string (`payment_handler.go:729-732`), so an
  internal DB failure is mis-reported to the caller as a client error and leaks detail.
- `AdminFinanceReport` / `AdminExportFinance`: errors → 400 with raw text (`payment_handler.go:750, :774`).
- `HideReview/ShowReview/DeleteReview`: missing row → 500 with raw error, not 404 (`admin_handler.go:482-535`).
- Stuck-payout reaper (`app/scheduler.go:73-85`): only `log.Printf("CRITICAL: …")`, never resolves or marks —
  a payout stranded in `created` (provider call crashed mid-flight) is permanent until an admin acts. Funds
  aren't reserved, so no double-spend, but no auto-recovery.

### 5.2 Partial failure mid-batch — batch not transactional (see 5.1). No rollback; duplicate ids → duplicate audit rows.

### 5.3 admin-web false success — NOT FOUND, VERIFIED
`api.request` throws when `!res.ok` (`admin-web/static/app.js:163-169`) and every action handler wraps in
try/catch with `toast(e.message,'error')`: approve `2707-2711`, reject `2722-2726`, tax `2795-2799`,
payout approve/reject `3467`/`3479`, refund `3778-3779`, review `3846-3857`, city toggle `3245/3254`.
**Caveat:** refund modal literally warns "возврат у провайдера может быть … зависит от backend"
(`app.js:3772`) and then shows `toast('Refund создан','success')` — which, per §2.1, is a false success
in every case since refunds never execute.

## SECTION 6 — RANKED FINDINGS

### CRITICAL
1. **Refunds never execute** — a recorded `created` row + 201 to admin; no provider call/reaper.
   `payment_handler.go:723-735`, `finance.go:627-643`, `payment_repository.go:1268-1275`. Fix: call the
   provider or expose "recorded only".
2. **Payout double-spend / negative balance** — `CreatePayout` doesn't reserve funds (`payment_repository.go:869-878`)
   + `ApprovalPayout` debits unconditionally with `failed` approvable (`payment_repository.go:1003`, `:1126`);
   no DB CHECK. Scenario: two 400₽ requests against 500₽ then approve both.
3. (family) **(unbounded final price)** — driver can demand an arbitrarily large `final_price` (only >0 checked,
   `order_handler.go:643-645`, `finalize_order.go:52-57`); no cap vs estimate → arbitrary client charge / over-invoice.
   Driver-facing, not admin, but on the same money rails.

### HIGH
4. `PUT /admin/settings` fully unvalidated (`settings_handler.go:27-45`); subscription prices → 0/negative
   (`finance.go:697-726`). Only commission is clamped.
5. Block/reject does not stop active work or remove driver from dispatch (`driver_repository.go:282-290`,
   `:411-414`; `dispatch_scheduler.go:194`); blocked driver keeps order + offers.
6. Empty-vehicle approvals via batch approve (`admin_handler.go:1160-1192`) while single approve enforces
   vehicle data (`admin_handler.go:1325-1341`).
7. Service-area delete 500s via FK instead of clean gating (`service_area_repository.go:180-196`); PATCH
   deactivate not gated vs active orders.

### MEDIUM
8. No "must be pending" precondition on decideDriverVerification → re-approve rejected driver (admin_repository.go:324-358).
9. Card payment provider-charge-before-local-insert with webhook that never resolves the orphan
   (`finance.go:184-206`, `:275-285`). NOT VERIFIED live.
10. Verification write path collision (admin Upsert vs app Create) on unique `user_id` → 500
    (`admin_route.go:282-318`, `driver_verification_repository.go:91-139`).
11. Refund error mapping 400 + raw leak (`payment_handler.go:729-732`).

### LOW
12. `minimumWithdrawal` never enforced in `RequestDriverPayout` (`finance.go:483-543`) → 1-cop payout accepted.
13. HideReview/Show/Delete → 500 not 404 on missing row (`admin_handler.go:482-500`).
14. `GetOrderReview`/`GetDriverReviews` readable by any authenticated non-admin user (`router.go:76`, `91`).
15. `adminRefundItemJSON` always `"order_id":""` (`payment_handler.go:923`).

### Actually-fine (credited)
- No SQL injection anywhere (all `$N`-arg parameterized). ✓
- All `/admin/*` guarded by admin role + JWT (`router.go:127-128`). ✓
- No role-escalation to admin (`auth_handler.go:127,184,294`). ✓
- Payout/reject single-turn txs with FOR UPDATE (`payment_repository.go:982,1065`). ✓
- Admin rate limit on `/auth/admin/login` (`router.go:61`). ✓
- Export report type whitelisted, not injected (`payment_repository.go:1277-1296`). ✓