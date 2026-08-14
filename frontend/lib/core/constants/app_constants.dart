class AppConstants {
  static const String appName = 'Авро';
  static const String appVersion = '1.0.0';

  static const bool isProduction =
      bool.fromEnvironment('DART_DEFINE_ENV_PROD', defaultValue: false);

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

  static const double makhachkalaLat = 42.9849;
  static const double makhachkalaLng = 47.5047;

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

  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://avro.app/privacy',
  );

  static const String termsOfServiceUrl = String.fromEnvironment(
    'TERMS_OF_SERVICE_URL',
    defaultValue: 'https://avro.app/terms',
  );

  /// Единый контакт поддержки для всех фич (модерация, профиль и пр.).
  static const String supportEmail = String.fromEnvironment(
    'EVIK_SUPPORT_EMAIL',
    defaultValue: 'support@avro.app',
  );
}

class EvikAssetPaths {
  static const String sedan = 'assets/img/sedan.png';
  static const String crossover = 'assets/img/cross.png';
  static const String minibus = 'assets/img/bus.png';

  static const String winchTowTruck = 'assets/img/tros.png';
  static const String platformTowTruck = 'assets/img/forma.png';
  static const String manipulatorTowTruck = 'assets/img/mani.png';
}
