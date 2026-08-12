# Отчёт: тестирование денежной логики (backend Авро/EVIK)

## Задача

Усилить денежную логику Go-бэкенда регулярными, граничными и adversarial-тестами по 5 группам: **pricing**, **finalize_order**, **confirm_payment**, **payout/wallet**, **webhook**. Требования: не менять прод-код; найденные баги фиксировать тестами (skip + TODO) и описывать в отчёте.

Базовое состояние (до добавлений): `go build ./...`, `go vet ./...`, `go test ./...` — зелёные. Прод-код за время работы **не изменялся** (в рабочем дереве есть pre-existing изменения, не относящиеся к задаче).

## Что реализовано (по группам)

### 1. Pricing — `internal/domain/pricing` (unit, adversarial)
- Отрицательные и нулевые дистанции не дают отрицательную цену: `TotalPrice >= MinimumPrice` при 0, −0.0001, −1, −100, −1e9 км.
- Гигантские дистанции (1e18…1e30 км) не приводят к overflow в отрицательную цену (инвариант: цена ≥ минимума и неотрицательна).
- Переполнение сложения `BasePrice + distanceKm*PricePerKm` при `BasePrice = MaxInt64` не ломает инвариант (цена упирается в минимум).
- Дробные километры: проверка rounding (1.5 км → должно быть half-up = 2×тариф) — **SKIPPED, баг PRICING-ROUND**.
- Некорректный тип ТС: ссылка на существующее покрытие `TestServiceCalculatePriceInvalidInput`.

### 2. Finalize order — `internal/usecase/order` (unit, границы допуска)
- Отрицательные цены (−1, −100 000 копеек) — отклоняются.
- Границы допуска ±100 копеек: 500200 (101 коп. сверх) — reject; 499800 (101 коп. ниже) — reject; 500101/499899 (ровно за границей) — reject; 499900 (ровно на границе) — accept, итоговая цена из сервера (500000), статус `awaiting_payment`.
- Отклонение всех статусов, кроме `in_progress` (created/searching/accepted/arrived/awaiting_payment/completed/cancelled) → `ErrInvalidTransition`.
- Чужой водитель ("driver does not own this order") — заказ не изменён.

### 3. Create order — `internal/usecase/order` (unit, adversarial)
- Неположительная цена (0, −1) принимается UC — заказ персистится. **SKIPPED, баг CREATE-NONPOSPRICE**.
- Характеристика аварийного сценария: при сбое расчёта цены в БД остаётся заказ `created` с `PriceTotal = 0` (заказ создаётся ДО расчёта цены).

### 4. Confirm payment — `internal/usecase/payment` (unit, adversarial)
- Двойной confirm наличными: второй вызов → `ErrInvalidTransition`, финансовых операций ровно 1, транзакций ровно 1.
- Отклонение чужих статусов (created/accepted/in_progress/completed/cancelled).
- Чужой пользователь → `ErrOrderNotOwned`.
- Атомарность: settlement и перевод статуса в `completed` выполняются в одной РБ-транзакции.

### 5. Payout / wallet — `internal/infrastructure/postgres` (integration)
- **Конкурентно, N>2**: 6 goroutines по 30 000 на балансе 50 000 → ровно 1 успешный payout, остальные `ErrInsufficientFunds`, баланс не уходит в минус.
- `ApprovePayout` по payout со статусом `failed` → `ErrPayoutNotApprovable`, баланс не тронут, статус остаётся `failed`.
- DB-инварианты: UPDATE −1 по `available/pending/debt` падает с именами constraint-ов `driver_wallets_available_nonneg`, `driver_wallets_pending_nonneg`, `driver_wallets_debt_nonneg`.
- Идемпотентный ключ payout: повторный create с тем же ключом возвращает ту же запись, в таблице 1 строка; новый ключ на тот же баланс работает.
- Счётчики не смешиваются: payout 120 000 отклоняется, несмотря на available+pending = 150 000 (эффективный баланс = available − outstanding); после успешного payout и approve: available=10 000, pending=50 000, debt=10 000.
- Splitting: инвариант `driver_amount + commission_amount == price_total` для комиссий 15%, 15% (итог 1001 коп.), 20%, 33%, 0%; `financial_status=completed`; `DebtBalance == commission`.

