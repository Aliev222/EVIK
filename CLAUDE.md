# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EVIK is a cross-platform Flutter tow truck application ("Uber for tow trucks") targeting iOS, Android, and Web platforms. The project consists of a production-ready Flutter frontend with custom Go backend integration.

## 🗺️ PROJECT MAP - START HERE FOR ANY TASK

**ALWAYS check this map first to navigate directly to the right files instead of searching.**

### 📁 **Root Structure**
```
EVIK/
├── backend/           # Go API server (Production ready)
├── frontend/          # Flutter mobile/web app (Production ready) 
├── render.yaml        # Render.com deployment config
├── docker-compose.yml # Local development setup
├── CLAUDE.md          # This file - project documentation
└── .gitignore         # Git ignore rules
```

### 🎯 **QUICK FILE FINDER - Common Tasks**

| **Task** | **Go To** |
|----------|-----------|
| 🚀 **App Entry Point** | `frontend/lib/main.dart` |
| 🔧 **API Server Main** | `backend/cmd/app/main.go` |
| 🎨 **UI Theme/Colors** | `frontend/lib/core/theme/` |
| 🔐 **Authentication** | `frontend/lib/features/auth/` + `backend/internal/auth/` |
| 📱 **Client Screens** | `frontend/lib/features/client/presentation/screens/` |
| 🚛 **Driver Screens** | `frontend/lib/features/driver/presentation/screens/` |
| 📦 **Orders Logic** | `frontend/lib/features/order/` + `backend/internal/domain/order/` |
| 🗺️ **Maps Integration** | `frontend/lib/features/map/` |
| 🌐 **API Client** | `frontend/lib/core/network/api_client_io.dart` |
| 🔌 **WebSocket** | `frontend/lib/core/realtime/websocket_client_io.dart` |
| 🧪 **Mock/Test Mode** | `frontend/lib/core/network/api_client_stub.dart` + `MOCK_MODE.md` |
| 🏗️ **Database** | `backend/internal/infrastructure/postgres/` |
| 🔥 **Build Config** | `frontend/android/app/build.gradle.kts` |
| 📋 **Dependencies** | `frontend/pubspec.yaml` + `backend/go.mod` |

### 🏗️ **Backend Architecture Map (Go)**
```
backend/
├── cmd/app/main.go                    # 🚀 Entry point
├── internal/
│   ├── config/config.go              # ⚙️ Configuration
│   ├── app/container.go              # 🏭 Dependency injection
│   ├── auth/tokens.go                # 🔐 JWT authentication
│   ├── domain/                       # 🧠 Business logic
│   │   ├── order/                    # 📦 Order entities & logic
│   │   ├── driver/                   # 🚛 Driver entities & logic
│   │   ├── user/                     # 👤 User entities
│   │   └── location/                 # 📍 Location entities
│   ├── usecase/                      # 🎯 Application services
│   │   ├── order/                    # 📦 Order operations
│   │   ├── driver/                   # 🚛 Driver operations
│   │   └── matching/                 # 🎯 Driver-order matching
│   ├── infrastructure/               # 🔧 External integrations
│   │   ├── postgres/                 # 🗄️ Database repositories
│   │   ├── redis/                    # ⚡ Cache & pub/sub
│   │   └── websocket/                # 🔌 Real-time communication
│   └── transport/                    # 🌐 API endpoints
│       ├── http/                     # 🌐 REST API handlers
│       └── ws/                       # 🔌 WebSocket handlers
├── go.mod                            # 📦 Dependencies
└── Dockerfile                        # 🐳 Container config
```

