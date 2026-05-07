# EVIK Frontend

Flutter client for the EVIK tow truck app.

## Maps

The app uses ProMaps for map tiles, address lookup, reverse geocoding, and route metadata.

Configure keys with Dart defines when needed:

```bash
flutter run \
  --dart-define=PROMAPS_MAPS_API_KEY=YOUR_MAPS_KEY \
  --dart-define=PROMAPS_ROAD_API_KEY=YOUR_ROAD_KEY \
  --dart-define=PROMAPS_SDK_API_KEY=YOUR_SDK_KEY
```

For local development, defaults are defined in `lib/core/constants/app_constants.dart`.

## Run

```bash
flutter pub get
flutter run -d chrome
flutter run -d android
```
