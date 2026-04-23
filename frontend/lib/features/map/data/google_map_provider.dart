import 'dart:async';

import '../../../core/map/map_provider.dart';

class GoogleMapProvider implements MapProvider {
  GoogleMapProvider();

  final StreamController<Location> _locationController =
      StreamController<Location>.broadcast();
  final StreamController<RouteSummary?> _routeSummaryController =
      StreamController<RouteSummary?>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<void> moveCamera(double lat, double lng) async {
    _locationController.add(Location(lat: lat, lng: lng));
  }

  @override
  Future<void> setMarkers(List<MapMarker> markers) async {}

  @override
  Future<void> clearMarkers() async {}

  @override
  Future<void> setRoute(List<Location> points) async {}

  @override
  Future<void> clearRoute() async {}

  @override
  Stream<Location> onLocationChanged() => _locationController.stream;

  @override
  Stream<RouteSummary?> onRouteSummaryChanged() =>
      _routeSummaryController.stream;

  Future<void> dispose() async {
    await _locationController.close();
    await _routeSummaryController.close();
  }
}
