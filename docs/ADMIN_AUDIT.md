# Admin Panel Audit — Авро (EVIK)

Audit date: 2026-08-06. Static code audit only — no live DB/server was run. Everything
marked ✅/⚠️/❌ is inferred from tracing code paths (handler → repo → SQL); runtime
behavior (does the SQL actually execute without error against a live DB) is marked
**NOT VERIFIED** where it matters.

Admin web app: `admin-web/` — a Go binary (`admin-web/main.go`) that reverse-proxies
`/api/v1/*` and `/ws/*` to the backend and serves an embedded vanilla-JS SPA from
`admin-web/static/` (`app.js`, 4610 lines; `index.html`; `styles.css`). There is no
separate JS framework/build — it's hand-written, single-file.

---

## SECTION 1 — Inventory: what the admin panel has

18 sections, defined in `admin-web/static/app.js:29-46` (`ROUTES` array):

| Route id | Title (RU) | Group | Backend endpoint(s) called | Wired? |
|---|---|---|---|---|
| `dashboard` | Дашборд | Операции | `GET /api/v1/admin/overview` (app.js:592) | ✅ real |
| `orders` | Заказы | Операции | `GET /api/v1/admin/orders`, `GET /api/v1/admin/orders/{id}` (app.js:791,1095,1228) | ✅ real |
| `drivers` | Водители | Операции | `GET /api/v1/admin/drivers/{id}`, `.../orders`, `.../reviews` (app.js:2455-2457) | ✅ real |
| `documents` | Документы / Модерация | Операции | `GET /api/v1/admin/driver-verifications`, `POST .../moderation/driver-verifications/{id}/{approve\|reject\|request-changes\|block}` (app.js:2613,2708,2723,2682,2684) | ✅ real |
| `tax-profiles` | Налоговые профили | Операции | `GET /api/v1/admin/tax-profiles`, `POST .../verify`, `.../{reject\|request-changes}` (app.js:2735,2796,2811) | ✅ real |
| `service-areas` | Зоны работы | Операции | `GET/POST/PATCH/DELETE /api/v1/admin/cities*`, `GET /api/v1/service-areas/check` (app.js:3214-3311,2958) | ✅ real |
| `payments` | Платежи | Финансы | `GET /api/v1/admin/finance-v2/payments` (app.js:3411) | ✅ real, **read-only** — no admin action buttons in this page (verified by reading the page's render function, app.js:3395-3410 region) |
| `payouts` | Выплаты | Финансы | `GET /api/v1/admin/finance/payouts` (via `/admin/finance/{reportType}`), `POST .../payouts/{id}/{approve\|reject}` (app.js:3467,3479) | ✅ real |
| `wallets` | Кошельки | Финансы | `GET /api/v1/admin/finance-v2/wallets` (app.js:3531) | ✅ real, read-only |
| `transactions` | Транзакции | Финансы | `GET /api/v1/admin/finance-v2/transactions` (app.js:3610) | ✅ real, read-only |
| `subscriptions` | Подписки | Финансы | `GET /api/v1/admin/finance-v2/subscriptions` (app.js:3685) | ✅ real, **read-only** — list/filter by status only, no cancel/grant/refund action (app.js:3660-3700) |
| `refunds` | Возвраты | Финансы | `GET/POST /api/v1/admin/finance/refunds` (app.js:3749,3778) | ✅ real |
| `reports` | Отчёты / Экспорт | Финансы | `GET /api/v1/admin/finance/{reportType}`, `POST /api/v1/admin/finance/export` (app.js:3356,3801) | ✅ real |
| `reviews` | Отзывы | Система | `GET /api/v1/admin/reviews`, `POST .../{id}/{hide\|show}`, `DELETE .../{id}` (app.js:3839,3846,3854) | ✅ real |
| `users` | Пользователи | Система | `GET /api/v1/admin/users` (app.js:3900) | ✅ real, **read-only** — filter/search client-side only, no ban/role-change/delete action (app.js:3890-3930) |
| `online-map` | Online водители | Система | `GET /api/v1/admin/drivers/locations` (app.js:4156, Leaflet map) | ✅ real |
| `audit-log` | Аудит | Система | `GET /api/v1/admin/audit-log` (app.js:4002) | ✅ real |
| `settings` | Настройки | Система | `GET/PUT /api/v1/admin/settings` (app.js:4267,4331) | ✅ real |

Also: dashboard KPI widget separately calls `GET /api/v1/admin/drivers-online`
(app.js:1960,2187) — a **second**, redundant online-drivers source alongside
`online-map`'s `/admin/drivers/locations`.

**No stubs/mocks/placeholders found** in `admin-web/static/app.js` — every page's data
call resolves to a real `h.repo.*` call in `backend/internal/transport/http/admin_handler.go`
which issues real SQL in `backend/internal/infrastructure/postgres/admin_repository.go`
(and `order_repository.go`, `driver_verification_repository.go`, `payment_repository.go`
for their respective domains). There is no `// TODO`, `mock`, or hardcoded fixture data
in either the admin-web JS or the backend admin handler.

**NOT VERIFIED**: whether the SQL in each repo method actually executes cleanly against
today's schema (migrations were read statically — see Section 2/4 — but no DB was run).

---

## SECTION 2 — Critical-for-launch admin functions (traced end-to-end)

### DRIVER MODERATION — ✅ works (code-traced)

Full chain, single Postgres table `driver_verifications`, same `*sql.DB` instance for
both write and read paths (wired once in `backend/internal/app/container.go:146`):

1. Admin UI: `admin-web/static/app.js:2613` loads
   `GET /api/v1/admin/driver-verifications` (list pending); action buttons at
   `app.js:2682-2684` and `2708-2723` fire
   `POST /api/v1/admin/moderation/driver-verifications/{id}/{approve|reject|request-changes|block}`.
2. Backend route: `backend/internal/transport/http/router.go:104-107`, admin-only
   (`RequireRoles(auth.RoleAdmin)`, router.go:99).
3. Handler: all four actions funnel into one function,
   `AdminHandler.decideDriverVerification` (`admin_handler.go:1298-1379`), which requires
   a ≥8-char reason for reject/request-changes/block (admin_handler.go:1312-1316), and for
   `approved` **requires the admin to re-enter vehicle_plate/model/type** — the admin's
   entry overwrites whatever the driver submitted (admin_handler.go:1325-1341), a
   deliberate trust boundary.
4. DB write: `AdminRepository.DecideDriverVerification`
   (`backend/internal/infrastructure/postgres/admin_repository.go:324-364`) —
   `UPDATE driver_verifications SET status = $2, ... WHERE id = $1`.
5. Driver-app read: `GET /drivers/{id}/verification-status` →
   `DriverHandler.GetVerificationStatus` (`driver_handler.go:376-407`) →
   `DriverVerificationRepository.GetVerificationStatus`
   (`driver_verification_repository.go:19-40`) —
   `SELECT id, status, ... FROM driver_verifications WHERE user_id = $1 ORDER BY submitted_at DESC LIMIT 1`.

Both the write (step 4) and the read (step 5) are plain queries against the same
`driver_verifications` table through the same backend process's DB handle — **there is
no caching layer and no denormalized copy**, so an admin decision is immediately visible
to the driver app's next poll, **provided admin-web and the driver app are pointed at the
same backend/DB** (see Section 3 for when they are not).

SMS notification on approve/reject is a **stub only** — `admin_handler.go:1367-1372`
just `log.Printf`s `[sms-stub] ...`; the driver is not actually notified, they must poll.

**NOT VERIFIED**: live DB round-trip (no DB running in this audit).

### ORDERS — ✅ works, live data

`GET /api/v1/admin/orders` and `/admin/orders/{id}` →
`AdminHandler.ListAdminOrders` / `GetAdminOrderDetails` (`admin_handler.go:1382+`) →
`OrderRepository.ListAdminOrders` (`order_repository.go:655+`) — real parametrized SQL
against the `orders` table with filters for status/payment_method/financial_status/
driver_id/client_id/date range. Returns money in kopecks with computed
`commission_amount` joined from `wallet_transactions` (order_repository.go:708-730).
No mock data.

### PRICING / TARIFFS — ❌ missing (admin cannot change per-km rates)

- Backend `PricingHandler` (`backend/internal/transport/http/pricing_handler.go`) exposes
  only **three GET-only** routes: `POST /pricing/calculate`, `GET /pricing/tariffs`,
  `GET /pricing/tariffs/{type}` (router.go:87-89) — no PUT/POST/PATCH for tariffs anywhere
  in `router.go`.
- The repository layer *does* have write methods —
  `PricingRepository.Create/Update/Delete` (`backend/internal/infrastructure/postgres/pricing_repository.go:130-183`)
  — but grepping the whole backend confirms **no handler or usecase ever calls them**.
  They are dead code from an API-consumer standpoint.
- The `pricing_tariffs` table (`backend/migrations/20260601_init_schema.sql:380-383`) is
  populated **once**, by a seed migration
  (`backend/migrations/20260602_seed_data.sql:29-32`: `tariff-winch`, `tariff-platform`,
  `tariff-manipulator` with base_price/price_per_km/minimum_price literals).
- `admin-web`'s `ROUTES` list (app.js:29-46) has **no "Тарифы"/pricing section at all** —
  it isn't merely unwired, the admin-web SPA doesn't have a page for it.

**Conclusion**: to "change per-km rate → app price updates" today requires either a raw
SQL `UPDATE pricing_tariffs` against the DB directly, or a new migration + deploy. There
is no admin-facing way to do this. To make it real: (a) add
`PUT /api/v1/admin/pricing/tariffs/{type}` in the backend calling the already-existing
`PricingRepository.Update`, admin-role-gated like every other `/admin/*` route, and (b) a
new admin-web page/section calling it. This is a small, well-scoped gap — the repo-layer
plumbing already exists.

### COMMISSION — ✅ works (contrast with pricing above)

Unlike per-type tariffs, the platform commission percentage **is** admin-editable:
`commission_percent` is read live via `settings.GetInt(list, "commission_percent",
fallbackCommissionPercent=15)` in `backend/internal/usecase/payment/finance.go:350-360`,
where `list` comes from the generic key-value `platform_settings` table
(`backend/migrations/20260601_init_schema.sql:450-455`). Admin UI: Settings page
(app.js:4267 `GET /admin/settings`, app.js:4331 `PUT /admin/settings {key,value}`) →
`SettingsHandler.Update` (`settings_handler.go:29-46`) → `settings.Repository.Upsert`.
No seed row exists for `commission_percent` (not found in `20260602_seed_data.sql`), so
until an admin sets it once, the system runs on the hardcoded 15% fallback — that's
expected/correct behavior, not a bug.

### PLATFORM SETTINGS (generic) — ✅ works
Generic key→JSONB store, list+upsert, both wired (see above). Whatever else lives under
this (e.g., surcharge percentages, thresholds) is admin-editable through the same
Settings page — **NOT VERIFIED** which specific keys the running app reads besides
`commission_percent`, since that requires grepping every `settings.GetInt`/`GetString`
call site, which was out of scope here beyond commission.

### SERVICE AREAS / ZONES — ✅ works
Full CRUD: `city_handler.go` — `Search`/`Autocomplete` proxy to a Nominatim (OSM)
geocoder (`city_handler.go:66-86,110-130`), `Create` geocodes + inserts with slug
dedup (`city_handler.go:151-171`), `List`/`Patch`/`Delete` hit
`ServiceAreaRepository` directly. Admin UI at app.js:3214-3311 (the `service-areas`
page) covers add/list/toggle-active/delete; a separate "Проверка покрытия" (coverage
check) widget on the same page calls the public `GET /service-areas/check` (app.js:2958).

### DRIVER SUBSCRIPTIONS — ⚠️ partial (view-only)
`GET /api/v1/admin/finance-v2/subscriptions` is wired and real
(`admin_handler.go:1100-1113` → real repo query), but the admin-web page
(app.js:3660-3700) only lists/filters by status — **no button to cancel, extend, or
manually grant a subscription**. If a driver's subscription needs manual admin
intervention (refund a wrongly-charged renewal, comp a subscription), there's currently
no UI or endpoint for it.

### USERS — ⚠️ partial (view-only)
`GET /api/v1/admin/users` is real (`admin_handler.go:403-418`), but the page
(app.js:3890-3930) is list/filter-by-role/search only — **no ban, role-change, or
delete-user action**, either in the UI or as a backend endpoint (no `PATCH/DELETE
/admin/users/{id}` exists in `router.go`).

### REVIEWS — ✅ works
`GET /admin/reviews`, `POST .../{id}/hide`, `POST .../{id}/show`, `DELETE .../{id}` all
wired (app.js:3839-3854 ↔ `admin_handler.go:435+`, plus `HideReview`/`ShowReview`/
`DeleteReview` in router.go:110-112). Full moderation capability present.

---

## SECTION 3 — App ↔ Admin connection integrity

### Auth
- Admin auth is **entirely separate** from app (client/driver) auth. It's a single
  hardcoded operator account, not per-admin-user accounts:
  `AuthHandler.AdminLogin` (`backend/internal/transport/http/auth_handler.go:361-399`)
  compares the submitted `user_id`/`password` against **one** pair of env vars,
  `ADMIN_USER_ID` / `ADMIN_PASSWORD` (`config.go:101-102`), using
  `subtle.ConstantTimeCompare` (auth_handler.go:376-377) — good practice against timing
  attacks, but there is no admin user table, so every admin action is attributed to the
  same `moderatorID` / `reviewed_by` value (`h.adminUserID`) — **the audit log
  (`/admin/audit-log`) cannot distinguish which human performed which action** if more
  than one person has the shared credential.
- No hardcoded default password: `ADMIN_PASSWORD` defaults to `""` (config.go:102), and
  in production `validateProductionConfig` (`config.go:168-201`) hard-fails boot
  (`log.Fatalf`) unless `ADMIN_PASSWORD` is ≥12 chars (config.go:189-190) and
  `ADMIN_USER_ID` is non-empty (config.go:187-188). `ADMIN_USER_ID` does default to the
  literal `"admin"` if unset (config.go:101) — acceptable since it's a username, not a
  secret, but worth knowing it's guessable.
- Rate-limited: `POST /auth/admin/login` is capped at 5 req/IP (`router.go:61`,
  `RateLimitByIP(limiter, 5)`), same tier as the regular login endpoint.
- **Not in git**: `ADMIN_USER_ID`/`ADMIN_PASSWORD` are not set in `render.yaml`
  (confirmed absent from the `envVars` list at repo root `render.yaml:1-40`), so they
  must be configured manually in the Render dashboard — no hardcoded prod credential in
  the repo. **NOT VERIFIED** whether they are actually set in the live Render service
  (can't check dashboard from this audit).

### The two-database split

This is real and structural, not hypothetical:

- **Production**: `render.yaml:9-15` wires the backend's `POSTGRES_DSN` to
  `fromDatabase: evik-postgres` — Render's managed Postgres instance.
- **Local dev**: `docker-compose.yml:3-13` spins up a *separate* `postgres:16` container
  (`evik-postgres`, local Docker volume `postgres_data`) on `localhost:5432`, and the
  backend's config default is exactly that:
  `config.go:93` — `POSTGRES_DSN` defaults to
  `postgres://evik:evik@localhost:5432/evik?sslmode=disable` if no env var is set.
- **Admin-web's target backend is chosen by which `.bat` script launches it**:
  `admin-web/start.bat` and `admin-web/start-production.bat` both hardcode
  `ADMIN_API_BASE_URL=https://tow-truck.onrender.com` (prod); only
  `admin-web/start-local.bat` sets `ADMIN_API_BASE_URL=http://localhost:8080`.
- **The Flutter app's target backend defaults to prod too**:
  `frontend/lib/core/network/api_client.dart:29-30` — `EVIK_API_BASE_URL` default value
  is `'https://tow-truck.onrender.com'`. It only points local if a developer explicitly
  runs `flutter run --dart-define=EVIK_API_BASE_URL=http://localhost:8080`.

**So by default (no overrides), admin-web and the app both point at prod — they are
unified.** The split the task description warns about only happens when a developer:
(a) runs the backend locally (`go run cmd/app/main.go`, defaults to the local Docker
Postgres), and (b) runs the Flutter app with a local `--dart-define` override to hit that
local backend, while (c) admin-web is still launched via `start.bat`/`start-production.bat`
(prod) instead of `start-local.bat`. In that specific dev configuration, every admin
action (driver approval, price/commission changes, etc.) writes to the prod DB and is
**invisible** to the locally-running app, and vice versa. This is a common trap during
local development/testing of admin-dependent features (e.g. testing "does approving a
driver unlock the driver app" locally) — it will silently look broken.

**Smallest fix to test admin↔app on one DB locally**: run backend locally
(`cd backend && go run cmd/app/main.go`, uses docker-compose Postgres by default), launch
admin-web with `admin-web/start-local.bat` (points at `localhost:8080`), and run the
Flutter app with `flutter run --dart-define=EVIK_API_BASE_URL=http://localhost:8080`. All
three then share one Postgres instance. No code changes needed — this is purely a launch-
configuration issue, not an architecture defect.

**For a real launch**: there's no "unification" work needed on the production side —
prod already has exactly one DB (`evik-postgres` on Render) that both the deployed admin
proxy (when pointed at it) and the deployed app (default dart-define) hit. The risk is
purely a *local development* footgun, not a production architecture problem.

### Admin endpoints vs admin-web screens — orphans

Cross-referencing every `admin.*` route registered in `router.go:99-166` against every
`api.get/post/put/patch/del(...)` call in `admin-web/static/app.js`:

**Backend endpoints with no admin-web caller found** (orphaned on the backend side):
- `POST /admin/moderation/batch/approve` (router.go:107) — no batch-approve UI; the
  Documents/Moderation page only has per-verification action buttons
  (app.js:2682-2723), no multi-select.
- `POST /admin/moderation/batch/reject` (router.go:108) — same, unused.
- `POST /api/v1/admin/cities/search` (router.go:157) — the service-areas page only calls
  `/admin/cities/autocomplete` (app.js:3290) for the typeahead; `Search` (which returns
  bbox/center for a single exact name, `city_handler.go:66-86`) has no caller.

No orphans found in the other direction — every `api.*` call in app.js resolves to a
route that exists in `router.go` (verified by grep cross-reference of all ~42 admin
paths called against all ~42 admin routes registered).

---

## SECTION 4 — Gaps / priorities for launch

Ranked, most launch-blocking first:

1. **Driver moderation — confirmed working end-to-end** (see Section 2). Not a blocker,
   *if* admin-web and the app are pointed at the same backend/DB in whatever environment
   is used for launch testing (see Section 3 — this is a config/procedure risk, not a
   code defect). **Action**: before launch sign-off, do one live manual test — approve a
   real driver through the deployed admin-web against the deployed prod backend, and
   confirm the driver app (also pointed at prod) reflects `approved` — this audit could
   not execute that (no DB running).

2. **Pricing/tariff admin UI is completely missing** —
   `backend/internal/transport/http/pricing_handler.go` (no write routes),
   `admin-web/static/app.js:29-46` (no pricing page in `ROUTES`). If launch requires the
   ability to adjust per-km/base/minimum price without a deploy, this blocks it. Backend
   repo-layer write methods already exist
   (`backend/internal/infrastructure/postgres/pricing_repository.go:130-183`) so the fix
   is scoped to: one new admin-role-gated handler + route, one new admin-web page.

3. **Single shared admin credential, no per-admin accountability** —
   `backend/internal/transport/http/auth_handler.go:361-399`,
   `config.go:101-102`. If more than one person will operate the admin panel at launch,
   every audit-log entry (`/admin/audit-log`) will show the same actor for every action —
   undermines the audit log's value for incident investigation. Not a hard blocker, but
   worth a decision before multiple staff get the shared password.

4. **SMS notification on driver moderation decisions is a stub** —
   `admin_handler.go:1367-1372` only logs, never sends. Drivers must manually re-poll the
   verification-status endpoint to discover they were approved/rejected — degrades the
   "driver app now requires real approval" flow's UX even though the data path itself
   works.

5. **Users page has no admin actions** (ban/role change/delete) —
   `app.js:3890-3930`, no corresponding backend route in `router.go`. Likely needed
   before launch for abuse handling (e.g., banning a client or driver), but not required
   for the moderation-gate to function.

6. **Subscriptions page is view-only** — `app.js:3660-3700`, no cancel/refund/grant
   action or endpoint. Lower priority — only matters once paid driver subscriptions are
   live and something goes wrong with one.

7. **Two redundant "online drivers" data sources** — dashboard widget
   (`GET /admin/drivers-online`, app.js:1960) vs. the dedicated online-map page
   (`GET /admin/drivers/locations`, app.js:4156). Not a functional bug, but worth
   consolidating; risk of the two disagreeing (different staleness thresholds) is
   unverified.

8. **Cities `/admin/cities/search` and moderation `/batch/approve`, `/batch/reject`
   backend routes are unused by any UI** — dead endpoints, not a blocker, just cleanup
   candidates or evidence of an unfinished batch-moderation feature.

---

## What was NOT verified (explicitly)

- No live Postgres/Redis/backend process was started during this audit — every "works"
  verdict is a **static trace** of handler → repo → SQL, cross-checked against schema in
  `backend/migrations/*.sql`. Actual query execution against a live DB (column names
  matching, no runtime SQL errors) was not exercised.
- Whether `ADMIN_USER_ID`/`ADMIN_PASSWORD` are actually set in the live Render dashboard
  for the deployed `evik-backend` service.
- Which specific `platform_settings` keys (besides `commission_percent`) the running
  backend reads — only `commission_percent`'s call site was traced in depth.
- Whether the embedded `admin-web/static/*` assets currently deployed match what's in the
  working tree (admin-web is built via `admin-web/build.bat` — go:embed bakes the static
  files in at build time; if the deployed binary is stale, screens described here may not
  match production).
