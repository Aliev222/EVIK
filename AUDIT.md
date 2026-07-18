| ТЕСТ | service_areas | Зона 'Frankfurt (TEST)' — для тестирования
владельцем вне Махачкалы. УДАЛИТЬ перед запуском. |

# Технический аудит проекта «Авро»

> Агрегатор эвакуаторов (аналог Яндекс.Такси для эвакуаторов). Первый город запуска — Махачкала.
> Стек: Go (Clean Architecture) · Flutter (клиент + водитель) · PostgreSQL · Redis · Firebase FCM · WebSocket · деплой backend на Render, админка на Vercel/Render.
>
> Аудит основан только на реальном коде репозитория. Каждая находка снабжена ссылкой `файл:строка`.
> Дата аудита: 2026-07-08. Ветка `main`, HEAD `888382b`.

---

## 1. Executive Summary

Проект в состоянии **позднего MVP, ~65–70% готовности к продакшену**. Доменное ядро реализовано
качественно: приём заказа защищён от гонки атомарным compare-and-set в SQL, кошелёк и денежные
операции водителя транзакционны (`BeginTx` + `SELECT … FOR UPDATE` + идемпотентные ключи), YooKassa и
FCM-push подключены реально (не мок), конфиг жёстко валидируется в проде. Однако до запуска есть
блокеры в безопасности денег, надёжности вебхука и полное отсутствие инженерных процессов (CI,
метрики, error-tracking). Часть UI-функций водителя/клиента показывает **фиктивные данные**.

**Топ-3 критичных блокера до запуска:**
1. **YooKassa webhook не проверяет подпись** и доверяет спуфящемуся `X-Forwarded-For` — единственная защита это IP-allowlist + перезапрос статуса у провайдера (B-01).
2. **Webhook не идемпотентен на ретрае**: маркер «обработано» пишется до side-effects, поэтому первый же частичный сбой навсегда блокирует финансовое завершение заказа/подписки (B-02, B-03).
3. **Нет CI/CD, метрик и error-tracking** на платёжной платформе: 19 тест-файлов никогда не гоняются автоматически, в проде нет наблюдаемости (B-15).

Дополнительно опасны для доверия пользователей: **промокод показывается, но к оплате не применяется**
(B-09) и **заработок водителя фабрикуется на клиенте** (B-10).

---

## 2. Карта проекта

### 2.1. Структура (backend)

```
backend/
├── cmd/app/main.go                      # entry point: конфиг, миграции (goose), HTTP-сервер, graceful shutdown
├── internal/
│   ├── config/config.go                 # env-driven конфиг + validateProductionConfig
│   ├── app/
│   │   ├── container.go                  # composition root (DI), EnsureSchema (inline DDL), seed настроек
│   │   └── expansion_scheduler.go        # фоновое расширение радиуса поиска
│   ├── auth/tokens.go                    # JWT access/refresh
│   ├── domain/                           # сущности + интерфейсы репозиториев (без импорта infra)
│   │   ├── order/ (entity, state_machine, event)
│   │   ├── driver/  user/  location/  pricing/  payment/  servicearea/  matching/
│   ├── usecase/                          # оркестрация
│   │   ├── order/ (create, accept, update_status, finalize, cancel)
│   │   ├── payment/finance.go            # платежи, вебхук, комиссия, подписки
│   │   ├── matching/find_driver.go       # поиск водителя + расширение радиуса
│   │   └── driver/gate.go                # гейт подписки
│   ├── infrastructure/
│   │   ├── postgres/ (order/driver/payment/user/... repositories)
│   │   ├── redis/location_store.go       # GEORADIUS, гео-кэш
│   │   ├── websocket/ (hub.go, order_event_relay.go)
│   │   ├── fcm/sender.go                 # Firebase Admin SDK, push с ретраем
│   │   ├── http/yookassa_client.go       # реальный клиент YooKassa
│   │   └── geocoding / storage (S3)
│   └── transport/
│       ├── http/ (router.go, *_handler.go, auth_middleware.go, rate_limiter.go)
│       └── ws/order_ws_handler.go
├── migrations/*.sql                      # 18 goose-миграций 20260510→20260527
├── migrations.go / migrations_init_prod.sql
└── docs/ (swagger.json/yaml/docs.go)
```

### 2.2. Структура (frontend)

```
frontend/lib/
├── main.dart
├── core/
│   ├── network/ (api_client_io.dart [native], api_client_stub.dart [web], api_client.dart [base URL])
│   ├── realtime/ (websocket_client_io.dart, event_dispatcher.dart) + realtime_location_service.dart
│   ├── notifications/push_notification_service.dart   # FCM
│   ├── services/ (location_service.dart, price_calculator.dart [legacy])
│   ├── storage/key_value_storage.dart
│   └── theme/ · error/global_error_handler.dart
├── features/
│   ├── auth/ (auth_provider.dart, auth_retry_coordinator.dart, экраны OTP)
│   ├── client/presentation/screens/ (~16 экранов)
│   ├── driver/presentation/screens/ (~12 экранов) + providers/driver_earnings_provider.dart
│   ├── order/ (http_order_repository.dart, order_flow_provider.dart, state_machine на клиенте)
│   └── map/ (flutter_map / OSM)
└── shared/ + admin-web/ (vanilla-JS SPA + Go reverse-proxy)
```

### 2.3. Слои Clean Architecture (Go) — соблюдение

Разделение чистое: `domain` не импортирует инфраструктуру, `usecase` зависит от доменных интерфейсов,
`transport` — тонкий. Нарушения/запахи:

| Нарушение | Где | Серьёзность |
|---|---|---|
| Схема БД описана и в Go (`EnsureSchema`), и в миграциях — два источника истины | `internal/app/container.go:294-725` vs `backend/migrations/*.sql` | HIGH (B-08) |
| Доменный `StateMachine` фактически мёртв — статусы выставляются сырым присваиванием | `domain/order/state_machine.go` vs `usecase/payment/finance.go:318,357,373` | MEDIUM (B-17) |
| infra→infra: relay напрямую импортирует пакет `redis` | `infrastructure/websocket/order_event_relay.go:9` | LOW |

