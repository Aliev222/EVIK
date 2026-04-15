class Location {
  const Location({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;
}

abstract class MapProvider {
  Future<void> init();
  Future<void> moveCamera(double lat, double lng);
  Stream<Location> onLocationChanged();
}

class StubMapProvider implements MapProvider {
  StubMapProvider();

  final Stream<Location> _stream = const Stream<Location>.empty();

  @override
  Future<void> init() async {
    // TODO: Replace with platform-specific map initialization.
  }

  @override
  Future<void> moveCamera(double lat, double lng) async {
    // TODO: Forward coordinates to real map SDK.
  }

  @override
  Stream<Location> onLocationChanged() => _stream;
}
