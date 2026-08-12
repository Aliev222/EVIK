# APP_XRAY — Рентген приложения Авро

Дата анализа: 2026-08-10.
Git HEAD: `b8a72b1365a258da01322c2cd57caa7ec642cd18`.
Граф: `graphify-out/graph.json` пересобран на текущем HEAD — 7219 узлов, 12522 ребра, 345 community.
Метод: свежий граф (graphify update) + фактический код, тесты и схема БД. Код не менялся.

---

## а) Архитектурная карта

### Слои (backend, Go)

| Слой | Путь | Роль |
|---|---|---|
| **domain** | `backend/internal/domain/{order,driver,user,payment,pricing,matching,servicearea,settings,location,routing,admin}` | Чистая бизнес-логика: сущности, стейт-машина заказа, офферы, events, ошибки |
| **usecase** | `backend/internal/usecase/{order,payment,driver}` | Прикладные сценарии: создание/приём/финализация заказа, денежный флоу, gate водителя |
| **infrastructure** | `backend/internal/infrastructure/{postgres,redis,http,websocket,fcm,storage,geocoding}` | Репозитории БД, YooKassa клиент, пул WS, Redis-локации, FCM, документы |
| **transport** | `backend/internal/transport/http` + `transport/ws` | HTTP-хендлеры, роутер, JWT-мидлварь, WS-хаб |
| **app** | `backend/internal/app/container.go` | DI-сборка; фоновые воркеры: `DispatchScheduler`, `driver_presence_reaper`, `stuck_order_reaper`, `expansion_scheduler` |
| **auth** | `backend/internal/auth` | JWT, claims, роли |

### Направление зависимостей + нарушени

```
transport/http ──► usecase ──► domain
       │                 ▲
       │                 │ (интерфейсы)
       ▼                 │
infrastructure ─────────┘
(нужно: domain ◄─use case ◄─transport; infrastructure реализует интерфейсы usecase/domain)

app/container.go ──► всё (DI)
```

**Нарушения направления (infrastructure → transport «снизу вверх»):**
1. `backend/internal/infrastructure/postgres/admin_repository.go` — импортирует `evik/backend/internal/transport/http` (типы `http.DriverReviewsStats`, `http.AdminTaxProfile`, `http.AdminListPayment/...`).
2. `backend/internal/infrastructure/postgres/driver_verification_repository.go` — импортирует `evik/backend/internal/transport/http` (типы `http.DriverVerificationStatus`, `http.DocumentInfo`).

Следствие: транспортные DTO протекают в слой данных; чистые интерфейсы usecase не выдержаны для admin/verification-модулей.

**domain → infrastructure/transport: нарушений НЕТ** (проверено `go list` + grep: domain импортирует только `internal/auth`).

### Frontend (Flutter)

```
lib/main.dart → core/ (network, realtime, theme, services)
             → features/{auth,onboarding,client,driver,order,map,review,admin}
             → shared/ (widgets, tariff_model)
Каждый feature: data/ → domain/ → presentation/{providers,screens,widgets}
```

Состояние — Riverpod (`StateNotifierProvider`/`Provider`/`FutureProvider`). События realtime — `core/realtime/event_dispatcher.dart`, клиент WS `websocket_client_io.dart`.

---

## б) Денежный поток end-to-end

Все суммы — в копейках (BIGINT, миграция `20260603_money_to_kopecks`). Комиссия по умолчанию 15% (`defaultCommissionPercent` в `payment_repository.go`), при активной подписке — 0%.

