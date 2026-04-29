import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

class YandexMapView extends StatelessWidget {
  const YandexMapView({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialZoom = 14,
    this.onMapCreated,
    this.showTrafficLayer = true,
  });

  final double? initialLat;
  final double? initialLng;
  final double initialZoom;
  final ValueChanged<YandexMapController>? onMapCreated;
  final bool showTrafficLayer;

  @override
  Widget build(BuildContext context) {
    return YandexMap(
      onMapCreated: (controller) async {
        if (showTrafficLayer) {
          await controller.toggleTrafficLayer(visible: true);
        }

        final lat = initialLat;
        final lng = initialLng;
        if (lat != null && lng != null) {
          await controller.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: Point(latitude: lat, longitude: lng),
                zoom: initialZoom,
              ),
            ),
          );
        }

        onMapCreated?.call(controller);
      },
      onTrafficChanged: (_) {},
    );
  }
}
