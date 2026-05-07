class AppConstants {
  static const String appName = 'Tow Truck';
  static const String appVersion = '1.0.0';

  static const bool isProduction =
      bool.fromEnvironment('DART_DEFINE_ENV_PROD', defaultValue: false);

  // Mock режим для тестирования без бэкенда
  static const bool useMockData =
      bool.fromEnvironment('USE_MOCK_DATA', defaultValue: false);

  // Режим быстрого тестирования - пропуск авторизации
  static const bool skipAuth =
      bool.fromEnvironment('SKIP_AUTH', defaultValue: false);

  // ProMaps API keys.
  static const String promapsMapsApiKey = String.fromEnvironment(
    'PROMAPS_MAPS_API_KEY',
    defaultValue: 'pk_live_d44618284239626c98dc23cd909b2b6eff001df7cdecbc5',
  );

  static const String promapsRoadApiKey = String.fromEnvironment(
    'PROMAPS_ROAD_API_KEY',
    defaultValue: 'pk_live_26bf2e35cc95c1af08299b1681c8321db809acb1a2e43e10',
  );

  static const String promapsSdkApiKey = String.fromEnvironment(
    'PROMAPS_SDK_API_KEY',
    defaultValue: 'pk_live_16a7094708ceae689162d22b0d541421236a609a1bd436a0',
  );

  static const String promapsBaseUrl = 'https://api.promaps.online';

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
