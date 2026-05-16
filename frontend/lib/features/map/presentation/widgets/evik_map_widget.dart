import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/map/presentation/providers/map_provider.dart';
import 'evik_osm_map_view.dart';

class EvikMapWidget extends ConsumerWidget {
  const EvikMapWidget({
    super.key,
    this.onMapTap,
    this.onMapLongPress,
    this.onCameraMove,
    this.isSelectionMode = false,
    this.crosshairVisible = false,
  });

  final void Function(MapLocation location)? onMapTap;
  final void Function(MapLocation location)? onMapLongPress;
  final void Function(MapLocation location)? onCameraMove;
  final bool isSelectionMode;
  final bool crosshairVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapState = ref.watch(mapProvider);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTapDown: (_) {
              final current =
                  mapState.cameraPosition ?? mapState.currentPosition;
              if (current != null) onMapTap?.call(current);
            },
            onLongPress: () {
              final current =
                  mapState.cameraPosition ?? mapState.currentPosition;
              if (current != null) onMapLongPress?.call(current);
            },
            child: EvikOsmMapView(
              initialLat: mapState.cameraPosition?.latitude ??
                  mapState.currentPosition?.latitude,
              initialLng: mapState.cameraPosition?.longitude ??
                  mapState.currentPosition?.longitude,
              initialZoom: mapState.zoomLevel,
              onTap: (lat, lng) {
                onMapTap?.call(MapLocation(
                  latitude: lat,
                  longitude: lng,
                  address: '',
                ));
              },
            ),
          ),
        ),
        if (crosshairVisible)
          const Center(
            child: Icon(
              Icons.add_circle,
              size: 34,
              color: EvikColors.accent,
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (mapState.currentPosition != null)
                const _Chip(
                    label: 'Вы на карте', icon: Icons.my_location_outlined),
              if (mapState.pickupLocation != null)
                const _Chip(label: 'Забор выбран', icon: Icons.trip_origin),
              if (mapState.dropoffLocation != null)
                const _Chip(
                    label: 'Доставка выбрана', icon: Icons.flag_outlined),
              if (isSelectionMode)
                const _Chip(
                  label: 'Режим выбора точки',
                  icon: Icons.touch_app_outlined,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.42;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth.clamp(120.0, 220.0)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
