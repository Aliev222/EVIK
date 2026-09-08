# План разбора незакоммиченного рабочего дерева

Дата: 2026-09-06

Обновлено: 2026-09-08 — владелец подтвердил:

- `graphify-out` удаляем и не возвращаем;
- `frontend/test/failures` не коммитим;
- `logs/**` не коммитим;
- macOS `Package.resolved` не коммитим.

Цель: навести порядок перед дальнейшей доводкой Avro/EVIK к продакшену, не потеряв полезные изменения и не закоммитив мусор.

## Что сейчас происходит

Рабочее дерево сильно загрязнено не потому, что вся логика плохая, а потому что в одном месте лежат сразу несколько разных пластов работы:

- реальные продуктовые изменения;
- UI/UX правки и режим UI-аудита;
- серверные изменения по смене маршрута заказа;
- платежи/выплаты;
- геокодинг и работа с картой;
- фоновые сервисы водителя;
- админка;
- платформенные настройки iOS/Android/macOS;
- сгенерированные/временные файлы (`graphify-out`, `logs`, failure screenshots).

Самый большой шум: `graphify-out/**` — 675 удалённых файлов и примерно 1.8 млн удалённых строк. Это искажает ощущение риска: Git показывает “катастрофу”, хотя это в основном артефакты старого графа.

## Коробки изменений

### 1. Мусор / артефакты, вероятно не коммитить

Кандидаты:

- `graphify-out/**`
- `logs/**`
- `frontend/test/failures/*.png`
- `frontend/test/failures/.DS_Store`

Рекомендация:

- удалить `graphify-out` из контроля Git, если мы окончательно переходим на GitNexus;
- добавить игнор всего `graphify-out/`, а не только `graphify-out/cache/`;
- не коммитить failure screenshots, они нужны только для локальной диагностики;
- логи не коммитить.

Статус:

- `.gitignore` усилен;
- untracked failure screenshots удалены;
- macOS `Package.resolved` удалены;
- tracked `graphify-out/**` и `logs/**` остаются как удаления в рабочем дереве, их нужно будет зафиксировать отдельным cleanup-коммитом.

Нужен ответ владельца:

- больше не нужен — подтверждено.

### 2. Смена адреса/маршрута активного заказа

Файлы:

- `backend/internal/usecase/order/change_route.go`
- `backend/internal/infrastructure/postgres/order_route_repository.go`
- `backend/internal/transport/http/order_route_handler.go`
- `backend/internal/app/container.go`
- `backend/internal/transport/http/router.go`
- `backend/internal/transport/ws/order_ws_handler.go`
- `backend/migrations/20260905_order_route_changes.sql`
- `frontend/lib/features/client/presentation/screens/edit_order_route_screen.dart`
- `frontend/lib/features/client/presentation/screens/driver_search_screen.dart`
- `frontend/lib/features/client/presentation/screens/driver_info_screen.dart`
- `frontend/lib/features/client/presentation/providers/order_flow_provider.dart`
- `frontend/lib/features/order/data/repository_impl/http_order_repository.dart`
- realtime/order-event файлы.

Смысл:

- до погрузки клиент может менять точку А и точку Б;
- после погрузки клиент меняет только точку Б;
- назад с точки Б до погрузки возвращает на точку А;
- назад с точки Б после погрузки возвращает на экран текущего заказа;
- цена после погрузки считается как “уже пройденный путь + оставшийся путь до новой Б”.

Статус:

- frontend route-editor tests прошли;
- backend unit tests прошли;
- backend PostgreSQL integration tests проходили на временной базе.

Риски:

- нужно отдельно проверить миграцию на реальной базе;
- нужно позже глубже проверить гонки с оплатой;
- city/cross-city логика пока упрощена.

### 3. UI-аудит / dev-режим без логина

Файлы:

- `frontend/lib/core/config/build_flags.dart`
- `frontend/lib/features/development/**`
- `frontend/lib/main.dart`
- `frontend/test/build_flags_test.dart`
- `frontend/test/visual_audit_capture_test.dart`
- `frontend/test/goldens/audit_*.png`

Смысл:

- можно гулять по экранам без регистрации и backend;
- тестовые данные должны быть явно помечены как демонстрационные;
- production-сборка не должна случайно включить тестовый режим.

Нужно проверить:

- что `EVIK_UI_AUDIT` невозможно случайно включить в релизе;
- что все mock-данные подписаны как тестовые;
- что режим помогает снимать все экраны, а не ломает реальную навигацию.

### 4. Клиентский UI/UX

Файлы:

- `frontend/lib/features/client/presentation/screens/client_home_screen.dart`
- `frontend/lib/features/client/presentation/screens/vehicle_selection_screen.dart`
- `frontend/lib/features/client/presentation/widgets/client_bottom_nav.dart`
- `frontend/lib/features/client/presentation/widgets/services_placeholder_screen.dart`
- `frontend/lib/features/onboarding/presentation/screens/role_selection_screen.dart`

Смысл:

- правки главного экрана клиента;
- карточки услуг;
- нижняя навигация;
- onboarding/выбор роли;
- подготовка будущего блока услуг/партнёров.

Нужно проверить глазами на симуляторе:

- все состояния клиента: главная, выбор услуги, выбор А, выбор Б, поиск водителя, водитель найден, водитель едет, погрузка/в пути, завершение;
- все критические размеры iPhone: маленький экран, обычный Pro, большой Max;
- переполнение русского текста;
- единый стиль карточек, отступов, скруглений, кнопок.

### 5. Геокодинг и карта

Файлы:

- `backend/internal/transport/http/geocoding_handler.go`
- `backend/internal/transport/http/geocoding_handler_test.go`
- `frontend/lib/core/services/map_api.dart`
- `frontend/lib/core/services/openstreetmap_service.dart`
- `frontend/test/map_api_test.dart`

Смысл:

- увести поиск/геокодинг через backend-прокси;
- не светить и не размазывать внешние map-запросы по клиенту;
- централизовать ошибки и лимиты.

Нужно проверить:

- поиск адресов в Махачкале/Каспийске;
- плохие запросы;
- отсутствие интернета;
- скорость;
- лимиты внешнего сервиса.

### 6. Водитель: фон, геолокация, realtime, звуки

Файлы:

- `frontend/lib/features/driver/data/services/driver_location_service.dart`
- `frontend/lib/features/driver/data/services/driver_notification_service.dart`
- `frontend/lib/features/driver/data/services/driver_shift_tracker.dart`
- `frontend/lib/features/driver/data/services/driver_wake_service.dart`
- `frontend/lib/features/driver/presentation/providers/driver_realtime_provider.dart`
- `frontend/lib/features/driver/presentation/providers/driver_status_provider.dart`
- `frontend/lib/features/driver/presentation/providers/new_driver_provider.dart`
- `frontend/assets/audio/*.mp3`
- `frontend/pubspec.yaml`
- tests around driver location/wake/shift.

Смысл:

- водитель должен получать заказ и не “засыпать”;
- геолокация должна отправляться корректно;
- звуки нужны приложению и их не удаляем.

Нужно проверить:

- iOS background location;
- Android permissions;
- звук при новом заказе;
- поведение при потере сети;
- частоту отправки координат, чтобы не убивать батарею.

### 7. Платежи и выплаты

Файлы:

- `backend/internal/domain/payment/repository.go`
- `backend/internal/infrastructure/postgres/payment_repository.go`
- `backend/internal/infrastructure/http/yookassa_client.go`
- `backend/internal/usecase/payment/**`
- `backend/docs/payment-flow.md`

Смысл:

- автоматические выплаты;
- webhook-проверки;
- защита от повторной/фальшивой обработки.

Нужно проверить отдельно:

- наличные;
- карта;
- отмена;
- возврат;
- повторный webhook;
- payout processing/paid/failed;
- что нельзя вывести деньги по чужому заказу.

### 8. Security/config

Файлы:

- `backend/.env.example`
- `backend/internal/config/config.go`
- `backend/internal/config/config_production_test.go`
- `backend/internal/transport/http/auth_handler.go`
- `backend/internal/transport/http/rate_limiter.go`
- `backend/internal/transport/http/trusted_proxy.go`
- `backend/internal/transport/http/trusted_proxy_test.go`
- auth security tests.

Смысл:

- production-конфиг;
- rate limit;
- trusted proxy;
- безопасность OTP/auth.

Нужно проверить:

- реальные env на российском сервере;
- TLS/proxy headers;
- CORS;
- rate limits;
- хранение секретов;
- логирование без токенов и персональных данных.

### 9. Админка

Файлы:

- `admin-web/static/app.js`
- `admin-web/static/styles.css`
- `admin-web/tests/audit.test.mjs`
- `admin-web/tests/harness.mjs`
- `frontend/lib/features/admin/presentation/screens/admin_dashboard_screen.dart`

Смысл:

- сейчас админка — отдельный проблемный слой;
- её нельзя “случайно” склеить с маршрутом/платежами;
- нужен отдельный аудит сценариев владельца.

Рекомендация:

- сначала описать, что владелец должен видеть и менять;
- потом убрать лишние модули;
- затем привести UI в единый стиль;
- затем добавить тесты на ключевые действия.

### 10. Платформенные настройки

Файлы:

- `frontend/android/**`
- `frontend/ios/Runner/**`
- `frontend/macos/**`
- `frontend/android/key.properties.example`
- `frontend/macos/**/Package.resolved`

Смысл:

- permissions;
- background modes;
- signing/example configs;
- Swift Package Manager state.

Нужно проверить:

- что это нужно именно для мобильных релизов;
- что macOS-файлы не мусор от локального запуска;
- что signing-файлы безопасны.

## Порядок разбора

1. Сначала отделить мусор:
   - `graphify-out`;
   - `logs`;
   - screenshots from `frontend/test/failures`;
   - `.DS_Store`.

2. Затем зафиксировать полезные фичи отдельными пакетами:
   - смена маршрута заказа;
   - UI-аудит/dev режим;
   - геокодинг/map proxy;
   - фоновые сервисы водителя;
   - платежи/выплаты;
   - security/config;
   - UI/UX клиентских экранов;
   - админка.

3. Для каждого пакета:
   - проверить diff;
   - прогнать релевантные тесты;
   - сделать GitNexus impact/detect-changes там, где меняются runtime-символы;
   - решить: commit / доработать / откатить / удалить.

4. Только после этого возвращаться к большим задачам:
   - полный UI/UX аудит всех экранов;
   - админка владельца;
   - production backend/security;
   - релизная подготовка.

## Вопросы владельцу перед удалением

1. `graphify-out` удаляем окончательно из репозитория и переходим на GitNexus как основной инструмент анализа? — да.
2. Локальные screenshots в `frontend/test/failures` можно не коммитить и убрать из рабочего дерева? — да.
3. `logs/**` можно окончательно оставить удалёнными? — да.
4. macOS `Package.resolved` — это нужно коммитить для твоего проекта или это случайный след запуска на Mac? — не коммитить.
