import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'animated_driver_marker.dart';
import 'evik_osm_map_view.dart';

/// Live map showing real-time driver locations with OSM
class LiveDriverMap extends ConsumerStatefulWidget {
  const LiveDriverMap({
    super.key,
    this.pickupLocation,
    this.destinationLocation,
    this.showRoute = false,
    this.showSearchAnimation = false,
    this.driverLocation,
    this.adminMode = false,
    this.activeDrivers = const [],
    this.controlsBottomOffset = 42,
  });

  final MapLocation? pickupLocation;
  final MapLocation? destinationLocation;
  final bool showRoute;
  final bool showSearchAnimation;
  final DriverLocationUpdate? driverLocation;
  final bool adminMode;
  final List<DriverLocationUpdate> activeDrivers;
  final double controlsBottomOffset;

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
            : 55.7558); // Moscow default
    final centerLng = widget.pickupLocation?.longitude ??
        (widget.activeDrivers.isNotEmpty
            ? widget.activeDrivers.first.lng
            : 37.6173); // Moscow default

    final zoom = widget.adminMode ? 12.0 : 15.0; // Zoom out for admin view

    return Stack(
      children: [
        // Base OSM view
        Positioned.fill(
          child: EvikOsmMapView(
            initialLat: centerLat,
            initialLng: centerLng,
            initialZoom: zoom,
            controlsBottomOffset: widget.controlsBottomOffset,
            controlsBackgroundColor: EvikColors.primaryWhite,
            controlsIconColor: EvikColors.accentOrange,
            onTap: (lat, lng) {
              // Handle map tap if needed
            },
          ),
        ),

        // Pickup location marker
        if (widget.pickupLocation != null)
          _buildStaticMarker(
            widget.pickupLocation!,
            Icons.location_on,
            EvikColors.successGreen,
            'Pickup',
          ),

        // Destination location marker
        if (widget.destinationLocation != null)
          _buildStaticMarker(
            widget.destinationLocation!,
            Icons.flag,
            EvikColors.accentOrange,
            'Destination',
          ),

        // Single driver marker (for client view)
        if (!widget.adminMode && widget.driverLocation != null)
          _buildDriverMarker(widget.driverLocation!),

        // Multiple driver markers (for admin view)
        if (widget.adminMode)
          ...widget.activeDrivers.map((driver) => _buildDriverMarker(driver)),

        // Search animation overlay
        if (widget.showSearchAnimation) _buildSearchAnimation(),

        // Driver info panel (non-admin mode)
        if (!widget.adminMode && widget.driverLocation != null)
          _buildDriverInfoPanel(widget.driverLocation!),
      ],
    );
  }

  Widget _buildStaticMarker(
    MapLocation location,
    IconData icon,
    Color color,
    String label,
  ) {
    return Positioned(
      left: _convertLngToX(location.longitude) - 15,
      top: _convertLatToY(location.latitude) - 30,
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: EvikColors.primaryWhite, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: EvikColors.primaryWhite,
              size: 16,
            ),
          ),
          Container(
            width: 2,
            height: 20,
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _buildDriverMarker(DriverLocationUpdate driver) {
    final driverLocation = LocationModel(
      lat: driver.lat,
      lng: driver.lng,
      address: 'Driver ${driver.driverId}',
    );
    final destination = widget.pickupLocation == null
        ? driverLocation
        : LocationModel(
            lat: widget.pickupLocation!.latitude,
            lng: widget.pickupLocation!.longitude,
            address: widget.pickupLocation!.displayAddress,
          );

    return Positioned(
      left: _convertLngToX(driver.lng) - 20,
      top: _convertLatToY(driver.lat) - 40,
      child: AnimatedDriverMarker(
        driverLocation: driverLocation,
        destination: destination,
        driverName: 'Водитель ${driver.driverId}',
        vehicleType: 'Эвакуатор',
        status: driver.status,
        onPositionUpdate: (position) {
          // Position updates handled by AnimatedDriverMarker
        },
      ),
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
          color: EvikColors.primaryWhite.withValues(alpha: 0.95),
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
                      color: EvikColors.primaryBlack,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Скорость: ${driver.speed.toStringAsFixed(1)} км/ч',
                    style: const TextStyle(
                      color: EvikColors.gray600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'ID: ${driver.driverId}',
              style: const TextStyle(
                color: EvikColors.gray600,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _convertLngToX(double lng) {
    // Convert longitude to screen X coordinate
    // This is a simplified conversion - in real implementation you'd use the map's projection
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth * 0.5; // Simplified center positioning
  }

  double _convertLatToY(double lat) {
    // Convert latitude to screen Y coordinate
    // This is a simplified conversion - in real implementation you'd use the map's projection
    final screenHeight = MediaQuery.of(context).size.height;
    return screenHeight * 0.5; // Simplified center positioning
  }

  Color _getStatusColor(DriverMarkerStatus status) {
    switch (status) {
      case DriverMarkerStatus.toPickup:
        return EvikColors.infoBlue;
      case DriverMarkerStatus.waiting:
        return EvikColors.accentOrange;
      case DriverMarkerStatus.toDestination:
        return EvikColors.successGreen;
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
          EvikColors.accentOrange.withValues(alpha: 0.3 * (1 - animationValue))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw expanding circles
    for (int i = 0; i < 3; i++) {
      final radius = 30.0 + (animationValue * 80.0) + (i * 20.0);
      final alpha = (0.3 * (1 - animationValue)) - (i * 0.1);

      if (alpha > 0) {
        paint.color =
            EvikColors.accentOrange.withValues(alpha: alpha.clamp(0.0, 1.0));
        canvas.drawCircle(size.center(Offset.zero), radius, paint);
      }
    }

    // Draw center point
    final centerPaint = Paint()
      ..color = EvikColors.accentOrange
      ..style = PaintingStyle.fill;
    canvas.drawCircle(size.center(Offset.zero), 8.0, centerPaint);
  }

  @override
  bool shouldRepaint(SearchPulsePainter oldDelegate) {
    return animationValue != oldDelegate.animationValue;
  }
}