### 📱 **Frontend Architecture Map (Flutter)**
```
frontend/lib/
├── main.dart                         # 🚀 App entry point
├── core/                             # 🏗️ Shared infrastructure
│   ├── bootstrap/app_bootstrap.dart  # ⚙️ App initialization
│   ├── error/global_error_handler.dart # 🚨 Error handling
│   ├── network/                      # 🌐 HTTP client & API
│   │   ├── api_client_io.dart       # 🌐 Production HTTP client
│   │   └── api_client_stub.dart     # 🧪 Mock for testing
│   ├── realtime/                     # 🔌 WebSocket integration
│   │   ├── websocket_client_io.dart # 🔌 Production WS client
│   │   └── event_dispatcher.dart    # 📡 Real-time events
│   ├── theme/                        # 🎨 Design system
│   │   ├── app_theme.dart           # 🎨 Main theme
│   │   ├── evik_colors.dart         # 🌈 Color palette
│   │   └── evik_typography.dart     # 📝 Text styles
│   ├── constants/app_constants.dart  # 📋 App-wide constants
│   └── services/                     # 🛠️ Core services
│       ├── location_service.dart    # 📍 GPS & location
│       └── price_calculator.dart    # 💰 Pricing logic
├── features/                         # 🎯 Feature modules
│   ├── auth/                         # 🔐 Authentication
│   │   ├── domain/entities/user.dart # 👤 User model
│   │   ├── presentation/
│   │   │   ├── auth_screen.dart     # 🔐 Phone login
│   │   │   ├── screens/sms_verification_screen.dart # 📱 SMS verify
│   │   │   └── providers/auth_provider.dart # 🔐 Auth state
│   ├── onboarding/                   # 👋 App introduction
│   │   └── presentation/screens/role_selection_screen.dart # 🚛👤 Role choice
│   ├── client/                       # 👤 Client interface
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── client_app_shell.dart     # 🏠 Main shell
│   │   │   │   ├── client_home_screen.dart   # 🏠 Home with map
│   │   │   │   ├── client_history_screen.dart # 📜 Order history
│   │   │   │   ├── client_profile_screen.dart # 👤 Profile settings
│   │   │   │   └── client_wallet_screen.dart # 💰 Payment methods
│   │   │   ├── widgets/              # 🧩 Client UI components
│   │   │   └── providers/            # 🔄 Client state management
│   │   └── data/services/pricing_service.dart # 💰 Price calculations
│   ├── driver/                       # 🚛 Driver interface
│   │   ├── domain/entities/          # 📦 Driver models
│   │   │   ├── driver.dart          # 🚛 Driver entity
│   │   │   ├── driver_earnings.dart # 💰 Earnings tracking
│   │   │   ├── active_order.dart    # 📦 Active order
│   │   │   └── available_order.dart # 📋 Available orders
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── driver_screen.dart        # 🚛 Main driver hub
│   │   │   │   ├── new_driver_home_screen.dart # 🏠 Driver home
│   │   │   │   ├── driver_documents_screen.dart # 📄 Document upload
│   │   │   │   ├── driver_moderation_screen.dart # ⏳ Approval status
│   │   │   │   ├── active_order_screen.dart  # 📦 Current order
│   │   │   │   ├── driver_profile_screen.dart # 👤 Driver profile
│   │   │   │   └── driver_earnings_screen.dart # 💰 Earnings view
│   │   │   ├── widgets/              # 🧩 Driver UI components
│   │   │   └── providers/            # 🔄 Driver state management
│   │   └── data/                     # 🗄️ Driver data layer
│   ├── order/                        # 📦 Order management
│   │   ├── domain/entities/order.dart # 📦 Order model
│   │   ├── data/repository_impl/http_order_repository.dart # 🌐 API calls
│   │   └── presentation/providers/order_provider.dart # 🔄 Order state
│   └── map/                          # 🗺️ Maps integration
│       ├── presentation/widgets/promaps_view_simple.dart # 🗺️ flutter_map (OSM)
│       └── domain/entities/map_location.dart # 📍 Location model
├── shared/                           # 🤝 Shared components
│   ├── widgets/                      # 🧩 Reusable UI components
│   │   ├── evik_button.dart         # 🔘 Custom buttons
│   │   ├── evik_map_cta.dart        # 🗺️ Map call-to-action
│   │   └── loading_state.dart       # ⏳ Loading indicators
│   └── models/tariff_model.dart      # 💰 Pricing models
└── pubspec.yaml                      # 📦 Flutter dependencies
```

### 🔗 **Key Integrations**

| **Component** | **Location** | **Purpose** |
|---------------|--------------|-------------|
| **flutter_map (OSM)** | `frontend/lib/features/map/` | Map display via flutter_map ^8.3.0 (OpenStreetMap tiles), geocoding & routing |
| **JWT Auth** | `backend/internal/auth/` + `frontend/lib/features/auth/` | User authentication |
| **PostgreSQL** | `backend/internal/infrastructure/postgres/` | Primary database |
| **Redis** | `backend/internal/infrastructure/redis/` | Caching & pub/sub |
| **WebSocket** | `backend/internal/infrastructure/websocket/` + `frontend/lib/core/realtime/` | Real-time updates |
| **HTTP API** | `backend/internal/transport/http/` + `frontend/lib/core/network/` | REST communication |

### 🎯 **State Management (Riverpod)**
- **Providers**: `frontend/lib/features/*/presentation/providers/`
- **Auth State**: `frontend/lib/features/auth/presentation/providers/auth_provider.dart`
- **Order State**: `frontend/lib/features/order/presentation/providers/order_provider.dart`
- **Driver State**: `frontend/lib/features/driver/presentation/providers/driver_provider.dart`
- **Client State**: `frontend/lib/features/client/presentation/providers/client_order_provider.dart`

### 🚀 **Production URLs & Config**
- **API Base**: `tow-truck.onrender.com` (defined in `frontend/lib/core/network/api_client.dart`)
- **WebSocket**: `wss://tow-truck.onrender.com/ws/orders`
- **Environment**: Set via `EVIK_API_BASE_URL` and `EVIK_WS_URL`
- **Deploy Config**: `render.yaml`

## Architecture Status

**Active Architecture: Flutter + Custom Go Backend**
- Frontend: Flutter with Riverpod state management  
- Backend: Go server with PostgreSQL + Redis
- Maps: flutter_map ^8.3.0 (OpenStreetMap-based, not Google Maps), geocoding, and routing
- Authentication: JWT-based phone authentication
- Real-time: WebSocket communication
- Deployment: Render.com hosting