### 2.4. HTTP-эндпоинты

Источник маршрутов — `backend/internal/transport/http/router.go`.

**Публичные (`/api/v1`, без JWT):**

| Метод | Путь | Файл:строка | Прим. |
|---|---|---|---|
| POST | /auth/register | router.go:56 | |
| POST | /auth/login | router.go:57 | rate-limit 10/мин/IP |
| POST | /auth/otp/request | router.go:58 | 3/мин/телефон |
| POST | /auth/otp/verify | router.go:59 | 5/мин/телефон |
| POST | /auth/admin/login | router.go:60 | 5/мин/IP |
| POST | /auth/refresh | router.go:61 | |
| POST | /webhooks/yookassa | router.go:62 → payment_handler.go:462 | без подписи (B-01) |
| GET | /service-areas/check | router.go:63 | |

**Защищённые (JWT, `authMW`):** `GET /auth/me` (:67), `POST /devices/fcm-token` (:68), revoke (:69).
Заказы: `POST /orders` (:71), `GET /orders` (:72), `/orders/active` (:73), `/orders/{id}` (:74),
`/orders/{id}/review` (:75), `POST /orders/{id}/payments` (:76), `GET …/payment-status` (:77),
`…/receipt` (:78), `POST …/accept` (:79), `…/status` (:80), `…/finalize` (:81), `…/confirm-payment`
(:82), `PATCH …/payment-method` (:83), `POST …/cancel` (:84). Водители: `GET /drivers/{id}` (:85),
`/profile` (:86), `/location` (:87), `/reviews` (:88), `POST …/status` (:89), tax-profile (:90-91),
npd (:92-94), verification (:95-96), documents/uploads (:97). Платежи/кошелёк: `/payments/wallet`
(:98), card init/delete/default (:99-102), promocode (:103), driver wallet/payouts/subscription
(:104-111), `POST /reviews` (:112). Прайсинг: `POST /pricing/calculate` (:115), tariffs (:116-117).
Роутинг: `POST /routing/orders/{id}/route` (:120), `/directions` (:121). Админ (`/admin`, роль admin,
:123-176): overview, driver-verifications + модерация, users, reviews CRUD, drivers-online, orders,
finance (refunds/reports/payouts/export), tax-profiles, cities CRUD, driver locations, settings
GET/PUT, audit-log. Инфра: `GET /swagger/*` (:181, только при `EXPOSE_SWAGGER=true`), `GET /healthz`
(:183), `HEAD /ws/orders` (:187), `GET /ws/orders` (:190).

> Примечание: `POST /payments/cards` (router.go:100) намеренно возвращает **410 Gone**
> (payment_handler.go:971) — прямой ввод карты отключён, привязка только через hosted-флоу YooKassa.

### 2.5. WebSocket-события

Константы типов — `domain/order/event.go:5-18` (12 типов):
`order_created, searching, order_accepted, order_arrived, in_progress, awaiting_payment, completed,
cancelled, no_driver_found, order_expanded, driver_location, admin_driver_location`.

Публикация: usecase’ы шлют событие в Redis pub/sub канал `orders:status` (`container.go:190`); relay
(`infrastructure/websocket/order_event_relay.go:28`) подписан и разводит по типам (`:56-110`):
`created` → клиент + водители города; `searching` → водители города; `expanded` → все водители;
`driver_location` → владелец-клиент + админы; остальное → user/driver/broadcast. Реконнекта на сервере
нет, только ping/pong (`order_ws_handler.go:101-135`).

### 2.6. Таблицы БД и связи

~27 таблиц (из `EnsureSchema` + `migrations/*`): `users, user_refresh_sessions, user_device_tokens,
phone_otps, orders, drivers, payment_methods, payment_transactions (DEPRECATED), payments,
driver_wallets, wallet_transactions, payouts, driver_payout_methods, subscriptions, commission_rules,
refunds, payment_webhooks, finance_reports_exports, wallet_transaction_locks, pricing_tariffs,
driver_verifications, moderation_audit_log, driver_tax_profiles, platform_settings, service_areas,
driver_reviews`.

FK-констрейнты добавлены поздно (`migrations/20260526_add_foreign_key_constraints.sql`): `orders.user_id`,
`orders.driver_id`, `payments.user_id`, `payments.order_id`, `drivers.user_id`, `driver_wallets.driver_id`.
**Отсутствуют FK** (B-19): `wallet_transactions.{order_id,payment_id,payout_id}`, `payouts.driver_id`,
`subscriptions.driver_id`, `driver_payout_methods.driver_id`, `orders.city_id → service_areas`,
`driver_tax_profiles.driver_id`, `refunds` (только payment). Индексы в целом хорошие (status/updated_at,
композиты, партиальный `idx_wallet_transactions_pending_release`), но `payment_webhooks` без индекса/unique
на event id (идемпотентность только в коде), и нет `payments(order_id,status)` под горячий
`CompleteOrderFinancially`.

### 2.7. Жизненный цикл заказа

Статусы (`domain/order/state_machine.go:5-14`): `created → searching → accepted → arrived →
in_progress → awaiting_payment → completed`, плюс `cancelled` и `no_driver_found`. Переходы:
create→searching (`create_order.go:166`), searching→accepted (атомарно `order_repository.go:83-89` и
matcher `find_driver.go:84`), searching→no_driver_found (`find_driver.go:130`),
accepted→arrived→in_progress→awaiting_payment (`update_status.go:34` через `TransitionTo`),
awaiting_payment→completed (**минуя state machine**, сырое присваивание в `finance.go:318,357,373` — B-17).

### 2.8. Основные экраны Flutter

**Клиент (`features/client/presentation/screens/`, ~16):** client_app_shell, client_home_screen,
pickup_location_screen, destination_location_screen, vehicle_selection_screen, tow_truck_selection_screen,
service_detail_screen, order_review_screen, driver_search_screen, driver_info_screen, tracking_screen,
order_completion_screen, driver_rating_screen, client_history_screen, client_wallet_screen,
client_profile_screen.