| Шаг | Backend (файл/функция) | Комментарий |
|---|---|---|
| 1. Расчёт цены | `transport/http/pricing_handler.go` → `domain/pricing/service.go:CalculatePrice` / `CalculateAllPrices` | Тариф из `pricing_tariffs` (base + per_km + minimum), расстояние Haversine `CalculateDistance` |
| 2. Создание заказа | `usecase/order/create_order.go:Execute` → `order_repository.go:Create` | `TransitionTo(Searching)`, `idempotency_key`, `notes`, цена зафиксирована в `price_total` |
| 3. Cross-city surcharge при приёме | `usecase/order/accept_order.go:applySurchargeIfCrossCity` | +50% к `price_total`, `surcharge_amount/percent`, `is_cross_city` |
| 4. Оплата (карта/кэш) | `usecase/payment/finance.go:CreateOrderPayment` | INSERT `payments` (provider YooKassa / cash), `ON CONFLICT (idempotency_key)` |
| 5. Finalize → awaiting_payment | `usecase/order/finalize_order.go:Execute` | Проверка серверной цены против клиентской, переход `in_progress → awaiting_payment` |
| 6. Confirm payment (клиент) | `usecase/payment/finance.go:ConfirmOrderPayment` | Cash: сразу settlement; Card: ждёт webhook |
| 7. Settlement | `postgres/payment_repository.go:completeOrderFinanciallyTx` | `financial_status='completed'`, `financially_completed_at`, сплит: `commission = (base*15+50)/100`, `driver_amount = total - commission`; подписка → commission 0% |
| 8. Wallet driver | `ensureWalletLocked` + `insertWalletTx` (payment_repository.go) | Cash: `debt_balance += commission` (cash_commission_debt) + `order_income`; Card: `pending_balance += driver_amount` (order_income, pending), repayment долга первым |
| 9. Release pending | `usecase/payment/finance.go:ReleasePendingBalances` → `MarkTransactionReleased` | Джоб: `pending → available` (по `available_after`) |
| 10. Payout | `usecase/payment/finance.go:RequestDriverPayout` → `CreatePayout` → `ApprovePayout`/`MarkPayoutPaid` | Баланс `available_balance` минусуется при paid; `wallet_transaction_locks` для идемпотентности |
| 11. Webhook YooKassa | `usecase/payment/webhook.go` + `payment_repository.go:WithWebhookTx` | Идемпотентность через `payment_webhooks`, IP-верификация `yookassa_verifier.go` |

Frontend-зеркало: `client/data/services/pricing_service.dart`, `payment_repository.dart`, провайдеры `payment_wallet_provider.dart`, `driver_wallet_provider.dart`.

**Найденный ранее drift (не чинил):** `admin_repository.go:1145` обращается к несуществующей колонке `orders.completed_at` (в схеме `financially_completed_at`) — падает `/admin/drivers/{id}/orders`.

---

## в) Стейт-машина заказа

Источник: `domain/order/state_machine.go` + `entity.go:TransitionTo`.

```
created ──► searching ──► accepted ──► arrived ──► in_progress ──► awaiting_payment ──► completed
   │            │             │          │               │                │
   └──► cancelled ◄───────────┴──────────┴───────────────┴────────────────┘
                searching ──► no_driver_found
```

| Начало | Допустимые переходы |
|---|---|
| created | searching, cancelled |
| searching | accepted, cancelled, no_driver_found |
| accepted | arrived, cancelled |
| arrived | in_progress, cancelled |
| in_progress | awaiting_payment, cancelled |
| awaiting_payment | completed, cancelled |
| completed / cancelled / no_driver_found | терминальные (без исходящих) |

Триггеры переходов (кто вызывает):

| Переход | Триггер | Файл/функция |
|---|---|---|
| → searching | Создание заказа | `usecase/order/create_order.go:Execute` |
| searching → accepted | Приём оффера водителем | `usecase/order/accept_order.go:Execute` (через `AcceptOrderTx`) |
| → arrived / in_progress | Драйвер обновляет статус | `usecase/order/update_status.go:Execute` |
| in_progress → awaiting_payment | Финализация | `usecase/order/finalize_order.go:Execute` |
| → completed | Webhook/settlement | `payment_repository.go:completeOrderFinanciallyTx` (UPDATE, не через TransitionTo) |
| → cancelled | Клиент/долг/рейпер | `usecase/order/cancel_order.go`, `stuck_order_reaper` |
| searching → no_driver_found | Диспетчер, нет кандидатов | `app/dispatch_scheduler.go:markNoDriverFound` |