## Key Flutter Commands

```bash
# Working directory: frontend/

# Development
flutter run -d chrome --web-port 3000
flutter run -d windows
flutter run --debug

# Analysis and Testing
flutter analyze --fatal-infos
flutter test
flutter test test/architecture_smoke_test.dart
flutter test --name="smoke"

# Build
flutter build web --release
flutter build apk --release  
flutter build appbundle --release

# Dependencies
flutter pub get
flutter pub upgrade
flutter pub deps
```

## Backend Commands

```bash
# Working directory: backend/

# Development
go run cmd/app/main.go

# Testing
go test ./...
go test -v ./internal/usecase/...

# Build
go build -o app cmd/app/main.go

# Docker
docker-compose up -d  # Start PostgreSQL + Redis
```

## Code Architecture

### Clean Architecture Pattern

Both frontend and backend follow Clean Architecture:

**Frontend (Flutter):**
```
lib/
├── core/                    # Shared infrastructure
│   ├── network/            # HTTP/WebSocket clients
│   ├── services/           # Location, pricing services
│   └── theme/             # Design system
├── features/              # Feature-based modules
│   ├── auth/              # Authentication
│   ├── client/            # Client interface  
│   ├── driver/            # Driver interface
│   └── order/             # Order management
└── shared/               # Cross-feature components
```

**Backend (Go):**
```
internal/
├── domain/                # Business entities & logic
├── usecase/              # Application services  
├── infrastructure/       # External integrations
└── transport/            # API endpoints
```

### State Management - Riverpod Patterns

**Provider Types:**
- `Provider`: Pure dependencies (services, repositories)
- `StateNotifierProvider`: Mutable state with business logic
- `StreamProvider`: WebSocket real-time data
- `FutureProvider`: Async operations

### Database Schema

**PostgreSQL Tables:**
- `users` - User profiles and authentication
- `drivers` - Driver details and status
- `orders` - Order lifecycle and tracking
- `locations` - Real-time location updates

**Redis Usage:**
- Session storage
- Real-time pub/sub for order updates
- Location caching

### User Flows

**Client Flow:**
1. Role Selection → Phone Auth → SMS Verification
2. Client Home Screen with flutter_map (OpenStreetMap) map
3. Order Creation: pickup/dropoff selection, vehicle type, pricing
4. Real-time order tracking (searching → assigned → arriving → evacuating → completed)

**Driver Flow:**  
1. Role Selection → Phone Auth → SMS Verification
2. Driver Onboarding: document upload (passport, license, vehicle docs, selfie)
3. Moderation: real-time status tracking (pending → approved/rejected)
4. Driver Home Screen: online toggle, available orders, active order management

## Testing Strategy

**Test Files:**
- `frontend/test/architecture_smoke_test.dart`: Widget integration tests
- `frontend/test/ui_audit_screens_test.dart`: UI validation across screens
- `backend/internal/usecase/*/test.go`: Business logic unit tests

**Test Patterns:**
- Provider overrides for HTTP-dependent widgets
- Mock repositories to avoid real API calls
- Widget pump-and-settle for async UI updates

## Maps Integration

**flutter_map Setup:**
- Library: `flutter_map: ^8.3.0` (OpenStreetMap-based, not Google Maps) + `flutter_map_animations: ^0.10.0`
- No proprietary API key required for base OSM tiles
- Custom wrapper: `ProMapsViewSimple` (legacy file name) with EVIK-specific markers
- Features: location tracking, address search, route metadata, custom markers
- Android integration: pure Flutter plugin stack, no native map platform view

## Development Workflow Considerations

**Role Context**: 
- Production-ready application with live backend
- Focus on stability and performance
- Light theme UI with Russian interface

**Backend Integration**:
- All frontend API calls go through HTTP client
- Real-time updates via WebSocket
- JWT authentication for all protected endpoints
- Network resilience with retry logic and timeouts

**Production Deployment**:
- Backend: Render.com with PostgreSQL + Redis
- Frontend builds: APK (131.5MB), Web (49MB)
- Environment-specific URLs via build flags

## Common Issues

**Dependencies:**
- flutter_map uses OpenStreetMap tiles; no proprietary map API key required (respect OSM tile usage policy in production)
- HTTP client configured with 30-second timeouts and retry logic

**State Management:**  
- Always use `ref.watch()` for reactive state in widgets
- Use `ref.listen()` for side effects (navigation, notifications)
- Provider overrides required for testing HTTP-dependent code

**Real-time Updates:**
- All order status changes flow through WebSocket automatically
- WebSocket client has heartbeat and auto-reconnection
- Graceful handling of connection drops and network changes

## Production URLs

- **API**: `https://tow-truck.onrender.com`
- **WebSocket**: `wss://tow-truck.onrender.com/ws/orders`
- **Web App**: `https://evik-web.onrender.com`

Configure via environment variables:
- `EVIK_API_BASE_URL`
- `EVIK_WS_URL`