**Водитель (`features/driver/presentation/screens/`, ~12):** new_driver_home_screen, driver_main_screen,
active_order_screen, driver_orders_history_screen, driver_earnings_screen, driver_profile_screen,
driver_profile_setup_screen, driver_documents_screen, document_camera_screen, driver_moderation_screen,
moderation_waiting_screen, driver_tax_profile_screen. (Есть дубли/легаси: `driver_screen.dart`,
две реализации home — см. B-28 и раздел 5.)

---

## 3. Таблица готовности модулей

| Модуль | Статус | Комментарий (файл:строка) |
|---|---|---|
| Аутентификация / JWT / refresh / роли | 🟡 | Native-refresh работает single-flight (`auth_provider.dart:329-334`); на **web нет refresh/ретраев** (`api_client_stub.dart:61-114`, B-12). Захардкожен `password:'dev-password'` в проде-пути (`auth_provider.dart:298`). |
| Создание заказа + жизненный цикл статусов | ✅ | Полный цикл реализован; переход в `completed` минует state machine (B-17). |
| Расчёт цены (тариф, A→B, наценки, межгород) | 🟡 | Работает, но дистанция — **Haversine (не дорожная)** → недосчёт (`pricing/entity.go:62`, `service.go:98`); surge/ночь не реализованы. |
| Расчёт комиссии и сплита | ⚠️ | Атомарно и корректно арифметически, но **комиссия захардкожена 15%**, настройки/`commission_rules` игнорируются (B-04). |
| Межгородская наценка | ⚠️ | Применяется **только для наличных**, карта — TODO (B-05). |
| Маршрутизация заказа водителям (ближайший, радиус) | 🟡 | GEORADIUS + расширение радиуса работают; N+1 по Redis и нет проверки свежести гео (B-18). |
| Real-time (WebSocket, реконнект, throttle гео) | ⚠️ | Backend WS есть, но **клиент на 2-сек HTTP-поллинге**; WS-клиент без reconnect/heartbeat (B-28). Single-instance hub (B-07). |
| Геолокация и карты (Redis-кэш, GEORADIUS, границы города) | ✅ | GEORADIUS + service-areas + city detection реализованы. |
| Платёжный слой (YooKassa / мок / Точка) | ⚠️ | **YooKassa реальный** (не мок), Точки нет; вебхук без подписи (B-01) и не идемпотентен на ретрае (B-02). |
| Баланс водителя и транзакции | ✅ | Ledger атомарен: `BeginTx`+`FOR UPDATE`+idempotency (`payment_repository.go:525-624,815-860`). |
| Подписки водителей | 🟡 | Логика есть, но **баг ключей цен** → админ-цены игнорируются (B-16); UI почти отсутствует. |
| Push-уведомления (FCM, retry) | ✅ | Firebase Admin SDK + ретрай 3×backoff (`fcm/sender.go:169-189`), cleanup dead-токенов; broadcast-ошибки глотаются (B-25). |
| Админ-панель | 🟡 | Функциональна (vanilla-JS SPA + Go reverse-proxy), JWT в localStorage; нет refresh в админ-JS. |
| CI/CD, метрики, error-tracking | 🔴 | Не найдено ничего (B-15). |

---

## 4. Реестр багов

Отсортировано по серьёзности. Класс: 🟥 critical · 🟧 high · 🟨 medium · ⬜ low/info.