### 6. Webhook — `internal/usecase/payment` (unit) + `internal/infrastructure/postgres` (integration)
- **N-конкурентные дубликаты**: 6 одновременных одинаковых вебхуков → 1 строка `payment_webhooks`, 1 транзакция `order_income`, `pending_balance = 425000`, вызов провайдера ровно 1 раз.
- Верификатор источника: границы всех CIDR YooKassa (v4/v6), битые RemoteAddr, поддельный не-allowlisted X-Real-IP — reject.
- **X-Real-IP bypass**: remote `203.0.113.1` + заголовок `X-Real-IP: 185.71.76.1` — источник «подтверждён». Тест проходит (характеристика бага).
- ParseEvent: nil/пустой/«не JSON»/обрезанный payload/неверный тип/`object.id` числом — ошибка; отсутствие `object.id` → пустой PaymentID.
- `Verify(nil)` — краш через nil-request (характеристика, паника перехвачена в тесте).

## Изменённые файлы

Только новые тестовые файлы (прод-код не тронут):

| Файл | Группа |
|---|---|
| `backend/internal/domain/pricing/adversarial_test.go` | Pricing |
| `backend/internal/usecase/order/finalize_order_adversarial_test.go` | Finalize |
| `backend/internal/usecase/order/create_order_adversarial_test.go` | Create order |
| `backend/internal/usecase/payment/confirm_payment_adversarial_test.go` | Confirm payment |
| `backend/internal/usecase/payment/webhook_verifier_adversarial_test.go` | Webhook verifier |
| `backend/internal/infrastructure/postgres/webhook_many_test.go` | Webhook (integration) |
| `backend/internal/infrastructure/postgres/wallet_payout_adversarial_test.go` | Payout/wallet (integration) |

## Добавленные тесты

**Pricing (domain/pricing/adversarial_test.go):**
- `TestTariffCalculatePrice_NegativeDistanceNeverResultsInNegativePrice`
- `TestTariffCalculatePrice_HugeDistanceNoOverflowToNegativeMoney`
- `TestTariffCalculatePrice_HugeBasePlusPerKmAdditionOverflow`
- `TestTariffCalculatePrice_FractionalKmHalfUp` — SKIP (PRICING-ROUND)
- `TestCalculatePrice_InvalidTruckType` (отсылка к `TestServiceCalculatePriceInvalidInput`)

Покрытие существующими: `TestTariffCalculatePrice` (вкл. кейс truncation), `TestNewTariffValidation`, `TestServiceCalculatePriceInvalidInput`, `TestHaversineDistanceCalculator`.

**Finalize (usecase/order/finalize_order_adversarial_test.go):**
- `TestFinalizeRejectsNegativePrice`
- `TestFinalizeRejectsPriceOneRubleAboveTolerance`
- `TestFinalizeRejectsPriceOneRubleBelowTolerance`
- `TestFinalizeRejectsPriceJustBeyondTolerance`
- `TestFinalizeAcceptsPriceAtToleranceBoundary`
- `TestFinalizeRejectsNonInProgressStatus`
- `TestFinalizeRejectsForeignDriver`

Существующие: `TestFinalizeUsesServerPrice`, `TestFinalizeIgnoresCallerPriceWithinTolerance`, `TestFinalizeRejectsInflatedPrice`, `TestFinalizeRejectsUnderpricedPrice`, `TestFinalizeRequiresPositivePrice`, `TestFinalizeRejectsOrderWithoutServerPrice`.

**Create order (usecase/order/create_order_adversarial_test.go):**
- `TestCreateOrder_RejectsNonPositivePrice` — SKIP (CREATE-NONPOSPRICE)
- `TestCreateOrder_FailedPriceComputationLeavesZeroPriceOrder`