Замечание: `StateNoDriverFound` объявлен в `entity.go:5`, но не включён в `State`-константы `state_machine.go`; в `allowedTransitions` он присутствует. `EventTypeFromStatus` не мапит `no_driver_found` (default → `order_created`).

---

## г) Инвентарь HTTP-эндпоинтов

Источник: `transport/http/router.go`. Все пути под префиксом `/api/v1`. Роли: `C`=client, `D`=driver, `A`=admin, `*`=любая авторизованная, «-»=публичный.

| Метод | Путь | Хендлер | Роль | Тест |
|---|---|---|---|---|
| POST | /auth/register | AuthHandler.Register | - | ✅ auth_handler_test |
| POST | /auth/login | AuthHandler.Login | - | ❌ |
| POST | /auth/otp/request | AuthHandler.RequestOTP | - | ✅ auth_handler_test (rate limit bypass в тесте опущен) |
| POST | /auth/otp/verify | AuthHandler.VerifyOTP | - | ✅ auth_handler_test |
| POST | /auth/admin/login | AuthHandler.AdminLogin | - | ❌ |
| POST | /auth/refresh | AuthHandler.Refresh | - | ✅ auth_handler_test |
| POST | /webhooks/yookassa | PaymentHandler.HandleYooKassaWebhook | - | ⚠️ usecase `finance_webhook_test` покрывает логику, не сам HTTP-хендлер |
| GET | /service-areas/check | ServiceAreaHandler.Check | - | ❌ (есть entity-тесты servicearea) |
| GET | /auth/me | AuthHandler.Me | * | ❌ |
| POST | /devices/fcm-token | AuthHandler.UpsertDeviceToken | * | ✅ auth_handler_test |
| POST | /devices/fcm-token/revoke | AuthHandler.RevokeDeviceToken | * | ❌ |
| POST | /orders | OrderHandler.CreateOrder | C,A | ❌ (нет HTTP-теста; usecase create_order не имеет своего теста) |
| GET | /orders | OrderHandler.ListOrders | * | ❌ |
| GET | /orders/active | OrderHandler.GetActiveOrder | * | ❌ |
| GET | /orders/{orderID} | OrderHandler.GetOrder | * | ❌ |
| GET | /orders/{orderID}/review | AdminHandler.GetOrderReview | * | ❌ |
| POST | /orders/{orderID}/payments | PaymentHandler.CreateOrderPayment | C,A | ⚠️ usecase `finance_create_payment_test` |
| GET | /orders/{orderID}/payment-status | PaymentHandler.GetOrderPaymentStatus | C,A | ❌ |
| GET | /orders/{orderID}/receipt | PaymentHandler.GetOrderReceipt | C,A | ❌ |
| POST | /orders/{orderID}/accept | OrderHandler.AcceptOrder | D,A | ⚠️ usecase `accept_order_test` (12 тестов); HTTP-хендлер не покрыт |
| POST | /orders/{orderID}/status | OrderHandler.UpdateOrderStatus | D,A | ⚠️ usecase `update_status_finance_test`, `finalize_order_test` |
| POST | /orders/{orderID}/finalize | OrderHandler.FinalizeOrder | D,A | ⚠️ usecase `finalize_order_test` |
| POST | /orders/{orderID}/confirm-payment | PaymentHandler.ConfirmPayment | C,A | ⚠️ usecase `finance_confirm_payment_test` |
| PATCH | /orders/{orderID}/payment-method | PaymentHandler.UpdateOrderPaymentMethod | C,A | ❌ |
| POST | /orders/{orderID}/cancel | OrderHandler.CancelOrder | * | ❌ (usecase cancel_order без теста) |
| POST | /orders/{orderID}/decline | OfferHandler.DeclineOffer | D,A | ⚠️ `dispatch_scheduler_test` (indirectly) |
| GET | /driver/current-offer | OfferHandler.GetCurrentOffer | D,A | ❌ |
| GET | /drivers/{driverID} | DriverHandler.GetDriver | * | ❌ |
| GET | /drivers/{driverID}/profile | DriverHandler.GetDriverProfile | * | ❌ |
| GET | /drivers/{driverID}/location | DriverHandler.GetLocation | * | ❌ |
| GET | /drivers/{driverID}/reviews | AdminHandler.GetDriverReviews | * | ❌ |
| POST | /drivers/{driverID}/status | DriverHandler.SetStatus | D,A | ⚠️ usecase `set_status_test` |
| GET | /drivers/{driverID}/tax-profile | DriverHandler.GetTaxProfile | D,A | ❌ |
| PUT | /drivers/{driverID}/tax-profile | DriverHandler.UpsertTaxProfile | D,A | ❌ |
| GET | /drivers/{driverID}/npd/status | DriverHandler.GetNPDStatus | D,A | ⚠️ npd.go:регрессия? нет теста |
| POST | /drivers/{driverID}/npd/connect | DriverHandler.ConnectNPD | D,A | ❌ |
| POST | /drivers/{driverID}/npd/disconnect | DriverHandler.DisconnectNPD | D,A | ❌ |
| GET | /drivers/{driverID}/verification-status | DriverHandler.GetVerificationStatus | D,A | ❌ |
| POST | /driver-verifications | AdminHandler.SubmitDriverVerification | D,A | ❌ |
| POST | /driver-documents/uploads | AdminHandler.CreateDocumentUpload | D,A | ❌ |
| GET | /payments/wallet | PaymentHandler.GetWallet | C,A | ❌ |
| POST | /client/payment-methods/init | PaymentHandler.InitClientPaymentMethod | C,A | ❌ |
| POST | /payments/cards | PaymentHandler.AddCard | C,A | ❌ |
| DELETE | /payments/cards/{cardID} | PaymentHandler.DeleteCard | C,A | ❌ |
| POST | /payments/cards/{cardID}/default | PaymentHandler.SetDefaultCard | C,A | ❌ |
| POST | /payments/promocode/apply | PaymentHandler.ApplyPromocode | C,A | ❌ (хардкод `EVIK2025`) |
| GET | /driver/earnings | PaymentHandler.GetDriverEarnings | D,A | ✅ intg `driver_earnings_test.go` |
| GET | /driver/wallet | PaymentHandler.GetDriverWallet | D,A | ⚠️ partial |
| GET | /driver/wallet/transactions | PaymentHandler.ListDriverWalletTransactions | D,A | ❌ |
| GET | /driver/payouts | PaymentHandler.ListDriverPayouts | D,A | ❌ |
| POST | /driver/payouts/request | PaymentHandler.RequestDriverPayout | D,A | ⚠️ usecase `finance_payout_test` |
| GET | /driver/payout-methods | PaymentHandler.ListDriverPayoutMethods | D,A | ❌ |
| POST | /driver/payout-methods | PaymentHandler.AddDriverPayoutMethod | D,A | ❌ |
| POST | /driver/subscription/payment | PaymentHandler.CreateDriverSubscriptionPayment | D,A | ⚠️ usecase `finance_subscription_test` |
| GET | /driver/subscription/status | PaymentHandler.GetDriverSubscriptionStatus | D,A | ⚠️ usecase `finance_subscription_test` |
| POST | /reviews | AdminHandler.CreateReview | C,A | ❌ |
| GET | /geocode/reverse | GeocodingHandler.Reverse | * | ✅ geocoding_handler_test (5) |
| POST | /pricing/calculate | PricingHandler.CalculatePrice | * | ❌ (domain-тесты pricing есть) |
| GET | /pricing/tariffs | PricingHandler.GetTariffs | * | ❌ |
| GET | /pricing/tariffs/{type} | PricingHandler.GetTariffByType | * | ❌ |
| POST | /routing/orders/{orderID}/route | RoutingHandler.CalculateRoute | D,A | ❌ |
| POST | /routing/orders/{orderID}/directions | RoutingHandler.GetDirections | D,A | ❌ |
| GET | /admin/overview | AdminHandler.Overview | A | ❌ |
| GET | /admin/driver-verifications | AdminHandler.ListDriverVerifications | A | ❌ |
| GET | /admin/users | AdminHandler.ListUsers | A | ❌ |
| GET | /admin/reviews | AdminHandler.ListReviews | A | ❌ |
| POST | /admin/reviews/{reviewID}/hide | AdminHandler.HideReview | A | ❌ |
| POST | /admin/reviews/{reviewID}/show | AdminHandler.ShowReview | A | ❌ |
| DELETE | /admin/reviews/{reviewID} | AdminHandler.DeleteReview | A | ❌ |
| GET | /admin/drivers-online | AdminHandler.ListOnlineDrivers | A | ❌ |
| POST | /admin/moderation/.../approve | AdminHandler.ApproveDriverVerification | A | ❌ |
| POST | /admin/moderation/.../reject | AdminHandler.RejectDriverVerification | A | ❌ |
| POST | /admin/moderation/.../request-changes | AdminHandler.RequestDriverVerificationChanges | A | ❌ |
| POST | /admin/moderation/.../block | AdminHandler.BlockDriverVerification | A | ❌ |
| POST | /admin/moderation/batch/approve | AdminHandler.BatchApproveVerifications | A | ❌ |
| POST | /admin/moderation/batch/reject | AdminHandler.BatchRejectVerifications | A | ❌ |
| GET | /admin/orders | AdminHandler.ListAdminOrders | A | ❌ |
| GET | /admin/orders/{orderID} | AdminHandler.GetAdminOrderDetails | A | ❌ |
| GET | /admin/finance/refunds | PaymentHandler.AdminListRefunds | A | ⚠️ usecase `finance_admin_test` |
| GET | /admin/finance/{reportType} | PaymentHandler.AdminFinanceReport | A | ❌ |
| POST | /admin/finance/payouts/{id}/approve | PaymentHandler.AdminApprovePayout | A | ⚠️ usecase `finance_admin_test` |
| POST | /admin/finance/payouts/{id}/reject | PaymentHandler.AdminRejectPayout | A | ⚠️ usecase `finance_admin_test` |
| POST | /admin/finance/export | PaymentHandler.AdminExportFinance | A | ❌ |
| GET | /admin/tax-profiles | AdminHandler.ListTaxProfiles | A | ❌ |
| POST | /admin/tax-profiles/{id}/verify | AdminHandler.VerifyTaxProfile | A | ❌ |
| POST | /admin/tax-profiles/{id}/reject | AdminHandler.RejectTaxProfile | A | ❌ |
| POST | /admin/tax-profiles/{id}/request-changes | AdminHandler.RequestTaxProfileChanges | A | ❌ |
| GET | /admin/cities/autocomplete | CityHandler.Autocomplete | A | ❌ |
| POST | /admin/cities/search | CityHandler.Search | A | ❌ |
| POST | /admin/cities | CityHandler.Create | A | ❌ |
| GET | /admin/cities | CityHandler.List | A | ❌ |
| PATCH | /admin/cities/{id} | CityHandler.Patch | A | ❌ |
| DELETE | /admin/cities/{id} | CityHandler.Delete | A | ❌ |
| GET | /admin/drivers/locations | DriverLocationsHandler.List | A | ❌ |
| GET | /admin/drivers/{driverID} | AdminHandler.GetDriverDetail | A | ❌ |
| GET | /admin/drivers/{driverID}/orders | AdminHandler.ListDriverOrders | A | ❌ (**падает — `orders.completed_at` не существует**) |
| GET | /admin/finance-v2/payments | AdminHandler.ListAdminPayments | A | ❌ |
| GET | /admin/finance-v2/wallets | AdminHandler.ListAdminWallets | A | ❌ |
| GET | /admin/finance-v2/transactions | AdminHandler.ListAdminTransactions | A | ❌ |
| GET | /admin/finance-v2/subscriptions | AdminHandler.ListAdminSubscriptions | A | ❌ |
| GET | /admin/settings | SettingsHandler.List | A | ❌ |
| PUT | /admin/settings | SettingsHandler.Update | A | ❌ |
| GET | /admin/audit-log | AdminHandler.ListAuditLog | A | ❌ |