| ID | Файл:строка | Описание | Серьёзность | Предлагаемый фикс |
|---|---|---|---|---|
| B-01 | `transport/http/payment_handler.go:462`, `:24-62` | YooKassa webhook без проверки подписи; `getClientIP` безусловно доверяет первому `X-Forwarded-For` (`:51-62`) → IP-allowlist спуфится. | 🟥 critical | Проверять подпись/секрет YooKassa; доверять XFF только за trusted-proxy (или брать RemoteAddr). |
| B-02 | `usecase/payment/finance.go:266-269`,`:274` | «seen»-маркер (`StoreWebhook`) пишется ДО side-effects; сбой `GetPayment` после вставки → ретраи короткозамыкаются, заказ/подписка **никогда не завершаются**. | 🟧 high | Маркировать processed только после успеха; при ошибке — не считать webhook обработанным. |
| B-03 | `usecase/payment/finance.go:281-324` | `UpdatePaymentFromProvider`→активация подписки→`CompleteOrderFinancially`→`orders.Update` без общей транзакции, с ранними `return`. | 🟧 high | Обернуть все side-effects вебхука в одну БД-транзакцию. |
| B-04 | `infrastructure/postgres/payment_repository.go:14,580` | Комиссия захардкожена `defaultCommissionPercent=15`; `platform_settings.commission_percent` и `commission_rules` (`container.go:561,612,712`) не читаются. | 🟧 high | Читать процент из настроек/правил на момент завершения заказа. |
| B-05 | `usecase/order/accept_order.go:188`,`:186-187` | Межгородская наценка 50% только для `cash`; карта — TODO, наценка теряется. | 🟧 high | Доплата картой через YooKassa либо запрет карты для cross-city. |
| B-06 | `usecase/order/accept_order.go:68-119`,`:112` | Приём заказа = 4 отдельных запроса без общей транзакции; сбой `Update` → водитель released, заказ остаётся `accepted`. (Сам double-accept безопасен: `order_repository.go:83-89`.) | 🟧 high | Одна транзакция на приём (accept+assign+surcharge). |
| B-07 | `infrastructure/websocket/hub.go`, `order_event_relay.go` | Единый in-process hub; при нескольких репликах WS-события теряются. | 🟧 high | Redis-backed fan-out / sticky sessions, либо явно один инстанс. |
| B-08 | `internal/app/container.go:294-725`; `migrations_init_prod.sql` | Два источника схемы (EnsureSchema + goose); `main.go:97-104` гоняет оба; init-скрипт заявляет 6 миграций при 18 файлах → риск дрейфа `goose_db_version`. | 🟧 high | Один источник (goose); удалить/заморозить `EnsureSchema`; сверить трекер в проде. |
| B-09 | `features/.../payment_wallet.dart:270,276`; `order_flow_provider.dart:262` | Промокод отображается/хранится, но `discountPct` нигде не читается, к цене не применяется и не парсится назад. | 🟧 high | Передавать промокод в `/pricing/calculate` и при создании заказа; применять скидку на бэке. |
| B-10 | `features/driver/.../providers/driver_earnings_provider.dart:60-70` | Заработок фабрикуется: `today=count*2500`, `week=+12300`, `month=+45600`, `rating:4.9`. | 🟧 high | Брать реальные суммы из `/driver/wallet` + `/transactions`. |
| B-11 | `core/network/api_client_io.dart:70-158` | POST/PUT/PATCH ретраятся до 3× на timeout/socket → дубли заказов/платежей на медленном бэке. | 🟧 high | Не ретраить неидемпотентные методы или слать `Idempotency-Key` (как у payout, `driver_wallet_repository.dart:89`). |
| B-12 | `core/network/api_client_stub.dart:61-114` | Web-клиент без refresh-токена и без ретраев → авторизация ломается после истечения токена. | 🟧 high | Портировать 401-refresh/ретрай из io-клиента. |
| B-13 | `features/order/.../http_order_repository.dart:56`; `auth_provider.dart:695-711` | В логи печатается bearer-токен и refresh/me ответы (76 debugPrint в 16 файлах). | 🟧 high | Убрать логирование секретов; gate за `kDebugMode` без токенов. |
| B-14 | `transport/http/router.go:57-60`; `rate_limiter.go:76-82` | Нет rate-limit на `/orders`, `/accept`, создание платежа, webhook; лимитер in-memory per-instance, XFF-spoofable. | 🟧 high | Redis-лимитер на критичных ручках; не доверять XFF. |
| B-15 | `.github/workflows` — не найдено | Нет CI/CD (тесты не гоняются), нет метрик (Prometheus/OTel — не найдено), нет error-tracking (Sentry — не найдено). | 🟧 high | Добавить CI (build+vet+test+analyze), Sentry, базовые метрики. |
| B-16 | `internal/app/container.go:718-720`; `usecase/payment/finance.go:644-650` | Seed-ключи `driver_subscription_{daily,weekly,monthly}_price`, а lookup строит `_{pro_day,pro_week,pro_month}_price` → админ-цены игнорируются, берётся хардкод. | 🟧 high | Согласовать ключи settings и planID. |
| B-17 | `usecase/payment/finance.go:318,357,373` | Переход в `completed` минует `order/state_machine.go` (сырое присваивание) → возможен переход из любого статуса. | 🟨 medium | Проводить все переходы через `TransitionTo`. |
| B-18 | `infrastructure/redis/location_store.go:49`,`:48` | N+1: `GET updated_at` на каждого водителя в цикле (не pipeline); свежесть гео не проверяется (дефолт `now`) → офлайн-водитель матчится. | 🟨 medium | Pipeline; фильтр по TTL/свежести. |
| B-19 | `internal/app/container.go:491,513` | Отсутствуют FK на денежных таблицах (`wallet_transactions.*`, `payouts.driver_id`, `subscriptions.driver_id`, `orders.city_id` …). | 🟨 medium | Добавить FK-констрейнты миграцией. |
| B-20 | `internal/app/container.go:164-175` | Redis без конфигурации пула/таймаутов → медленный Redis стопорит диспетч. | 🟨 medium | Задать pool size, read/write/dial timeouts. |
| B-21 | `cmd/app/main.go`; `usecase/order/create_order.go:125,221` | Фоновые горутины (schedulers, hub.Run, relay, detached goroutines) без `recover()`; паника роняет процесс. | 🟨 medium | `recover()` в каждой долгоживущей горутине; `WaitGroup` на shutdown. |
| B-22 | `transport/http/router.go:183-186` | `/healthz` возвращает статичный «ok», не проверяет БД/Redis (liveness ≠ readiness). | 🟨 medium | Добавить `/readyz` с ping БД+Redis. |
| B-23 | `cmd/app/main.go:35`; `container.go:55-60` | Логирование неструктурированное (stdlib `log`), без JSON/уровней/корреляции. | 🟨 medium | slog/zap с уровнями и request-id. |
| B-24 | `frontend/analysis_options.yaml:13-19` | 6 файлов (в т.ч. `price_calculator.dart`, order-файлы) исключены из анализатора → прячут ошибки (см. чистый вывод analyze в 5.2). | 🟨 medium | Убрать excludes, починить issue. |
| B-25 | `infrastructure/fcm/sender.go:155-161`,`:208-215` | `sendMulticast` глотает ошибки батча (`continue`, всегда `nil`); dead-токены при broadcast не чистятся. | 🟨 medium | Возвращать агрегированную ошибку; чистить токены и на broadcast. |
| B-26 | `backend/docs/swagger.yaml` | Swagger от 2026-07-03, HEAD 2026-07-08 с фичами — устарел на несколько коммитов. | 🟨 medium | Перегенерировать перед публикацией. |
| B-27 | `transport/ws/order_ws_handler.go:38-40`,`:56-58` | Пустой `Origin` всегда разрешён; токен принимается через query-param → утечка в логи/прокси. | 🟨 medium | Проверять Origin; передавать токен в заголовке/subprotocol. |
| B-28 | `core/realtime/websocket_client_io.dart`; `order_flow_provider.dart:318-325` | WS-клиент без reconnect/heartbeat, `onReconnected` не вызывается; клиент реально живёт на 2-сек поллинге; две конкурирующие realtime-реализации. | 🟨 medium | Единый WS-клиент с backoff-reconnect + heartbeat; убрать поллинг или дублирующий стек. |
| B-29 | git-tracked: `Tow truck-handoff.zip`, `branch-audit/*.diff` | В `branch-audit/*.diff` закоммичены `pk_live_...` ключ и `jwtSecret` литералы; лишние zip/логи/`.bat`/`app.js`. | ⬜ low | Удалить артефакты из git; ротировать засвеченные ключи. |
| B-30 | `docker-compose.yml:11`; `render.yaml` | Хардкод `POSTGRES_PASSWORD: evik` (только dev); `render.yaml` не объявляет env YooKassa/S3/Firebase/ADMIN_PASSWORD → `log.Fatal` в проде (`config.go:141-172`). | ⬜ low | Объявить обязательные env в render.yaml; секреты в dashboard. |
| B-31 | `transport/http/order_handler.go:369` | `GetOrder` даёт любому водителю читать `searching`-заказ (пул) — by design, но раскрывает адрес/цену всех заказов. | ⬜ low | Ограничить поля / гео-скоуп для пула. |
| B-41 | `admin_repository.go:829`, `:1081` | `ListAdminWallets` и `AdminGetDriverDetail` читают `available_balance`, `pending_balance`, `debt_balance` из `driver_wallets` без `rub_to_cents()`. NUMERIC(12,2) рубли сканируются в Go `int64` как целое число (×100 ошибка). Расхождение ×100 в админ-панели. Фикс: миграция на BIGINT-копейки устраняет причину — после неё BIGINT читается напрямую без конвертера. | 🟧 high | Миграция денежных колонок NUMERIC(12,2) → BIGINT (копейки), удаление конвертеров. |
| B-43 | `infrastructure/postgres/order_repository.go:549-558` | Админка показывает 0 дохода водителя по наличным заказам. `driver_amount` считается как `SUM(wt.amount) WHERE type='order_income'`, для наличных этой строки нет. | 🟧 high | B-10: хранить `driver_amount` в самой таблице `orders`. |
| B-44 | `usecase/payment/finance.go:399-423` | `CompleteOrderFinancially` (tx1) и `orderRepo.Update(status=completed)` (tx2) — две отдельные транзакции. При падении между ними деньги начислены, статус не обновлён, заказ не попадёт в выборку заработка. | 🟨 medium | Объединить в одну транзакцию (связано с B-03). |
| B-45 | `transport/http/order_handler.go:525-549`; `router.go:80`; `usecase/order/update_status.go:23` | `POST /orders/{orderID}/status` (RoleDriver, RoleAdmin) принимает `{"status":"completed"}` и переводит заказ в `completed` БЕЗ `CompleteOrderFinancially`. Клиент не платит, водителю не начислено, комиссия/долг не зафиксированы. | 🟥 critical | Запретить `completed` через общий эндпоинт → ошибка; CHECK-констрейнт: `completed` → `financially_completed_at IS NOT NULL`. |
| B-46 | `frontend/test/ui_audit_screens_test.dart` | Flutter-тесты `ClientHomeScreen` и `DriverHomeScreen` падают на pending-таймере от `geolocator.getCurrentPosition` (10s). CI бы их не пропустил. | ⬜ low | Мокать `Geolocator` в тестах или выставлять `pump` с `Duration` для таймера. |
| B-48 | `new_driver_provider.dart`, `drivers_stats.dart` | `DriverStats` хранит `double` рубли вместо `int` копеек; требует инлайновых `/100` при маппинге из `EarningsStats`. Второй формат денег на клиенте. | ⬜ low | Унифицировать при рефакторинге home screen: `DriverStats` → int копейки. |