**Confirm payment (usecase/payment/confirm_payment_adversarial_test.go):**
- `TestConfirmOrderPaymentCash_DoubleConfirmNoDoubleSettlement`
- `TestConfirmOrderPayment_RejectsWrongStatus`
- `TestConfirmOrderPayment_RejectsForeignUser`
- `TestConfirmOrderPaymentCash_SettlementAndCompletedAtomically`

Существующие: `TestConfirmOrderPaymentCash_OneTransaction` и др. в `finance_confirm_payment_test.go`, integration `TestConfirmPaymentCash_FreesDriverAndCompletesOrder`.

**Payout/wallet (infrastructure/postgres/wallet_payout_adversarial_test.go, integration):**
- `TestPayout_ConcurrentCreateExceedsBalance_ThreePlus`
- `TestApprovePayout_RejectsFailedPayout`
- `TestWalletNonNegativeCheckConstraints`
- `TestPayout_SameIdempotencyKey_NoDuplicate`
- `TestWallet_AvailablePendingDebtNotMixed`
- `TestSplitInvariant_AcrossPercentages`

Существующие: `TestPayout_ConcurrentCreateExceedsBalance`, `TestApprovePayout_RejectsWhenBalanceInsufficient`, `TestApprovePayoutHappyPath`, `TestApprovePayoutIdempotentForAlreadyPaid`, `TestSplitInvariant_Standard/CrossCity/CardOrder`, `TestWallet_ParallelIdempotentKey`, `TestOrderSplitConstraint`, `TestCreateOrder_Idempotent`.

**Webhook (usecase/payment/webhook_verifier_adversarial_test.go + infrastructure/postgres/webhook_many_test.go):**
- `TestWebhook_ManyConcurrentDuplicates` (N=6, integration)
- `TestYooKassaVerifier_RejectsForgedSources`
- `TestYooKassaVerifier_XRealIPBypass`
- `TestYooKassaVerifier_ParseEvent_MalformedPayload`
- `TestYooKassaVerifier_ParseEvent_MissingObjectID`
- `TestVerify_NilRequestPanics`

Существующие: `TestWebhook_ConcurrentDuplicate`, `TestWebhook_MidTxFailure_RollsBack`, `TestWebhook_RetryAfterSuccess`, `TestWebhook_RetryAfterFailure`, `TestWebhook_YooKassaVerifier_ForgedIP`.

## Найденные баги

1. **[PRICING-ROUND] Дробная дистанция округляется truncation вместо half-up.** `Tariff.CalculatePrice` считает `int64(distanceKm * float64(PricePerKm))`: 1.5 км → 1 км (1₽ теряется с каждого дробного километра), 0.5 км → 0 км. На практике потери <1₽/заказ, систематически в пользу клиента. Существующий тест заранее закреплял это поведение. Исправление: half-up rounding в `entity.go`.
2. **[CREATE-NONPOSPRICE] CreateOrderUseCase принимает неположительную цену.** Заказ с `PriceTotal = 0` и −1 создаётся без ошибки (цена, приходящая из прайсинга, не проверяется, create_order.go:146). Тест-скрипт проходит создание. Нужен порог `> 0`.
3. **[CREATE-ZEROPRICE-ROW] Заказ персистится до расчёта цены.** При ошибке прайсинга в БД остаётся заказ `created` с `PriceTotal = 0` (create_order.go:100) — мусорные заказы в проде.
4. **[WEBHOOK-XREALIP-BYPASS] Верификация источника вебхука обходится подделкой X-Real-IP.** `clientIPFromRequest` безусловно доверяет заголовку (TODO B-01). Внешний отправитель без контроль над HTTP-заголовками не может им воспользоваться, но в текущей архитектуре (без доверенного прокси) заголовок подделываем: `203.0.113.1` + `X-Real-IP: 185.71.76.1` проходит как легитимный YooKassa. Может привести к фрод-подтверждению платежей. Требует: брать IP только из `RemoteAddr` и/или разрешать X-Real-IP только при доверенном прокси.
5. **[WEBHOOK-NILPANIC] `Verify(nil)` паникует** (разыменование nil `*http.Request`). Низкий приоритет — все вызовы в проде передают не-nil.
6. **Переполнение упирается в минимум (footgun).** Огромные дистанции/тарифы (переполнение int64) приводят к цене = `MinimumPrice` — занижение стоимости на экстремальных маршрутах. Инвариант неотрицательности держится, но нужен валидационный потолок (например, max distance). Поведение платформозависимо: на darwin/arm64 `int64(out-of-range float)` насыщается к MaxInt64, на других платформах результат может отличаться.