Не-Http дополнительные: `GET /healthz` (публичный, без теста), `* /ws/orders` (WS, см. д)).

Итого эндпоинтов: **93 REST + 1 WS + 1 healthz**. Покрытие HTTP-тестом: **~8 из 93**. Покрытие юнит/usecase-логикой (частично): ещё ~15.

---

## д) Диспетчеризация

Участники: `app/dispatch_scheduler.go`, `domain/matching/service.go`, `postgres/offer_repository.go`, `usecase/order/accept_order.go`.

Поток:

1. **Создание заказа** (`create_order.go`) → статус `searching`, публикуется event `order_created`/`searching`, воркер `DispatchScheduler` (тик каждые 2 сек) видит заказ через `offerRepo.ListSearchingWithoutOffer` (нет живого оффера).
2. **Матчинг** (`domain/matching/service.go:FindCandidates`): ищет онлайн-водителей в радиусе (старт 2 км, шаг +2 км до 15 км), фильтрует по подписке/токенам/свежести гео (`LiveDriverChecker` = WS Hub), исключает уже офференных (`exclude`).
3. **Оффер** (`dispatch_scheduler.go:createOffer`): создание строки в `order_offers`, timeout 15 сек (из settings `offer_timeout_seconds`), раунды (`GetCurrentRound`, лимит `dispatch_round_limit`, default 3), WS-пуш водителю (`hub.SendToDriver`) + FCM-пуш.
4. **Принятие** (`usecase/order/accept_order.go:Execute`): требует активный оффер (`GetActiveForOrderAndDriver`), в транзакции `AcceptOrderTx` (status=searching→accepted, driver_id) + `AssignOrderTx` на водителе + `ResolveOfferTx('accepted')`. Идемпотентно (тот же драйвер). Recovery: stale-терминальный заказ освобождает драйвера и ретрай.
5. **Отказ/протухание**: `DeclineOffer` → `ResolveOfferTx('declined')`; `ExpirePending` → `outcome='expired'`; затем `tryOfferNext` следующему кандидату.
6. **Нет кандидатов** → `markNoDriverFound` (статус `no_driver_found` + event + client push).