---

## 5. Тесты и качество кода

### 5.1. Покрытие тестами

**Backend (19 `_test.go`):** сильный набор в `usecase/payment` (`finance_*_test.go` — webhook, payout,
refund, release, subscription, create_payment, admin), а также pricing (distance/service/tariff),
yookassa client, auth handler, order handler, driver gate/set_status, order accept + update_status_finance.

**Не покрыто (критично):** `usecase/matching/find_driver.go` (расширение радиуса, конкурентный
assign), `create_order.go`, `cancel_order.go`, `finalize_order.go`, **все postgres-репозитории** (нет
интеграционных тестов на атомарность `AcceptOrder`, арифметику комиссии в `CompleteOrderFinancially`,
блокировки кошелька), redis `location_store`, websocket hub/relay, rate limiter, IP/подпись вебхука.
Самый чувствительный SQL (`payment_repository.go:525`) тестируется только через usecase-фейки.

**Frontend (`frontend/test/`):** 4 теста + 1 test-double (`widget_test.dart` рендерит только
RoleSelectionScreen; `role_selection_screen_golden_test.dart`; `order_flow_provider_test.dart` — один
happy-path; `ui_audit_screens_test.dart`). Покрытие критичных потоков (auth/OTP/refresh, создание
заказа, оплата/finalize/confirm, промокод, WebSocket, заработок) — **фактически нулевое**.

### 5.2. Вывод инструментов (фактический прогон, 2026-07-08)

**`cd backend && go vet ./...`** → **чисто, exit 0, без замечаний.**

**`cd backend && go test ./... -cover`** → все пакеты проходят (exit 0, падений нет). Покрытие крайне
неравномерное — денежные и repo-пути почти не покрыты:

```
domain/pricing                     94.2%   ✅
usecase/payment                    63.5%
usecase/driver                     36.0%
usecase/order                      25.9%   ← accept/finalize/cancel слабо покрыты
infrastructure/http (yookassa)      8.5%
transport/http                      5.4%
infrastructure/postgres             0.0%   ← ВСЕ репозитории без тестов (деньги!)
infrastructure/redis                0.0%
infrastructure/websocket            0.0%
usecase/matching                    0.0%   ← матчинг без тестов
transport/ws                        0.0%
auth / config / fcm / geocoding     0.0%
domain/{payment,location,admin,...} [no test files]
```

**`cd frontend && flutter analyze`** → exit 0, **2 issues (info)**:

```
info - 'withOpacity' is deprecated ... Use .withValues() - lib/main.dart:273:32
info - 'withOpacity' is deprecated ... Use .withValues() - lib/main.dart:286:28
2 issues found. (ran in 40.0s)
```

> Важно: почти чистый результат analyze обманчив — 6 файлов исключены из анализа
> (`analysis_options.yaml:13-19`, B-24), включая `price_calculator.dart` и order-файлы, поэтому их
> потенциальные проблемы analyze не видит.

**`golangci-lint run`** — не настроен в репозитории (конфиг `.golangci.yml`/`.golangci.yaml` не найден);
запускался только `go vet`.

