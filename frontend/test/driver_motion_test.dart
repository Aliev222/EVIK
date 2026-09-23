import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tow_truck_frontend/features/map/domain/driver_motion.dart';

void main() {
  test('bearing crosses north by the shortest arc', () {
    final halfway = interpolateDriverBearing(359, 1, .5);
    expect(halfway.abs() < .001 || (halfway - 360).abs() < .001, isTrue);
  });

  test('stationary GPS noise cannot rotate the tow truck', () {
    expect(
      stableDriverBearing(previous: 87, incoming: 241, speedKmh: .4),
      87,
    );
    expect(
      stableDriverBearing(previous: 87, incoming: 91, speedKmh: 18),
      91,
    );
  });

  test('animation follows sample cadence within safe bounds', () {
    final start = DateTime.utc(2026, 9, 18, 12);
    expect(
      driverMotionDuration(start, start.add(const Duration(seconds: 2))),
      const Duration(seconds: 2),
    );
    expect(
      driverMotionDuration(start, start.add(const Duration(seconds: 20))),
      const Duration(seconds: 3),
    );
  });

  test('position follows a confirmed bend instead of cutting its corner', () {
    final position = interpolateDriverPositionOnRoute(
      start: const LatLng(42.00000, 47.00000),
      end: const LatLng(42.00100, 47.00100),
      route: const [
        LatLng(42.00000, 47.00000),
        LatLng(42.00100, 47.00000),
        LatLng(42.00100, 47.00100),
      ],
      progress: .5,
      accuracyM: 5,
      bearing: 90,
      speedKmh: 18,
    );

    expect(position, isNotNull);
    expect(position!.longitude, closeTo(47, .00002));
    expect(position.latitude, closeTo(42.0009, .00015));
  });

  test('does not snap a yard fix onto a nearby road', () {
    final position = interpolateDriverPositionOnRoute(
      start: const LatLng(42.00000, 47.00000),
      end: const LatLng(42.00100, 47.00100),
      route: const [
        LatLng(42.00000, 47.00000),
        LatLng(42.00200, 47.00000),
      ],
      progress: .5,
      accuracyM: 5,
      bearing: 0,
      speedKmh: 18,
    );

    expect(position, isNull);
  });
}