Воркеры-соседи: `stuck_order_reaper` (searching/accepted timeout → cancel/release), `driver_presence_reaper` (stale online → offline), `expansion_scheduler` (поиски → расширение радиуса/город).

Тесты: `app/dispatch_scheduler_test.go` (8 кейсов), `domain/matching/service_test.go` (6 кейсов), `postgres/offer_repository_test.go`, `usecase/order/accept_order_test.go`, интеграционные accept/race/order_completion_guard.

---

## е) Тепловая карта покрытия

### Backend

| Модуль | Тесты | Тип | Уровень покрытия |
|---|---|---|---|
| `domain/order` | Опосредованно через usecase/accept + postgres intg | unit+intg | Среднее |
| `domain/matching` | service_test.go (6) | unit | ✅ Хорошее |
| `domain/pricing` | distance_test, service_test, tariff_test | unit | ✅ Хорошее |
| `domain/servicearea` | entity_test.go | unit | ⚠️ частичное (нет интеграции с `service_area_repository`) |
| `domain/settings` | entity_test.go | unit | ⚠️ частичное |
| `domain/payment` | Нет прямых | unit (через usecase fakes) | ⚠️ сущности тестируются транзитивно |
| `domain/{driver,user,location,routing,admin}` | Нет | — | ❌ **Полностью без тестов** (driver - только через set_status/gate) |
| `usecase/order` | accept(12), finalize, surcharge, update_status_finance | unit | ✅ Хорошее для accept/finalize |
| `usecase/order/create_order`, `cancel_order` | Нет | — | ❌ **Дыра** |
| `usecase/payment` | finance*.go (11 файлов, ~60+ тестов) | unit | ✅ Хорошее |
| `usecase/driver` | gate_test, set_status_test | unit | ⚠️ хорошее, но npd не покрыт |
| `transport/http/auth_handler` | auth_handler_test (6) | unit | ⚠️ часть методов (Register,RequestOTP,VerifyOTP,Refresh,UpsertDeviceToken) |
| `transport/http/geocoding_handler` | geocoding_handler_test (5) | unit | ✅ |
| `transport/http/order_handler` | order_handler_test (2) | unit (только ACL-хелпер) | ❌ HTTP-флоу не покрыт |
| `transport/http/{driver,payment,admin,pricing,routing,city,settings,offer}` | Нет HTTP-тестов | — | ❌ **Дыра** |
| `transport/ws` | Нет | — | ❌ |
| `infrastructure/postgres` | 15 файлов, ✅ интеграция с реальным Postgres (testcontainers): accept, confirm_payment, earnings, offers, idempotency, split, races, webhook, triggers/FK | **integration** | ✅ Лучшее покрытие в проекте |
| `infrastructure/http` | yookassa_client_test | unit | ⚠️ |
| `infrastructure/{redis,fcm,storage,geocoding,websocket}` | Нет | — | ❌ |
| `app/` | dispatch_scheduler_test (8), driver_presence_reaper_test (6) | unit | ✅ Хорошее |