### 5.3. Прочее качество
- Frontend: 6 файлов исключены из анализатора (B-24); 76 `debugPrint` в 16 файлах, включая утечку токена (B-13); дубли/легаси-файлы (две realtime-реализации, `order_screen.dart`/`order_state_notifier.dart`, `driver_screen.dart`, `price_calculator.dart`).
- Backend: код идиоматичен, `defer rows.Close()` соблюдается, SQL параметризован (инъекций не найдено), `go vet` чист.

### 5.4. Результаты golangci-lint (фактический прогон, 2026-07-08)

> Дополнение к 5.2: на момент того прогона конфиг `.golangci.yml` не был найден. Позже он был
> добавлен в **`backend/.golangci.yml`** (рядом с `go.mod`; в git пока не закоммичен — линтер
> подхватывает его из рабочей директории). Ниже — фактический прогон.

**Версия линтера:** `golangci-lint v1.64.8` (собран с `go1.26.2`). Конфиг — схема **v1**
(`linters.disable-all` + явный `enable`, `gosimple` как отдельный линтер). Схема совместима с
мажорной версией линтера, **конфиг распарсился без ошибок** (никаких `unknown linter` /
`unsupported version` / `invalid config`).

**Команда:** `cd backend && golangci-lint run ./...` → exit 1 (есть находки, не ошибка конфига).

**Всего находок: 194.** Разбивка по линтерам:

| Линтер | Кол-во | Класс проблемы |
|---|---|---|
| errcheck | 57 | проглоченные ошибки |
| govet (shadow) | 44 | затенение `err` (все 44 — `shadow`) |
| gocritic | 37 | производительность (hugeParam 25, rangeValCopy 12) |
| unused | 15 | мёртвый код |
| gosec | 14 | G201/G202 — **все ложноположительные** (см. ниже) |
| errorlint | 14 | сравнение/обёртка ошибок |
| ineffassign | 4 | бесполезные присваивания |
| staticcheck | 3 | SA1019 — использование deprecated API |
| contextcheck | 3 | непроброс `context.Context` |
| nilerr | 2 | `return nil` при `err != nil` |
| gosimple | 1 | упрощение |

Линтеры `bodyclose`, `sqlclosecheck`, `rowserrcheck`, `copyloopvar`, `unparam`, `durationcheck`,
`noctx`, `prealloc` — **0 находок** (утечек ресурсов и захвата loop-переменной не найдено; на
`go1.22+` захват переменной цикла безопасен by design).

> **Важный нюанс к 5.2:** «`go vet` чист» остаётся верным — дефолтный `go vet` не включает
> анализатор `shadow`. golangci-lint гоняет `govet` с `enable-all`, поэтому всплыли 44 затенения
> `err`. Это не противоречие, а более строгая настройка.

#### Группа 1 — errcheck / nilerr / errorlint (проглоченные и неправильно обработанные ошибки)

**errcheck — 57.** Денежные/заказные пути (🟥/🟧):

| Файл:строка | Линтер | Описание | Путь |
|---|---|---|---|
| `usecase/payment/finance.go:293-294` | errcheck | `strconv.Atoi` срока карты не проверяется | 🟧 деньги |
| `transport/http/order_handler.go:316` | errcheck | результат `orderRepo.ListByStatusAndCity` отброшен | 🟧 заказ |
| `transport/http/order_handler.go:793` | errcheck | результат `orderRepo.ListExpandedSearching` отброшен | 🟧 заказ |
| `transport/http/order_handler.go:324` | errcheck | `cityCache.ClearLastCity` не проверен | 🟨 заказ |
| `transport/http/payment_handler.go:760` | errcheck | `csv.Writer.WriteAll` (выгрузка платежей) не проверен | 🟨 деньги |
| `transport/http/payment_handler.go:1225` | errcheck | `strconv.Atoi` не проверен | 🟨 деньги |
| `infrastructure/postgres/payment_repository.go:568` | errcheck | `Row.Scan` статуса платежа в `CompleteOrderFinancially` отброшен | 🟨 деньги |
| `infrastructure/postgres/payment_repository.go:*` (×15) | errcheck | `tx.Rollback` в defer не проверяется | ⬜ деньги (fail-safe) |
| `usecase/driver/set_status.go:245` | errcheck | `eventPublisher.Publish` не проверен | 🟨 конкур. |
| `infrastructure/websocket/order_event_relay.go:52-121` | errcheck | 6× непроверенных type-assertion при разборе payload | 🟨 |
| `transport/ws/order_ws_handler.go:101-132` | errcheck | 4× `SetReadDeadline/SetWriteDeadline/WriteMessage` | ⬜ |
| прочие (`auth_handler`, `driver_handler`, `admin_handler`, middleware …) | errcheck | `json.Encode`/`w.Write`/`userIDFromContext` не проверены | ⬜ |

**nilerr — 2** (🟨, гео/матчинг):

| Файл:строка | Описание |
|---|---|
| `infrastructure/redis/location_store.go:198` | `err != nil` (строка 196), но возвращается `nil` — ошибка Redis маскируется |
| `infrastructure/redis/location_store.go:202` | то же для строки 200 |

**errorlint — 14** (🟨). Сравнение ошибок через `==`/`!=` (ломается на обёрнутых):
`transport/http/routing_handler.go:69,122`, `pricing_handler.go:169`,
`infrastructure/postgres/driver_verification_repository.go:37`, `usecase/driver/gate_test.go:30,38,46`.
Не-оборачивающий `fmt.Errorf` (нужен `%w`): `domain/order/errors.go:16`, `domain/driver/errors.go:15`,
`app/container.go:73,75,77`, `infrastructure/http/yookassa_client.go:180,224`.

#### Группа 2 — bodyclose / sqlclosecheck / rowserrcheck (утечки ресурсов)

**0 находок.** Подтверждает вывод 5.3 о соблюдении `defer rows.Close()`.

#### Группа 3 — gosec / gocritic (числовая арифметика, переполнения)

**gosec — 14, все G201/G202 (SQL string formatting/concatenation), все ложноположительные.**
Проверено вручную: во всех случаях динамически собирается только `WHERE`-часть из **статических**
предикатов, а значения передаются через `args...`/`argRef()` (плейсхолдеры `$N`). Пользовательские
данные в SQL не конкатенируются → инъекции нет. Это **подтверждает** 5.3, а не опровергает.

