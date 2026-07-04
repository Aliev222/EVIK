import 'package:flutter/foundation.dart';

class AppConstants {
  static const String appName = 'Авро';
  static const String appVersion = '1.0.0';

  static const bool isProduction =
      bool.fromEnvironment('DART_DEFINE_ENV_PROD', defaultValue: false);

  // Mock данные для разработки без сервера
  static const bool useMockData =
      bool.fromEnvironment('USE_MOCK_DATA', defaultValue: false);

  // Флаг пропуска авторизации - режим отладки
  static const bool skipAuth =
      bool.fromEnvironment('SKIP_AUTH', defaultValue: kDebugMode);

  static const String openStreetMapTileUrl = String.fromEnvironment(
    'OSM_TILE_URL',
    defaultValue: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
  );

  static const String openStreetMapAttribution = String.fromEnvironment(
    'OSM_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  static const String osrmBaseUrl = String.fromEnvironment(
    'OSRM_BASE_URL',
    defaultValue: 'https://router.project-osrm.org',
  );

  static const String nominatimBaseUrl = String.fromEnvironment(
    'NOMINATIM_BASE_URL',
    defaultValue: 'https://nominatim.openstreetmap.org',
  );

  static const Duration clientLocationUpdateInterval = Duration(seconds: 5);
  static const double clientRouteRefreshThresholdM = 75.0;

  static const Duration locationUpdateInterval = Duration(seconds: 10);
  static const Duration orderTimeoutDuration = Duration(minutes: 30);
  static const Duration splashDuration = Duration(milliseconds: 1400);

  static const double searchRadiusKm = 50.0;
  static const double defaultSearchRadiusKm = 5.0;
  static const double driverLocationUpdateDistanceM = 10.0;

  static const int maxOrderDistance = 50;
  static const int minOrderDistance = 1;
  static const double maxDriverRating = 5.0;
  static const double minDriverRating = 1.0;

  static const double defaultBaseFare = 500.0;
  static const double defaultPricePerKm = 25.0;
  static const double defaultMinimumFare = 800.0;

  static const Map<String, double> defaultVehicleMultipliers = {
    'light': 1.0,
    'suv': 1.2,
    'minibus': 1.5,
    'truck': 2.0,
  };

  static const double moscowLat = 55.7558;
  static const double moscowLng = 37.6173;

  static const List<String> activeOrderStatuses = <String>[
    'searching',
    'assigned',
    'onWay',
    'arrived',
    'evacuating',
  ];

  static const List<String> completedOrderStatuses = <String>[
    'completed',
    'cancelled',
  ];
}

class EvikAssetPaths {
  static const String sedan = 'assets/img/sedan.png';
  static const String crossover = 'assets/img/cross.png';
  static const String minibus = 'assets/img/bus.png';

  static const String winchTowTruck = 'assets/img/tros.png';
  static const String platformTowTruck = 'assets/img/forma.png';
  static const String manipulatorTowTruck = 'assets/img/mani.png';
}
