# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EVIK is a cross-platform Flutter tow truck application ("Uber for tow trucks") targeting iOS, Android, and Web platforms. The project consists of a production-ready Flutter frontend with Firebase backend integration, plus legacy Go backend infrastructure.

## Architecture Status

**Active Architecture: Flutter + Firebase**
- Frontend: Flutter with Riverpod state management
- Backend: Firebase (Firestore, Auth, Storage, Cloud Messaging) 
- Maps: Yandex Maps (yandex_mapkit ^4.2.1)
- Authentication: Firebase Phone Auth with SMS verification

**Legacy Architecture: Go + PostgreSQL + Redis** 
- Backend files exist in `/backend` but are not integrated with current frontend
- Original WebSocket-based real-time architecture replaced by Firestore real-time listeners
- Docker Compose setup available for Go backend development

## Key Flutter Commands

```bash
# Working directory: frontend/

# Development
flutter run -d chrome --web-port 3000
flutter run -d windows
flutter run --debug

# Analysis and Testing
flutter analyze --no-pub
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

## Firebase Configuration

Firebase initialization is required for the app to function:

1. **Development Setup**:
   - Mock Firebase config exists in `lib/firebase_options.dart`
   - Firebase emulators supported via environment variables:
     - `EVIK_USE_FIREBASE_EMULATOR=true`
     - `EVIK_FIREBASE_AUTH_HOST=127.0.0.1`
     - `EVIK_FIREBASE_AUTH_PORT=9099`
     - `EVIK_FIRESTORE_HOST=127.0.0.1` 
     - `EVIK_FIRESTORE_PORT=8080`
     - `EVIK_STORAGE_HOST=127.0.0.1`
     - `EVIK_STORAGE_PORT=9199`

2. **Production**: Replace `firebase_options.dart` with real Firebase project configuration

## Code Architecture

### Clean Architecture Pattern

```
lib/
├── core/                    # Shared infrastructure
│   ├── services/           # Firebase, location, pricing
│   ├── constants/          # App constants, Firestore collections
│   └── theme/             # Design system (EvikColors, EvikTokens)
├── features/              # Feature-based modules
│   ├── auth/              # Phone authentication + SMS
│   ├── onboarding/        # Role selection (client/driver)
│   ├── client/            # Client order management  
│   ├── driver/            # Driver order acceptance + onboarding
│   ├── order/             # Shared order domain
│   └── map/               # Yandex Maps integration
└── shared/               # Cross-feature models
```

### State Management - Riverpod Patterns

**Provider Types:**
- `Provider`: Pure dependencies (services, repositories)
- `StateNotifierProvider`: Mutable state with business logic
- `StreamProvider`: Firestore real-time data
- `FutureProvider`: Async operations

**Key Providers:**
- `authProvider`: Authentication state
- `currentUserProvider`: Current user data
- `clientOrderProvider`: Client order management
- `driverProvider`: Driver status and orders
- `mapProvider`: Map state and location

### Firebase Collections Structure

```
users/{userId}              # User profiles
drivers/{userId}            # Driver details (vehicle, earnings, online status)
drivers_verification/{userId} # Driver document verification (pending/approved/rejected)
orders/{orderId}           # Orders with real-time status updates
tariffs/current            # Pricing configuration
```

### User Flows

**Client Flow:**
1. Role Selection → Phone Auth → SMS Verification
2. Client Home Screen with Yandex Map
3. Order Creation: pickup/dropoff selection, vehicle type, pricing
4. Real-time order tracking (searching → assigned → arriving → evacuating → completed)

**Driver Flow:**  
1. Role Selection → Phone Auth → SMS Verification
2. Driver Onboarding: document upload (passport, license, vehicle docs, selfie)
3. Moderation: real-time status tracking (pending → approved/rejected)
4. Driver Home Screen: online toggle, available orders, active order management

## Testing Strategy

**Test Files:**
- `test/architecture_smoke_test.dart`: Widget integration tests with provider overrides
- `test/ui_audit_screens_test.dart`: UI validation across screens
- `test/role_selection_screen_golden_test.dart`: Golden file visual testing

**Test Patterns:**
- Provider overrides for Firebase-dependent widgets
- Fake repositories to avoid Firebase initialization in tests
- Widget pump-and-settle for async UI updates

## Maps Integration

**Yandex Maps Setup:**
- API key configuration: `AppConstants.yandexMapkitApiKey`
- Custom wrapper: `EvikMapWidget` with EVIK-specific styling
- Features: location tracking, route building, custom markers
- Fallback: Google Maps provider available but not active

## Development Workflow Considerations

**Role Context**: 
- You are Tech Lead who reviews code and assigns tasks to Codex agent
- User is Tech Lead/Product Manager who makes architectural decisions
- Focus on architecture first, design polish later

**Firebase vs Backend**:
- Current development uses Firebase exclusively
- Go backend exists but frontend doesn't integrate with it
- All new features should use Firestore real-time listeners, not HTTP/WebSocket

**Moderation System**:
- Driver document verification implemented but approval/rejection requires manual Firestore updates
- Admin panel not yet implemented - uses debug methods for testing

## Common Issues

**Dependencies:**
- Yandex MapKit version locked at ^4.2.1 (higher versions cause conflicts)
- Firebase options must be properly configured for any Firebase features to work

**State Management:**  
- Always use `ref.watch()` for reactive state in widgets
- Use `ref.listen()` for side effects (navigation, notifications)
- Provider overrides required for testing Firebase-dependent code

**Real-time Updates:**
- All order status changes flow through Firestore automatically
- No manual state synchronization needed between collections
- Stream providers handle connection/disconnection gracefully