### Frontend

| Файл | Покрывает |
|---|---|
| `client_bottom_nav_sos_hold_test.dart` | SOS-кнопка (удержание 3с, отмена, micro-move) |
| `client_home_screen_address_test.dart` | Карточка адреса на главном экране (loading/резолв) |
| `order_flow_provider_test.dart` | Стейт-флоу заказа (order_flow state) |
| `ui_audit_screens_test.dart` | Смоук-рендер ключевых экранов |
| `widget_test.dart` | Смоук-тест корневого приложения |
| `role_selection_screen_golden_test.dart` | Golden (Skipped) |

ИТОГО frontend: малозатратные widget/unit тесты. **Пусто:** data-слои (репозитории/датасорсы), все провайдеры (кроме order_flow), экономика (price_calculator, pricing_service), WS-клиент/event_dispatcher, навигация, мок-режим. Основной риск — нет ни одного теста на `http_order_repository`, `payment_repository`, `driver_wallet_repository`.

### Общие дыры (топ-риск, без HTTP-тестов)

1. Весь admin-блок (`/admin/*`) — 30+ эндпоинтов, из них с логикой логики только usecase payment покрыт косвенно.
2. HTTP-слой в целом: покрыты только auth и geocode; остальные 85+ маршрутов без автотестов уровня хендлера (все check-и ролей/валидации пути не проверяются).
3. `usecase/order/create_order.go` и `cancel_order.go` без тестов (базовые сценарии пользователя).
4. Фронтенд data-слой: ни одного теста репозиториев/датасорсов; WS-реалтайм не покрыт.
5. NPD (Мой Налог) коннектор: есть `StubNPDProvider`, но никаких тестов потока connect/disconnect.
6. Диспетчер-инварианты: конкуренция запросов accept/decline на уровне HTTP не проверяется (только на уровне БД/use case).

