import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

class MapKitAvailability {
  const MapKitAvailability._();

  static const MethodChannel _channel =
      MethodChannel('evik/yandex_map_provider');

  static Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }
}

class MapKitUnavailablePlaceholder extends StatelessWidget {
  const MapKitUnavailablePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF3F5F8),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE7DF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.map_outlined,
                  color: Color(0xFFFF5A2C),
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Карта недоступна',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Добавьте YANDEX_MAPKIT_API_KEY в android/local.properties и пересоберите приложение.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.55),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MapKitAwareYandexMap extends StatelessWidget {
  const MapKitAwareYandexMap({
    super.key,
    required this.builder,
  });

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: MapKitAvailability.isAvailable(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(color: Color(0xFFF3F5F8));
        }
        if (snapshot.data != true) {
          return const MapKitUnavailablePlaceholder();
        }
        return builder(context);
      },
    );
  }
}

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
    return MapKitAwareYandexMap(
      builder: (_) => YandexMap(
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
      ),
    );
  }
}