## Результаты тестов

```
$ go build ./...                                    # OK
$ go vet ./...                                      # OK
$ go test ./...                                     # все пакеты ok
  ok  evik/backend/internal/domain/pricing
  ok  evik/backend/internal/infrastructure/postgres
  ok  evik/backend/internal/usecase/order
  ok  evik/backend/internal/usecase/payment
  ok  evik/backend/internal/transport/http
  ok  evik/backend/internal/app, matching, servicearea, settings, driver, http

$ go test -race ./internal/domain/pricing/... ./internal/usecase/order/... ./internal/usecase/payment/...
  ok  evik/backend/internal/domain/pricing
  ok  evik/backend/internal/usecase/order
  ok  evik/backend/internal/usecase/payment

$ go test -tags integration ./internal/infrastructure/postgres/ -run 'TestPayout_|TestApprovePayout_|TestWalletNonNegative|TestWallet_Available|TestSplitInvariant_Across|TestWebhook_ManyConcurrent' -v
  --- PASS: TestPayout_ConcurrentCreateExceedsBalance
  --- PASS: TestApprovePayout_RejectsWhenBalanceInsufficient
  --- PASS: TestPayout_ConcurrentCreateExceedsBalance_ThreePlus
  --- PASS: TestApprovePayout_RejectsFailedPayout
  --- PASS: TestWalletNonNegativeCheckConstraints (3 subtests)
  --- PASS: TestPayout_SameIdempotencyKey_NoDuplicate
  --- PASS: TestWallet_AvailablePendingDebtNotMixed
  --- PASS: TestSplitInvariant_AcrossPercentages (5 subtests)
  --- PASS: TestWebhook_ManyConcurrentDuplicates
  ok  evik/backend/internal/infrastructure/postgres  14.572s

$ go test -tags integration -count=1 ./internal/infrastructure/postgres/
  ok  evik/backend/internal/infrastructure/postgres  68.239s
```

Всё зелёное. Skipped-тесты (`PRICING-ROUND`, `CREATE-NONPOSPRICE`) фиксируют баги и ожидаемо `SKIP`.

## Риски

- Денежные расчёты построены на `float64` → int64; результат переполнения платформозависим (проверено на darwin/arm64). При смене платформы (Linux amd64) поведение крайних кейсов может измениться — рекомендуется обновить тесты под целевую платформу.
- Интеграционные тесты требуют Docker (testcontainers, ~1.2–4s на тест; полный пакет ~68s) и не исполняются по умолчанию (`go test ./...` их пропускает — только `-tags integration`).
- Исправление багов PRICING-ROUND и CREATE-NONPOSPRICE (снятие skip) — отдельная задача; после исправления прод-кода тесты должны быть переведены из skip в активные.
- N-конкурентные тесты (payout, webhook) проверяют самые жёсткие гарантии; при смене стратегии блокировок/изоляции БД требуют проверки на стабильность (flakiness).

## Нерешённые вопросы

- Кто и когда чинит найденные баги (1–4)? Без исправления `WEBHOOK-XREALIP-BYPASS` верификация вебхуков остаётся формальной.
- Нужен ли числовой потолок расстояния/тарифа (баг 6) — продуктовое решение.
- `finalize_order`: ошибка чужого водителя — не-sentinel (проверка по строке); вопрос перехода на typed error (влияет на HTTP-маппинг).
- Раскомментирование skip-тестов следует делать вместе с исправлением — иначе прогоны будут красными.