---

## ж) God-nodes и мёртвый код (СВЕЖИЙ граф, HEAD b8a72b1)

### God-nodes (символы с максимальной связностью, значимые рёбра calls/refs/imports)

| Символ | Файл | deg (in/out) |
|---|---|---|
| `NewContainer()` | `backend/internal/app/container.go` | 52 (1/51) — DI-центр |
| `writeAuthError()` | `backend/internal/transport/http/auth_middleware.go` | 47 (46/1) |
| `New()` | `backend/internal/infrastructure/fcm/sender.go` | 39 (33/6) |
| `userIDFromContext()` | `backend/internal/transport/http/auth_context.go` | 36 (35/1) |
| `orderFlowProvider` | `frontend/.../order_flow_provider.dart` | 35 (35/0) |
| `Payout` | `backend/internal/domain/payment/entity.go` | 26 (23/3) |

FILE-уровень (файлы-хабы, высокий out): `auth_provider.dart` (96), `driver_earnings_screen.dart` (93), `new_driver_home_screen.dart` (84), `order_flow_provider.dart` (82), `driver_status_provider.dart` (58) и др. — концентраторы frontend UI/state.

### Кандидаты в мёртвый код (подтверждено по исходникам)

| Символ | Файл | Статус |
|---|---|---|
| `IsValidStatus()` | `domain/driver/entity.go:54` | ❌ нет вызовов |
| `IsNotFound()` | `infrastructure/postgres/admin_repository.go:1190` | ❌ нет вызовов |
| `PayoutScreenData` | `domain/payment/entity.go:248` | ❌ тип не используется |
| `WalletScreenData` | `domain/payment/entity.go:241` | ❌ тип не используется |
| `Promocode` | `domain/payment/entity.go:45` | ❌ тип не используется (хендлер хардкодит `EVIK2025`) |
| `CreateVerification()` | `infrastructure/postgres/driver_verification_repository.go:91` | ❌ нет вызовов; **содержит INSERT в `moderation_audit_log` с несуществующими колонками** (`verification_id,previous_status,new_status,timestamp`) |
| `RoutingHandler.Preview` | `transport/http/routing_handler.go:162` | ❌ определён, не подключён к роутам (висячий эндпоинт) |

