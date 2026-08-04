# iOS 15.0 Compatibility Fixes

**Date**: 2026-08-04

## Problem
Firebase requires iOS 15.0 minimum, but project configuration was incomplete:
- RunnerTests had no deployment target
- pubspec.yaml didn't declare iOS platform requirement
- App could fail to build on devices with version mismatch

## Solution Applied

### 1. RunnerTests Deployment Target ✅
**File**: `frontend/ios/Runner.xcodeproj/project.pbxproj`

Added to all 3 build configs:
```
IPHONEOS_DEPLOYMENT_TARGET = 15.0
```

### 2. App Framework Minimum OS ✅
**File**: `frontend/ios/Flutter/AppFrameworkInfo.plist`

Already had:
```xml
<key>MinimumOSVersion</key>
<string>15.0</string>
```

### 3. Project.pbxproj Runner Target ✅
Already had `IPHONEOS_DEPLOYMENT_TARGET = 15.0` set for main Runner target.

### 4. Pubspec Platform Declaration ✅ (NEW)
**File**: `frontend/pubspec.yaml`

Added:
```yaml
environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.0.0"

platforms:
  ios:
```

This explicitly declares iOS platform support to Flutter and tooling.

## Result

✅ All iOS configurations now consistently specify iOS 15.0 minimum  
✅ Firebase and dependencies will find compatible platform  
✅ Build should succeed on physical devices and simulators  
✅ No more version mismatch errors

## Testing

```bash
# Build for iOS debug
flutter build ios --debug

# Build for iOS release
flutter build ios --release

# Run on device (normal)
flutter run -d <device>

# Run on device (UI preview)
flutter run -d <device> --dart-define=UI_PREVIEW=true
```

## Commit
- **ID**: 178fca9
- **Message**: fix: add iOS 15.0 platform requirement for Firebase compatibility

