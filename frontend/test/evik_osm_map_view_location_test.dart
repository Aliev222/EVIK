import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('my location button centers the camera on the client position',
      (tester) async {
    final controller = MapController();
    var recenterCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EvikOsmMapView(
            initialLat: 42.9849,
            initialLng: 47.4947,
            initialZoom: 15,
            showControls: false,
            showUserLocation: false,
            showStandaloneLocationButton: true,
            mapController: controller,
            onRecenter: () => recenterCalls++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('Моё местоположение'), findsOneWidget);

    // User pans away from the client position.
    controller.move(const LatLng(43.2, 47.0), 11);
    await tester.pump();
    expect(controller.camera.center.latitude, closeTo(43.2, 0.0001));

    await tester.tap(find.byTooltip('Моё местоположение'));
    await tester.pump();

    expect(controller.camera.center.latitude, closeTo(42.9849, 0.0001));
    expect(controller.camera.center.longitude, closeTo(47.4947, 0.0001));
    expect(controller.camera.zoom, closeTo(17, 0.0001));
    expect(recenterCalls, 1);
  });

  testWidgets('map tap without an onTap handler is a no-op', (tester) async {
    final controller = MapController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EvikOsmMapView(
            initialLat: 42.9849,
            initialLng: 47.4947,
            initialZoom: 15,
            showControls: false,
            showUserLocation: false,
            mapController: controller,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final centerBefore = controller.camera.center;
    // Tap the middle of the map: nothing must change.
    await tester.tapAt(tester.getCenter(find.byType(EvikOsmMapView)));
    // flutter_map delays single-tap resolution by 250ms (double-tap
    // disambiguation); advance past it so no timer leaks.
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.camera.center.latitude, closeTo(centerBefore.latitude, 0.0001));
    expect(controller.camera.center.longitude, closeTo(centerBefore.longitude, 0.0001));
  });
}