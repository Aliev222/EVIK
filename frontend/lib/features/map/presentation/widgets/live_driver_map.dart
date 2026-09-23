import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors;
import 'package:tow_truck_frontend/features/map/domain/entities/map_location.dart';
import 'package:tow_truck_frontend/features/map/domain/driver_motion.dart';
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
    this.animatedDriverLocation,
    this.driverMarkerBuilder,
    this.animateDriverMarker = false,
    this.routePoints = const [],
    this.extraMarkers = const [],
    this.routeColor,
    this.routeStrokeWidth = 3,
    this.routeBorderStrokeWidth = 1.5,
    this.scaleMarkersWithZoom = false,
    this.adminMode = false,
    this.activeDrivers = const [],
    this.controlsBottomOffset = 42,
    this.attributionBottomOffset = 16,
    this.attributionRightOffset = 16,
    this.showRecenterButton = false,
    this.onRecenter,
    this.onManualCamera,
    this.fitToMarkers = true,
    this.fitPadding = const EdgeInsets.all(42),
    this.initialZoom = 15,
  });

  final MapLocation? pickupLocation;
  final MapLocation? destinationLocation;
  final bool showSearchAnimation;
  final DriverLocationUpdate? driverLocation;

  /// A tracking-only input. Its animation is contained in this map state, so
  /// the surrounding order screen and its sheet do not rebuild on every frame.
  final DriverLocationUpdate? animatedDriverLocation;
  final Widget Function(DriverLocationUpdate location)? driverMarkerBuilder;
  final bool animateDriverMarker;
  final List<LatLng> routePoints;
  final List<EvikMapMarker> extraMarkers;
  final Color? routeColor;
  final double routeStrokeWidth;
  final double routeBorderStrokeWidth;
  final bool scaleMarkersWithZoom;
  final bool adminMode;
  final List<DriverLocationUpdate> activeDrivers;
  final double controlsBottomOffset;
  final double attributionBottomOffset;
  final double attributionRightOffset;
  final bool showRecenterButton;
  final VoidCallback? onRecenter;
  final VoidCallback? onManualCamera;
  final bool fitToMarkers;
  final EdgeInsets fitPadding;
  final double initialZoom;

  @override
  ConsumerState<LiveDriverMap> createState() => _LiveDriverMapState();
}

class _LiveDriverMapState extends ConsumerState<LiveDriverMap>
    with SingleTickerProviderStateMixin {
  static const _driverMotionDuration = Duration(milliseconds: 2000);

  late final AnimationController _driverMotionController;
  DriverLocationUpdate? _motionStart;
  DriverLocationUpdate? _motionEnd;

  @override
  void initState() {
    super.initState();
    _driverMotionController = AnimationController(
      vsync: this,
      duration: _driverMotionDuration,
    )..addListener(() {
        if (mounted) setState(() {});
      });
    final initial = widget.animatedDriverLocation;
    if (initial != null) _motionStart = _motionEnd = initial;
  }

  @override
  void didUpdateWidget(covariant LiveDriverMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rawIncoming = widget.animatedDriverLocation;
    if (!widget.animateDriverMarker || rawIncoming == null) return;
    final previousTarget = _motionEnd;
    if (previousTarget == null) {
      _motionStart = _motionEnd = rawIncoming;
      return;
    }
    // GPS heading is effectively noise while stationary. Keep the last
    // confirmed nose direction until movement resumes.
    final incoming = _withBearing(
      rawIncoming,
      stableDriverBearing(
        previous: previousTarget.bearing,
        incoming: rawIncoming.bearing,
        speedKmh: rawIncoming.speed,
      ),
    );
    if (_sameFix(previousTarget, incoming)) return;
    _motionStart = _displayedDriverLocation ?? previousTarget;
    _motionEnd = incoming;
    _driverMotionController.duration = driverMotionDuration(
      previousTarget.timestamp,
      incoming.timestamp,
    );
    _driverMotionController.forward(from: 0);
  }

  @override
  void dispose() {
    _driverMotionController.dispose();
    super.dispose();
  }

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

    final zoom = widget.adminMode ? 12.0 : widget.initialZoom;

    final displayedDriver = _displayedDriverLocation;
    final displayedRoute = widget.routePoints;

    // Build all map markers. The animated driver is appended last so it is
    // never hidden behind pickup/destination markers at close zoom.
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

    if (widget.animateDriverMarker &&
        displayedDriver != null &&
        widget.driverMarkerBuilder != null) {
      markers.add(EvikMapMarker(
        lat: displayedDriver.lat,
        lng: displayedDriver.lng,
        title: 'Эвакуатор',
        color: AvroClientColors.accent,
        child: widget.driverMarkerBuilder!(displayedDriver),
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
            routePoints: displayedRoute,
            routeColor: widget.routeColor,
            routeStrokeWidth: widget.routeStrokeWidth,
            routeBorderStrokeWidth: widget.routeBorderStrokeWidth,
            scaleMarkersWithZoom: widget.scaleMarkersWithZoom,
            showRecenterButton: widget.showRecenterButton,
            onRecenter: widget.onRecenter,
            onManualCamera: widget.onManualCamera,
            fitToMarkers: widget.fitToMarkers,
            // The animated driver marker changes every frame. Camera fitting
            // belongs to route/phase changes, never to animation frames.
            refitOnMarkerChanges: false,
            fitPadding: widget.fitPadding,
            controlsBottomOffset: widget.controlsBottomOffset,
            attributionBottomOffset: widget.attributionBottomOffset,
            attributionRightOffset: widget.attributionRightOffset,
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

  DriverLocationUpdate? get _displayedDriverLocation {
    final end = _motionEnd;
    if (end == null) return null;
    final start = _motionStart ?? end;
    // Linear interpolation preserves velocity across regularly spaced GPS
    // fixes; restarting an ease-in curve for every packet creates visible
    // stop/go motion even when the tow truck moves steadily.
    final progress = _driverMotionController.value;
    final routedPosition = interpolateDriverPositionOnRoute(
      start: LatLng(start.lat, start.lng),
      end: LatLng(end.lat, end.lng),
      route: widget.routePoints,
      progress: progress,
      accuracyM: end.accuracyM ?? 15,
      bearing: end.bearing,
      speedKmh: end.speed,
    );
    return DriverLocationUpdate(
      driverId: end.driverId,
      lat: routedPosition?.latitude ?? _lerp(start.lat, end.lat, progress),
      lng: routedPosition?.longitude ?? _lerp(start.lng, end.lng, progress),
      bearing: interpolateDriverBearing(start.bearing, end.bearing, progress),
      speed: end.speed,
      status: end.status,
      orderId: end.orderId,
      timestamp: end.timestamp,
      sequence: end.sequence,
      receivedAt: end.receivedAt,
      accuracyM: end.accuracyM,
    );
  }

  bool _sameFix(DriverLocationUpdate a, DriverLocationUpdate b) =>
      a.lat == b.lat &&
      a.lng == b.lng &&
      a.bearing == b.bearing &&
      a.timestamp == b.timestamp;

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  DriverLocationUpdate _withBearing(
    DriverLocationUpdate update,
    double bearing,
  ) =>
      DriverLocationUpdate(
        driverId: update.driverId,
        lat: update.lat,
        lng: update.lng,
        bearing: bearing,
        speed: update.speed,
        status: update.status,
        orderId: update.orderId,
        timestamp: update.timestamp,
        sequence: update.sequence,
        receivedAt: update.receivedAt,
        accuracyM: update.accuracyM,
      );

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
