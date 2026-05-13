# Tow Truck Admin Panel

Чистая пересборка admin-web панели с нуля. Vanilla HTML/CSS/JS + Go proxy server.

## Быстрый старт

```bash
cd admin-web
go build .
./admin-web.exe   # Windows

# Или напрямую:
go run main.go
```

Открыть: http://localhost:5174

## Переменные окружения

| Переменная         | По умолчанию         | Описание                    |
|--------------------|----------------------|-----------------------------|
| `ADMIN_WEB_ADDR`   | `:5174`              | Адрес для web server        |
| `ADMIN_API_BASE_URL` | `http://localhost:8080` | Backend API для проксирования `/api/v1/*` |

## Архитектура

- **main.go**: Go HTTP server
  - Статика: `//go:embed static/*` → FileServer
  - Proxy: `/api/v1/*` → backend с сохранением `Authorization` header
  - SPA fallback: неизвестные пути → `index.html`
- **static/index.html**: Single page shell
- **static/styles.css**: Design tokens + компоненты
- **static/app.js**: Вся логика (state, API client, router, 17 страниц)

## Функционал

### ✅ Реализованные разделы (используют реальные backend endpoints)

1. **Dashboard** (`/api/v1/admin/overview`) — KPI карточки + простые bar charts
2. **Orders** (`/api/v1/admin/orders` + фильтры) — список заказов + detail drawer
3. **Drivers** (`/api/v1/admin/users` filtered by role) — базовый список водителей
4. **Documents/Moderation** (`/api/v1/admin/driver-verifications` + approve/reject/block) — полная модерация заявок
5. **Reviews** (`/api/v1/admin/reviews`) — read-only список отзывов
6. **Users** (`/api/v1/admin/users`) — список пользователей с фильтрами
7. **Online Map** (`/api/v1/admin/drivers-online`) — таблица координат (карты нет)
8. **Refunds** (`/api/v1/admin/finance/refunds` + create) — список возвратов + создание новых
9. **Reports/Export** (`POST /api/v1/admin/finance/export?type=...`) — CSV экспорт
10. **Payouts** (список через `/admin/finance/payouts` report + approve/reject actions)

### ⚠️ Частично реализованные (CSV report mode)

11. **Payments** — через `/api/v1/admin/finance/payments` (report format)
12. **Wallets** — через `/api/v1/admin/finance/wallets` (report format)  
13. **Transactions** — через `/api/v1/admin/finance/transactions` (report format)
14. **Subscriptions** — через `/api/v1/admin/finance/subscriptions` (report format)

Эти разделы показывают данные как таблицы из CSV-rows (`{rows: [[]]}` format), поскольку dedicated list endpoints не существуют.

### 🚫 Backend endpoint отсутствует (показывают placeholder)

15. **Tax Profiles** — `/api/v1/admin/tax-profiles` endpoint не реализован
16. **Service Areas CRUD** — только `/api/v1/service-areas/check` работает (point checker), CRUD операции отсутствуют
17. **Settings** — admin settings endpoints не существуют

### 🔐 Авторизация

- Login: `POST /api/v1/auth/admin/login` (username/password → JWT)
- Token в `localStorage` как `admin_token`
- Автологаут при 401

## Проверка backend endpoints

Все endpoints проверены на существование в `backend/internal/transport/http/router.go`. Отсутствующие endpoint'ы намеренно показывают "Backend endpoint отсутствует" вместо fake данных.

## Безопасность

- **Никаких `X-Evik-Api-Base-Url` header overrides** (удалены по требованию спецификации)
- Backend URL задается только через `ADMIN_API_BASE_URL` env var
- JWT токены не логируются
- Все user input экранируется через `escapeHtml()`

## Сборка для продакшна

```bash
go build -ldflags="-s -w" .
```

Бинарь содержит встроенную статику (`//go:embed`), дополнительные файлы не нужны.

## Возможные улучшения

1. Добавить backend endpoints для tax profiles, service areas CRUD, settings
2. Dedicated endpoints для finance lists вместо CSV-report режима  
3. Интеграция карт-провайдера для Online Map
4. Batch operations для moderation
5. Real-time обновления через WebSocket