Живые, несмотря на вид в графе: `HaversineDistanceCalculator`, `ServiceImpl` (используются через конструкторы), `StubNPDProvider` (container.go:239).

---

## Итог

- Эндпоинтов REST: **93** (+ `* /ws/orders`, `/healthz`).
- Покрыто HTTP-тестами: **8 / 93** (auth — Register/OTP/Verify/Refresh/UpsertDeviceToken, geocode/reverse; остальные — только юнит/usecase-логика).
- Топ-5 непокрытых критичных зон:
  1. **Admin REST-блок** (`/admin/*`, 30+ эндпоинтов) — без HTTP-тестов; `ListDriverOrders` к тому же задет дрейфом схемы.
  2. **HTTP-слой в целом** — роли, валидации, статус-коды проверяются только для auth и geocode.
  3. **Фронтенд data-слой/реалтайм** — репозитории, датасорсы, WS, провайдеры без тестов.
  4. **`create_order` / `cancel_order` usecase** — базовые клиентские сценарии без тестов.
  5. **Диспетчер/офферы на уровне HTTP** — конкуренция accept/decline не покрыта на уровне маршрутов.
- graphify: **установлен** (`uv tool install graphifyy` → бинарь `graphify`), граф **пересобран на текущем HEAD** `b8a72b1` (7219 узлов / 12522 ребра; подтверждено полем `built_at_commit` в graph.json). SQL-файлы не попали в граф (нет `tree_sitter_sql`), 6 файлов дали 0 узлов, 7 нативных файлов — с синтаксич. ошибками парсера (без влияния на анализ Go/Dart).