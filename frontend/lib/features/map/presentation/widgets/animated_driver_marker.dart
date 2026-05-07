import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../../../../core/services/promaps_service.dart';
import '../../../order/domain/entities/order.dart';

/// Animated driver marker that smoothly moves along ProMaps route
class AnimatedDriverMarker extends StatefulWidget {
  const AnimatedDriverMarker({
    super.key,
    required this.driverLocation,
    required this.destination,
    required this.driverName,
    required this.vehicleType,
    this.status = DriverMarkerStatus.toPickup,
    this.onPositionUpdate,
  });

  final LocationModel driverLocation;
  final LocationModel destination;
  final String driverName;
  final String vehicleType;
  final DriverMarkerStatus status;
  final Function(LocationModel position)? onPositionUpdate;

  @override
  State<AnimatedDriverMarker> createState() => _AnimatedDriverMarkerState();
}

class _AnimatedDriverMarkerState extends State<AnimatedDriverMarker>
    with TickerProviderStateMixin {
  late AnimationController _moveController;
  late AnimationController _rotationController;

  List<LocationModel> _routePoints = [];
  LocationModel? _currentPosition;
  double _currentBearing = 0;
  Timer? _routeUpdateTimer;

  @override
  void initState() {
    super.initState();

    _moveController = AnimationController(
      duration: const Duration(seconds: 5), // 5 seconds per segment
      vsync: this,
    );

    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _currentPosition = widget.driverLocation;
    _initializeRoute();
  }

  @override
  void dispose() {
    _moveController.dispose();
    _rotationController.dispose();
    _routeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeRoute() async {
    try {
      // Get route from ProMaps
      final route = await ProMapsService.getRoute(
        fromLat: widget.driverLocation.lat,
        fromLng: widget.driverLocation.lng,
        toLat: widget.destination.lat,
        toLng: widget.destination.lng,
        profile: 'driving',
      );

      if (route?.polyline != null) {
        // Decode polyline into points (simplified)
        _routePoints = _decodePolyline(route!.polyline!);
        _startAnimation();
      } else {
        // Fallback: direct line movement
        _routePoints = [widget.driverLocation, widget.destination];
        _startAnimation();
      }
    } catch (e) {
      // Fallback on error
      _routePoints = [widget.driverLocation, widget.destination];
      _startAnimation();
    }

    // Update route every 30 seconds
    _routeUpdateTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _initializeRoute(),
    );
  }

  void _startAnimation() {
    if (_routePoints.length < 2) return;

    _moveController.addListener(() {
      _updatePosition();
    });

    _moveController.repeat();
  }

  void _updatePosition() {
    if (_routePoints.isEmpty) return;

    final progress = _moveController.value;
    final totalSegments = _routePoints.length - 1;
    final currentSegmentIndex = (progress * totalSegments).floor().clamp(0, totalSegments - 1);
    final segmentProgress = (progress * totalSegments) - currentSegmentIndex;

    if (currentSegmentIndex < _routePoints.length - 1) {
      final start = _routePoints[currentSegmentIndex];
      final end = _routePoints[currentSegmentIndex + 1];

      // Interpolate position
      final lat = start.lat + (end.lat - start.lat) * segmentProgress;
      final lng = start.lng + (end.lng - start.lng) * segmentProgress;

      // Calculate bearing (direction)
      final bearing = _calculateBearing(start, end);

      setState(() {
        _currentPosition = LocationModel(
          lat: lat,
          lng: lng,
          address: 'Движется...',
        );
        _currentBearing = bearing;
      });

      // Notify parent about position update
      widget.onPositionUpdate?.call(_currentPosition!);
    }
  }

  double _calculateBearing(LocationModel start, LocationModel end) {
    final lat1 = start.lat * pi / 180;
    final lat2 = end.lat * pi / 180;
    final deltaLng = (end.lng - start.lng) * pi / 180;

    final y = sin(deltaLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng);

    return atan2(y, x) * 180 / pi;
  }

  List<LocationModel> _decodePolyline(String polyline) {
    // Simplified polyline decoder (in real app, use proper decoder)
    // For now, create intermediate points between start and end
    final points = <LocationModel>[];
    final steps = 10; // 10 intermediate points

    for (int i = 0; i <= steps; i++) {
      final ratio = i / steps;
      final lat = widget.driverLocation.lat +
          (widget.destination.lat - widget.driverLocation.lat) * ratio;
      final lng = widget.driverLocation.lng +
          (widget.destination.lng - widget.driverLocation.lng) * ratio;

      points.add(LocationModel(
        lat: lat,
        lng: lng,
        address: 'Route point $i',
      ));
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPosition == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _currentBearing * pi / 180,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: widget.status.color, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                widget.status.iconPath,
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback to default icon if image fails to load
                  return Icon(
                    widget.status.icon,
                    color: widget.status.color,
                    size: 24,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Driver marker status with corresponding colors and icons
enum DriverMarkerStatus {
  toPickup,
  toDestination,
  waiting;

  Color get color {
    switch (this) {
      case DriverMarkerStatus.toPickup:
        return const Color(0xFF10B981); // Green - coming to pickup
      case DriverMarkerStatus.toDestination:
        return const Color(0xFF3B82F6); // Blue - driving to destination
      case DriverMarkerStatus.waiting:
        return const Color(0xFFF59E0B); // Orange - waiting
    }
  }

  String get iconPath {
    switch (this) {
      case DriverMarkerStatus.toPickup:
        return 'assets/images/vehicles/truck.png'; // Пустой эвакуатор
      case DriverMarkerStatus.toDestination:
        return 'assets/images/vehicles/truck_loaded.png'; // Загруженный эвакуатор
      case DriverMarkerStatus.waiting:
        return 'assets/images/vehicles/truck.png'; // Ожидает
    }
  }

  IconData get icon {
    switch (this) {
      case DriverMarkerStatus.toPickup:
        return Icons.local_shipping; // Fallback icon
      case DriverMarkerStatus.toDestination:
        return Icons.local_shipping; // Fallback icon
      case DriverMarkerStatus.waiting:
        return Icons.pause; // Pause icon
    }
  }

  String get label {
    switch (this) {
      case DriverMarkerStatus.toPickup:
        return 'Едет к вам';
      case DriverMarkerStatus.toDestination:
        return 'Везет машину';
      case DriverMarkerStatus.waiting:
        return 'Ожидает';
    }
  }
}