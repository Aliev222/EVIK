import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'location_service.dart';
import 'map_api.dart';

export 'map_api.dart' show OsmLocation, OsmPlace, RoutePreview;

class OpenStreetMapService {
  static final MapApi _mapApi = MapApi();

  static String getMapTileUrl({
    required int zoom,
    required int x,
    required int y,
  }) {
    return AppConstants.openStreetMapTileUrl
        .replaceAll('{z}', zoom.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }

  static Future<OsmLocation?> geocode(String address) async {
    return _mapApi.geocode(address);
  }

  static Future<OsmLocation?> searchLocation(String query) => geocode(query);

  static Future<OsmLocation?> getCurrentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    Position position;
    try {
      position = await LocationService.getCurrentPositionWithFallback();
    } catch (_) {
      return null;
    }

    final address = await reverseGeocode(
      lat: position.latitude,
      lng: position.longitude,
    );

    return OsmLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address ?? 'Current location',
    );
  }

  static Future<String?> reverseGeocode({
    required double lat,
    required double lng,
  }) =>
      _mapApi.reverseGeocode(lat: lat, lng: lng);

  static Future<RoutePreview?> getRoutePreview({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String profile = 'driving',
  }) =>
      _mapApi.getRoutePreview(
        fromLat: fromLat,
        fromLng: fromLng,
        toLat: toLat,
        toLng: toLng,
      );

  static Future<List<OsmPlace>> searchNearby({
    required double lat,
    required double lng,
    required String query,
    double radius = 1000,
    int limit = 10,
  }) async {
    final location = await geocode('$query near $lat,$lng');
    if (location == null) return const <OsmPlace>[];

    return <OsmPlace>[
      OsmPlace(
        name: query,
        address: location.address,
        latitude: location.latitude,
        longitude: location.longitude,
        category: '',
      ),
    ];
  }
}
