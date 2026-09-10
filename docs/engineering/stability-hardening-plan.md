# EVIK / Авро — stability hardening plan

Дата начала: 2026-09-11  
HEAD: `5480c9c` (`main`)  
Ограничения: production не трогаем; нагрузочные проверки выполняются только локально или на staging; секреты и персональные данные не записываются в отчёты.

## Стартовая инвентаризация

- Backend: Go HTTP API, PostgreSQL repositories/migrations, Redis, background schedulers/reapers, WebSocket order hub, FCM.
- Clients: Flutter клиент и водитель; iOS/Android lifecycle, reconnect/background state требуют runtime-проверки.
- Admin: отдельный Go web service (`admin-web`).
- Deploy: `render.yaml` (production) и `render.staging.yaml` (изолированный staging blueprint).
- GitNexus: индекс обновлён на текущем HEAD; 11,743 nodes, 34,440 edges, 364 flows. В индексе есть lower-bound предупреждения по пропущенным/неразрешённым flow-кандидатам — отсутствие flow не трактуется как отсутствие пути.
- `CONTEXT.md` и ADR в репозитории не найдены.

## Рабочий журнал

| ID | Категория | Найденная проблема | Доказательство | Серьёзность | Влияние | Воспроизведение | План исправления | Статус | Commit | Результаты проверки |
|---|---|---|---|---|---|---|---|---|---|---|
| STAB-001 | Orders / accept | ~~В recovery-пути swapped args~~ Исправлено ранее; текущий вызов передаёт `driverID, orderID`. | `backend/internal/usecase/order/accept_order.go:157`; regression `accept_order_test.go:187`. Git history: `c496983`. | High (historical) | Ранее мог ломать recovery busy-driver. | `go test ./internal/usecase/order -run 'TestAcceptOrderRecovery' -count=1 -v` | Оставить regression test; не менять без повторного impact analysis. | DONE | `c496983` | PASS (0.00s) на текущем HEAD. |
| STAB-002 | Payments / atomicity | `/confirm-payment` выполняет финансовое завершение и перевод заказа в `completed` двумя отдельными DB-операциями. | `backend/internal/usecase/payment/finance.go` (static source audit; webhook path отдельно transactional). | High | Crash между операциями оставляет деньги и статус в разных состояниях. | Integration test с контролируемой ошибкой между writes. | Объединить writes в транзакционный use-case/repository seam и проверить idempotency. | TODO | — | Не проверено на живой БД. |
| STAB-003 | Driver lifecycle | Completion через cash/card не вызывает `ReleaseOrder`; водитель может остаться busy. | `finance.go`, `update_status.go`, `stuck_order_reaper.go` (static source audit). | Medium | Последующие офферы не приходят до ручного offline/online. | Complete-order flow, затем запросить driver availability/current order. | Единый terminal transition с release и regression test для cash/card/webhook. | TODO | — | Не проверено runtime. |
| STAB-004 | Auth / production | OTP code генерируется и хэшируется, но production delivery gateway отсутствует. | `auth_handler.go`, `config.go`; подтверждено в `docs/STATUS_AUDIT.md`. | Critical | OTP login в production недоставляем; публичный запуск блокирован. | Production-like config без fixed/debug OTP: код не имеет delivery sink. | USER_ACTION_REQUIRED: выбрать SMS-провайдера, подключить secret/config и staging delivery test. | BLOCKED | — | Static confirmed; external delivery not available. |
| STAB-005 | Security / auth abuse | Требуется повторно подтвердить rate limiting OTP и production guards после текущего HEAD. | Existing audit says limits/guards exist; current tests pending. | High | SMS abuse или обход OTP при регрессии. | Unit/integration tests for per-phone request/verify limits and weak-code rejection. | Verify code + tests; fix only if red. | TODO | — | Не проверено на текущем HEAD. |
| STAB-006 | Driver verification | Admin reject/block may leave active driver order/offer state unresolved. | Listed as unresolved in `docs/PRODUCTION_READINESS_PLAN.md`; code/runtime proof pending. | High | Blocked driver can remain on line or receive offers. | Integration scenario: active driver -> admin block -> dispatch/WS checks. | Decide owner policy (reassign/cancel), then implement transactionally. | BLOCKED | — | Требует product decision. |
| STAB-007 | Frontend / payments | Card UI persists payment method but does not run real charge/3DS flow. | `frontend/lib/features/order/screens/payment_confirmation_screen.dart`; existing audit. | High | Card payment E2E incomplete. | Flutter/widget + staging provider flow once provider exists. | USER_ACTION_REQUIRED: select/acquire payment provider and credentials; implement E2E. | BLOCKED | — | Static confirmed. |
| STAB-008 | Scale / events | Multi-instance safety for local dispatch/WS state and event fanout is not yet proven. | Render/Redis config and backend flow audit pending. | High | Duplicate/missed offers or events after horizontal scaling. | Two-instance staging test with Redis and concurrent orders. | Document/implement distributed dispatch lock, shared pub/sub, replay/idempotency, readiness/shutdown. | TODO | — | Not run. |
| STAB-009 | Test infrastructure | PostgreSQL integration test не имел `integration` build tag и поэтому видел helper-файл, исключённый из обычной сборки. | `go test ./...` до: undefined `setupTestDB`/`truncateAll`; `testutil_test.go` и остальные integration tests используют `//go:build integration`. | High (resolved) | Полный backend test/vet gate был красный. | `cd backend && go test ./...` | Добавлен `//go:build integration` в `service_area_create_integration_test.go`. | DONE | `5f57bfa` | После изменения `go test ./...`, `go vet ./...`, `go build ./...` PASS; integration runtime tests отдельно не запускались. |

## USER_ACTION_REQUIRED

- Choose and provision an SMS/OTP provider for production; provide it through Render secret configuration, not chat.
- Choose/provision card acquiring/3DS provider; do not use real payments in tests.
- Decide policy for blocking a driver with an active order: reassign or cancel/refund policy.
- Create the isolated Render staging blueprint and provide access/URL if live WS/push/E2E validation is required.
- Provide a test iPhone/Android device or redacted runtime logs for background/foreground push verification.

## Iteration protocol

For each code finding: reproduce with a focused test, run it red before the fix, run GitNexus impact before editing, apply the smallest fix, run the focused and regression suites, run `gitnexus detect-changes --scope all` before commit, then update this table with evidence. No production secrets or production load tests are used.