| Файл:строка | Код | Вердикт |
|---|---|---|
| `admin_repository.go:478,490,824,828,876,880,916,920,966,970` (×10) | G201 | ложноположительное (parametrized WHERE) |
| `driver_repository.go:328` | G201 | ложноположительное |
| `order_repository.go:535` | G202 | ложноположительное |
| `payment_repository.go:1158` | G202 | ложноположительное |
| `user_repository.go:213` | G202 | ложноположительное (`IN (...)` из `argRef`) |

> **Важно для денежной арифметики:** ни одной находки **G109/G115** (переполнение при конвертации
> чисел) линтер не выдал. Значит баг комиссии **B-04** — это логическая ошибка (хардкод 15%), а не
> арифметическое переполнение; gosec его не ловит, покрытие тестами по-прежнему обязательно.

**gocritic — 37, только производительность** (не корректность): `hugeParam` (25 — тяжёлые структуры
`method`/`filter`/`refund`/`transaction` передаются по значению, до 176 байт) и `rangeValCopy`
(12 — копирование 160–208 байт на итерацию). Сосредоточены в `payment_repository.go`,
`payment_handler.go`, `usecase/payment/finance.go`, `order_repository.go`, `create_order.go`. ⬜ low.

#### Группа 4 — govet / copyloopvar (конкурентность)

**govet — 44, все `shadow`** (затенение `err`). copyloopvar / copylocks / lostcancel — 0.
Затенение сконцентрировано в денежных путях: `payment_repository.go` (×17),
`usecase/payment/finance.go` (×3), `usecase/order/create_order.go` (×5),
`transport/http/payment_handler.go` (×5). Риск: во вложенном блоке присваивается `err :=`, внешняя
переменная не обновляется → ошибка может «потеряться». 🟨.

**contextcheck — 3** (пересекается с B-21): `infrastructure/websocket/order_event_relay.go:38` и
`usecase/order/create_order.go:125` — отсоединённые горутины не пробрасывают `context.Context`.

#### Группа 5 — unused / unparam / ineffassign (мёртвый код)

**unused — 15.** Мёртвый бэкенд-код, в основном легаси-привязка карт в `payment_handler.go`:
`addCardRequest` (тип, :112), `addCardLegacyDisabled` (:1012), `paymentMethodFromRequest` (:1132),
`detectCardBrand` (:1218), `onlyDigits` (:1208), `validLuhn` (:1233); а также
`payment_repository.go:1446 placeholders`. Плюс несколько неиспользуемых в других пакетах.

**ineffassign — 4:** `usecase/payment/finance.go:271-272` (`status`/`paid` вычисляются из payload и
тут же перезаписываются ответом провайдера на :278-279 — **защитная перепроверка, поведенчески
безопасно**), плюс 2 прочих. ⬜ low.

**unparam — 0.**

#### Группа 6 — прочее

**staticcheck — 3, SA1019 (deprecated API):**
`infrastructure/fcm/sender.go:79` `option.WithCredentialsJSON` (объявлен deprecated из-за
потенциального security-риска), `sender.go:204` `messaging.IsRegistrationTokenNotRegistered`
(→ `IsUnregistered()`), `infrastructure/redis/location_store.go:34` `GeoRadius` (→ `GeoSearch`).

**gosimple — 1:** `transport/http/payment_handler.go:973` — избыточный `return` (S1023).

---

#### Новые баги из прогона (B-32…B-40)

Часть находок подтверждает уже известные темы: массовый errcheck/govet-shadow смыкается с
**B-02/B-25** (проглоченные ошибки), `nilerr` — та же геолокация, что и **B-18**, contextcheck
горутин — та же проблема, что **B-21**. Ниже — то, что не описано в реестре B-01…B-31.

| ID | Файл:строка | Описание | Серьёзность | Предлагаемый фикс |
|---|---|---|---|---|
| B-32 | `infrastructure/postgres/payment_repository.go:568` | В `CompleteOrderFinancially` ошибка `Row.Scan` статуса платежа игнорируется (`_ = …Scan(…)`). Реальная ошибка БД неотличима от `ErrNoRows`; для карты fail-closed, для наличных проход дальше без знания состояния платежа. | 🟨 medium | Проверять ошибку Scan; отличать `sql.ErrNoRows` от инфраструктурной ошибки. |
| B-33 | `infrastructure/redis/location_store.go:198`,`:202` | `nilerr`: при `err != nil` функция возвращает `nil` — ошибка Redis в гео/матчинг-пути маскируется, вызывающий считает операцию успешной. | 🟨 medium | Возвращать ошибку (или явно `redis.Nil`→`nil`, прочее — наружу). |
| B-34 | `payment_repository.go` (×17), `usecase/payment/finance.go` (×3), `usecase/order/create_order.go` (×5), `transport/http/payment_handler.go` (×5) | `govet shadow`: 44 затенения `err` во вложенных блоках, преимущественно на денежных путях — внешняя `err` не обновляется, ошибка может потеряться. Дефолтный `go vet` (5.2) их не видит. | 🟨 medium | Не затенять `err` (`=` вместо `:=` / переименовать); включить shadow-vet в CI. |
| B-35 | `transport/http/order_handler.go:316`,`:793`; `usecase/payment/finance.go:293-294`; `transport/http/payment_handler.go:760`,`:1225` | `errcheck` на значимых путях: отброшены результаты запросов заказов и `csv.WriteAll`/`Atoi` в платёжных выгрузках (всего 57 находок errcheck, здесь — денежные/заказные). Расширяет B-02/B-25. | 🟧 high (order_handler) / 🟨 (прочее) | Проверять и логировать/возвращать ошибки; для defer-`Rollback` — паттерн `errcheck`-исключения. |
| B-36 | `transport/http/routing_handler.go:69`,`:122`; `pricing_handler.go:169`; `postgres/driver_verification_repository.go:37` | `errorlint`: сравнение ошибок через `==`/`!=` ломается на обёрнутых ошибках; плюс не-оборачивающий `fmt.Errorf` в `container.go`/`yookassa_client.go`/domain-errors (нужен `%w`). | 🟨 medium | `errors.Is/As`; оборачивать через `%w`. |
| B-37 | `transport/http/payment_handler.go:112,1012,1132,1208,1218,1233`; `payment_repository.go:1446` | `unused`: мёртвый легаси-код привязки карт (`addCardRequest`, `addCardLegacyDisabled`, `paymentMethodFromRequest`, `detectCardBrand`, `onlyDigits`, `validLuhn`) и `placeholders`. Бэкенд-аналог фронтового B-24. | ⬜ low | Удалить мёртвый код (либо включить, если планировался). |
| B-38 | `infrastructure/fcm/sender.go:79`,`:204`; `infrastructure/redis/location_store.go:34` | `staticcheck SA1019`: deprecated API — `WithCredentialsJSON` (помечен deprecated из-за security-риска), `IsRegistrationTokenNotRegistered`, `GeoRadius`. | ⬜ low | Мигрировать на `IsUnregistered()`, `GeoSearch(BYRADIUS)`, безопасную загрузку credentials. |
| B-39 | `infrastructure/websocket/order_event_relay.go:38`; `usecase/order/create_order.go:125` | `contextcheck`: отсоединённые горутины не пробрасывают `context.Context` (нет отмены/таймаутов/трейсинга). Смыкается с B-21. | 🟨 medium | Пробрасывать `context.Context` в горутины; `context.WithoutCancel` при необходимости. |
| B-40 | `payment_repository.go`, `payment_handler.go`, `usecase/payment/finance.go`, `order_repository.go`, `create_order.go` | `gocritic`: 25 `hugeParam` (тяжёлые структуры до 176 байт по значению) + 12 `rangeValCopy` (160–208 байт/итерацию) — лишние копии на горячих денежных путях. | ⬜ low (perf) | Передавать по указателю / индексировать в цикле. |

