class Location {
  const Location({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;
}

class MapMarker {
  const MapMarker({
    required this.id,
    required this.location,
    this.title,
  });

  final String id;
  final Location location;
  final String? title;
}

class RouteSummary {
  const RouteSummary({
    required this.distanceKm,
    required this.etaMinutes,
  });

  final double distanceKm;
  final int etaMinutes;
}

abstract class MapProvider {
  Future<void> init();
  Future<void> moveCamera(double lat, double lng);
  Future<void> setMarkers(List<MapMarker> markers);
  Future<void> clearMarkers();
  Future<void> setRoute(List<Location> points);
  Future<void> clearRoute();
  Stream<Location> onLocationChanged();
  Stream<RouteSummary?> onRouteSummaryChanged();
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
  Future<void> setMarkers(List<MapMarker> markers) async {
    // TODO: Forward markers to real map SDK.
  }

  @override
  Future<void> clearMarkers() async {
    // TODO: Forward marker clear to real map SDK.
  }

  @override
  Future<void> setRoute(List<Location> points) async {
    // TODO: Forward route polyline to real map SDK.
  }

  @override
  Future<void> clearRoute() async {
    // TODO: Forward route clear to real map SDK.
  }

  @override
  Stream<Location> onLocationChanged() => _stream;

  @override
  Stream<RouteSummary?> onRouteSummaryChanged() =>
      const Stream<RouteSummary?>.empty();
}
