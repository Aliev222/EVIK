# EVIK Frontend

## Yandex MapKit Setup (Android)

Prerequisites:
- JDK 17 (or at least JDK 11)
- Android SDK configured

1. Copy `android/local.properties.example` to `android/local.properties`.
2. Add your key:

```properties
YANDEX_MAPKIT_API_KEY=YOUR_KEY_HERE
```

3. Run app as usual:

```bash
flutter pub get
flutter run -d android
```

Web:

```bash
flutter run -d chrome
```

Notes:
- API key is read from `android/local.properties` via Gradle and injected into `AndroidManifest.xml` as a placeholder.
- Never commit real keys to git.
- If key is missing or MapKit fails, EVIK shows a safe map placeholder without crashing.
- Web always uses a safe placeholder map (StubMapProvider).
