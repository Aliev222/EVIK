import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'animated_driver_marker.dart';
import 'evik_osm_map_view.dart';

/// Live map showing real-time driver locations with OSM
class LiveDriverMap extends ConsumerStatefulWidget {
  const LiveDriverMap({
    super.key,
    this.pickupLocation,
    this.destinationLocation,
    this.showSearchAnimation = false,
    this.driverLocation,
    this.routePoints = const [],
    this.extraMarkers = const [],
    this.routeColor,
    this.adminMode = false,
    this.activeDrivers = const [],
    this.controlsBottomOffset = 42,
    this.showRecenterButton = false,
    this.onRecenter,
  });

  final MapLocation? pickupLocation;
  final MapLocation? destinationLocation;
  final bool showSearchAnimation;
  final DriverLocationUpdate? driverLocation;
  final List<LatLng> routePoints;
  final List<EvikMapMarker> extraMarkers;
  final Color? routeColor;
  final bool adminMode;
  final List<DriverLocationUpdate> activeDrivers;
  final double controlsBottomOffset;
  final bool showRecenterButton;
  final VoidCallback? onRecenter;

  @override
  ConsumerState<LiveDriverMap> createState() => _LiveDriverMapState();
}

class _LiveDriverMapState extends ConsumerState<LiveDriverMap> {
  @override
  Widget build(BuildContext context) {
    // Determine map center and initial zoom
    final centerLat = widget.pickupLocation?.latitude ??
        (widget.activeDrivers.isNotEmpty
            ? widget.activeDrivers.first.lat
            : 42.9764);
    final centerLng = widget.pickupLocation?.longitude ??
        (widget.activeDrivers.isNotEmpty
            ? widget.activeDrivers.first.lng
            : 47.5024);

    final zoom = widget.adminMode ? 12.0 : 15.0; // Zoom out for admin view

    // Build all map markers
    final markers = <EvikMapMarker>[...widget.extraMarkers];

    if (widget.pickupLocation != null) {
      markers.add(EvikMapMarker(
        lat: widget.pickupLocation!.latitude,
        lng: widget.pickupLocation!.longitude,
        title: 'Место погрузки',
        color: AvroClientColors.success,
        icon: Icons.trip_origin_rounded,
      ));
    }

    if (widget.destinationLocation != null) {
      markers.add(EvikMapMarker(
        lat: widget.destinationLocation!.latitude,
        lng: widget.destinationLocation!.longitude,
        title: 'Место назначения',
        color: AvroClientColors.accent,
        icon: Icons.flag_rounded,
      ));
    }

    return Stack(
      children: [
        // Base OSM view with markers and route
        Positioned.fill(
          child: EvikOsmMapView(
            initialLat: centerLat,
            initialLng: centerLng,
            initialZoom: zoom,
            markers: markers,
            routePoints: widget.routePoints,
            routeColor: widget.routeColor,
            showRecenterButton: widget.showRecenterButton,
            onRecenter: widget.onRecenter,
            controlsBottomOffset: widget.controlsBottomOffset,
            controlsBackgroundColor: AvroClientColors.background,
            controlsIconColor: AvroClientColors.accent,
            onTap: (lat, lng) {
              // Handle map tap if needed
            },
          ),
        ),

        // Search animation overlay
        if (widget.showSearchAnimation) _buildSearchAnimation(),

        // Driver info panel (non-admin mode)
        if (!widget.adminMode && widget.driverLocation != null)
          _buildDriverInfoPanel(widget.driverLocation!),
      ],
    );
  }

  Widget _buildSearchAnimation() {
    return Positioned.fill(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(seconds: 2),
          builder: (context, value, child) {
            return CustomPaint(
              size: const Size(200, 200),
              painter: SearchPulsePainter(
                animationValue: value,
                center: Offset.zero,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDriverInfoPanel(DriverLocationUpdate driver) {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AvroClientColors.background.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _getStatusColor(driver.status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getStatusText(driver.status),
                    style: const TextStyle(
                      color: AvroClientColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Скорость: ${driver.speed.toStringAsFixed(1)} км/ч',
                    style: const TextStyle(
                      color: AvroClientColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'ID: ${driver.driverId}',
              style: const TextStyle(
                color: AvroClientColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(DriverMarkerStatus status) {
    switch (status) {
      case DriverMarkerStatus.toPickup:
        return AvroClientColors.info;
      case DriverMarkerStatus.waiting:
        return AvroClientColors.accent;
      case DriverMarkerStatus.toDestination:
        return AvroClientColors.success;
    }
  }

  String _getStatusText(DriverMarkerStatus status) {
    switch (status) {
      case DriverMarkerStatus.toPickup:
        return 'Едет к вам';
      case DriverMarkerStatus.waiting:
        return 'Ожидает';
      case DriverMarkerStatus.toDestination:
        return 'Везет к месту назначения';
    }
  }
}

/// Custom painter for search pulse animation
class SearchPulsePainter extends CustomPainter {
  const SearchPulsePainter({
    required this.animationValue,
    required this.center,
  });

  final double animationValue;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          AvroClientColors.accent.withValues(alpha: 0.3 * (1 - animationValue))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw expanding circles
    for (int i = 0; i < 3; i++) {
      final radius = 30.0 + (animationValue * 80.0) + (i * 20.0);
      final alpha = (0.3 * (1 - animationValue)) - (i * 0.1);

      if (alpha > 0) {
        paint.color =
            AvroClientColors.accent.withValues(alpha: alpha.clamp(0.0, 1.0));
        canvas.drawCircle(size.center(Offset.zero), radius, paint);
      }
    }

    // Draw center point
    final centerPaint = Paint()
      ..color = AvroClientColors.accent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(size.center(Offset.zero), 8.0, centerPaint);
  }

  @override
  bool shouldRepaint(SearchPulsePainter oldDelegate) {
    return animationValue != oldDelegate.animationValue;
  }
}