> **Отдельно (не баг):** gosec G201/G202 (14) проверены вручную — все ложноположительные
> (параметризованный динамический `WHERE`). Рекомендация: добавить комментарии `//nosec G201`/`G202`
> с обоснованием, чтобы прогон был «зелёным» и не маскировал будущие реальные конкатенации.
> **ineffassign** `finance.go:271-272` — защитная перепроверка, поведение корректно, фикс необязателен.

---

## 6. Готовность к продакшену

| Пункт | Статус | Комментарий |
|---|---|---|
| Структурированное логирование, уровни | 🔴 | stdlib `log`, без JSON/уровней (B-23). |
| Метрики / observability | 🔴 | Не найдено (B-15). |
| Error-tracking (Sentry) | 🔴 | Не найдено (B-15). |
| Обработка паник | 🟡 | chi `Recoverer` на HTTP есть; в горутинах `recover()` нет (B-21). |
| Graceful shutdown | ✅ | `signal.NotifyContext` + `srv.Shutdown` 10s (`main.go:47,70-75`); горутины не `Wait`аются. |
| Конфиг через env, без секретов в коде | ✅ | `validateProductionConfig` фаталит на dev-секретах/bypass (`config.go:141-173`). Засвеченные ключи только в `branch-audit/*.diff` (B-29). |
| Миграции БД (goose) | 🟡 | Гоняются на старте, но дубль-схема + возможный дрейф трекера (B-08). |
| Health-check | 🟡 | `/healthz` поверхностный (B-22). |
| Документация API (Swagger) | 🟡 | Есть, отключён в проде; устарел (B-26). |
| CORS / rate-limit / auth middleware | 🟡 | CORS с allow-list (localhost только в debug, безопасно); rate-limit узкий и per-instance (B-14); auth-middleware корректен. |
| CI/CD | 🔴 | Отсутствует (B-15). |

---

## 7. Приоритизированный backlog

Оценка сложности: **S** ≈ до полудня · **M** ≈ 1–2 дня · **L** ≈ неделя+.

### Блокеры (сделать до запуска)
1. **B-01** Проверка подписи YooKassa webhook + не доверять XFF — **S/M**.
2. **B-02 + B-03** Идемпотентность вебхука на ретрае + одна транзакция на side-effects — **M**.
3. **B-06** Транзакция на приём заказа (accept+assign+surcharge) — **M**.
4. **B-05** Межгородская наценка для карты (или запрет карты для cross-city) — **S**.
5. **B-09** Реальное применение промокода к цене — **M**.
6. **B-10** Реальный заработок водителя из кошелька/транзакций — **M**.
7. **B-11** Idempotency-Key / отказ от ретрая неидемпотентных POST — **S**.
8. **B-15** CI (build+vet+test+analyze) + Sentry + базовые метрики — **M**.

### Важное (во время стабилизации)
- **B-04** Конфигурируемая комиссия — **S**.
- **B-16** Согласовать ключи цен подписок — **S**.
- **B-12** Refresh/ретрай на web-клиенте — **S**.
- **B-13** Убрать логирование секретов — **S**.
- **B-14** Rate-limit на критичных ручках (Redis) — **S**.
- **B-08** Единый источник схемы (goose), сверка трекера в проде — **L**.
- **B-07** Масштабируемость WS (Redis fan-out) — **L**.
- **B-18** Pipeline + freshness в матчинге — **M**.
- **B-21** `recover()` в горутинах — **S**.
- **B-22** `/readyz` с проверкой БД+Redis — **S**.
- **B-23** Структурированное логирование — **M**.

### Nice-to-have
- **B-17** переходы через state machine; **B-19** FK-констрейнты; **B-20** конфиг пула Redis;
  **B-24** убрать excludes анализатора; **B-25** FCM broadcast-cleanup; **B-26** актуализировать Swagger;
  **B-27/B-28** WS Origin/reconnect, устранить дублирующий realtime-стек; **B-29/B-30** очистка репозитория
  и ротация засвеченных ключей, объявление env в render.yaml; road-distance вместо Haversine в прайсинге;
  повысить покрытие тестами (postgres-репозитории, matching, webhook).
