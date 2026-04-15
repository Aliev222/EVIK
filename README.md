# EVIK - Uber-like Tow Truck Architecture

Production-ready baseline for a Flutter + Go system using Clean Architecture and modular monolith backend.

## 1) Folder Structure

```text
.
├── backend
│   ├── cmd
│   │   └── app
│   │       └── main.go
│   ├── go.mod
│   └── internal
│       ├── app
│       │   └── container.go
│       ├── config
│       │   └── config.go
│       ├── domain
│       │   ├── driver
│       │   │   ├── entity.go
│       │   │   └── repository.go
│       │   ├── order
│       │   │   ├── entity.go
│       │   │   ├── errors.go
│       │   │   ├── repository.go
│       │   │   └── state_machine.go
│       │   └── user
│       │       ├── entity.go
│       │       └── repository.go
│       ├── infrastructure
│       │   ├── postgres
│       │   │   ├── driver_repository.go
│       │   │   └── order_repository.go
│       │   ├── redis
│       │   │   ├── location_store.go
│       │   │   └── pubsub.go
│       │   └── websocket
│       │       └── hub.go
│       ├── transport
│       │   ├── http
│       │   │   ├── order_handler.go
│       │   │   └── router.go
│       │   └── ws
│       │       └── order_ws_handler.go
│       └── usecase
│           ├── matching
│           │   └── find_driver.go
│           └── order
│               ├── cancel_order.go
│               ├── create_order.go
│               └── update_status.go
├── docker-compose.yml
└── frontend
    ├── lib
    │   ├── core
    │   │   ├── config
    │   │   │   └── app_config.dart
    │   │   ├── network
    │   │   │   └── api_client.dart
    │   │   ├── storage
    │   │   │   └── key_value_storage.dart
    │   │   ├── theme
    │   │   │   └── app_theme.dart
    │   │   └── widgets
    │   │       └── app_scaffold.dart
    │   ├── features
    │   │   ├── auth
    │   │   │   ├── data
    │   │   │   ├── domain
    │   │   │   │   └── README.md
    │   │   │   └── presentation
    │   │   ├── driver
    │   │   │   ├── data
    │   │   │   ├── domain
    │   │   │   │   └── README.md
    │   │   │   └── presentation
    │   │   ├── map
    │   │   │   ├── data
    │   │   │   ├── domain
    │   │   │   │   └── README.md
    │   │   │   └── presentation
    │   │   ├── order
    │   │   │   ├── data
    │   │   │   │   ├── datasource
    │   │   │   │   │   └── order_remote_datasource.dart
    │   │   │   │   ├── dto
    │   │   │   │   │   └── order_dto.dart
    │   │   │   │   └── repository_impl
    │   │   │   │       └── order_repository_impl.dart
    │   │   │   ├── domain
    │   │   │   │   ├── entities
    │   │   │   │   │   └── order.dart
    │   │   │   │   ├── repositories
    │   │   │   │   │   └── order_repository.dart
    │   │   │   │   └── usecases
    │   │   │   │       └── create_order_usecase.dart
    │   │   │   └── presentation
    │   │   │       ├── screens
    │   │   │       │   └── order_screen.dart
    │   │   │       ├── state
    │   │   │       │   └── order_state_notifier.dart
    │   │   │       └── widgets
    │   │   │           └── order_state_views.dart
    │   │   └── profile
    │   │       ├── data
    │   │       ├── domain
    │   │       │   └── README.md
    │   │       └── presentation
    │   └── main.dart
    └── pubspec.yaml
```

## 2) Clean Architecture Rules Applied

- domain: entities, state machine, repository contracts.
- usecase: business workflows only.
- infrastructure/data: repository and pub/sub implementations.
- transport: thin HTTP/WS adapters with no business logic.

Dependency direction: only inward (Dependency Inversion).

## 3) Order State Machine

Implemented in `backend/internal/domain/order/state_machine.go`.

- `created -> searching -> accepted -> arrived -> in_progress -> completed`
- `created/searching/accepted/arrived/in_progress -> cancelled`
- invalid transitions return `ErrInvalidTransition`

State updates are done through use cases only.

## 4) Realtime

- WebSocket endpoint: `/ws/orders`
- Redis Pub/Sub channel: `orders:status`
- Forwarder: Redis events -> WS Hub -> clients

## 5) Geolocation

- Redis GEO for live driver coordinates (`location_store.go`).
- PostgreSQL for durable order history (`order_repository.go`).

## 6) Matching (Simplified)

`backend/internal/usecase/matching/find_driver.go`:

- search nearest available drivers
- increase radius each N seconds
- stop on context cancellation

## 7) Frontend State Management (Riverpod)

- Single source of truth: `OrderUiState.status`
- enum exactly as required:
  - `idle, searching, accepted, arrived, inProgress, completed, cancelled`
- state-driven UI via `switch` in `OrderScreen`

## 8) Run Infra

```bash
docker compose up -d
```

## 9) Production Hardening (Next)

1. Add migrations and indexes (orders, driver availability, optional PostGIS).
2. Add auth + role-aware WS channels.
3. Add outbox pattern for guaranteed event delivery.
4. Add integration tests for forbidden transitions and WS fanout.
5. Split matching/realtime into microservices using existing interfaces.
