import 'dart:async';

import '../../../core/map/map_provider.dart';

class GoogleMapProvider implements MapProvider {
  GoogleMapProvider();

  final StreamController<Location> _locationController = StreamController<Location>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<void> moveCamera(double lat, double lng) async {
    _locationController.add(Location(lat: lat, lng: lng));
  }

  @override
  Stream<Location> onLocationChanged() => _locationController.stream;

  Future<void> dispose() async {
    await _locationController.close();
  }
}
