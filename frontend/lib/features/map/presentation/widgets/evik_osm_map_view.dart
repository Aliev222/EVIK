import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'pulsing_location_dot.dart';

class EvikOsmMapView extends StatefulWidget {
  const EvikOsmMapView({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialZoom = 14,
    this.onTap,
    this.onCameraMove,
    this.onCameraEnd,
    this.onRecenter,
    this.markers = const <EvikMapMarker>[],
    this.routePoints = const <LatLng>[],
    this.routeColor,
    this.showControls = true,
    this.fitToMarkers = true,
    this.showUserLocation = true,
    this.showLocationButton = true,
    this.showRecenterButton = false,
    this.onLocationButtonPressed,
    this.controlsBottomOffset = 42,
    this.attributionBottomOffset = 16,
    this.controlsBackgroundColor,
    this.controlsIconColor,
    this.mapController,
    this.showStandaloneLocationButton = false,
    this.locationButtonBottomOffset = 16,
  });

  final double? initialLat;
  final double? initialLng;
  final double initialZoom;
  final void Function(double lat, double lng)? onTap;
  final void Function(double lat, double lng)? onCameraMove;
  final VoidCallback? onCameraEnd;
  final VoidCallback? onRecenter;
  final List<EvikMapMarker> markers;
  final List<LatLng> routePoints;
  final Color? routeColor;
  final bool showControls;
  final bool fitToMarkers;
  final bool showUserLocation;
  final bool showLocationButton;
  final bool showRecenterButton;
  final void Function(double lat, double lng, String address)?
      onLocationButtonPressed;
  final double controlsBottomOffset;
  final double attributionBottomOffset;
  final Color? controlsBackgroundColor;
  final Color? controlsIconColor;

  /// Optional externally-owned map controller. When omitted the view creates
  /// its own internal controller (ownership stays with the caller of this
  /// parameter).
  final MapController? mapController;

  /// Standalone round "my location" button at the right edge, independent of
  /// the zoom/control cluster (which needs [showControls]).
  final bool showStandaloneLocationButton;

  /// Bottom offset (from the view's bottom edge) of the standalone button.
  final double locationButtonBottomOffset;

  @override
  State<EvikOsmMapView> createState() => _EvikOsmMapViewState();
}

class _EvikOsmMapViewState extends State<EvikOsmMapView> {
  late final MapController _mapController;
  bool _isLocating = false;
  bool _userInteracted = false;
  StreamSubscription<Position>? _userLocationSubscription;
  LatLng? _userLocation;
  bool _locationErrorShown = false;

  LatLng get _initialCenter => LatLng(
        widget.initialLat ?? AppConstants.makhachkalaLat,
        widget.initialLng ?? AppConstants.makhachkalaLng,
      );

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();
    if (widget.showUserLocation) _subscribeToUserLocation();
  }

  @override
  void didUpdateWidget(covariant EvikOsmMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeLenChanged = widget.routePoints.length != oldWidget.routePoints.length;
    if (routeLenChanged) {
      debugPrint('[MAPVIEW] routePoints changed: ${oldWidget.routePoints.length} → ${widget.routePoints.length}');
      if (widget.routePoints.length >= 2) {
        debugPrint('[MAPVIEW] PolylineLayer WILL render (${widget.routePoints.length} points, color: ${widget.routeColor})');
      } else {
        debugPrint('[MAPVIEW] PolylineLayer NOT rendered — need >=2 points, got ${widget.routePoints.length}');
      }
    }
    if (widget.showUserLocation != oldWidget.showUserLocation) {
      if (widget.showUserLocation) {
        _subscribeToUserLocation();
      } else {
        _unsubscribeFromUserLocation();
      }
    }
    final centerChanged = widget.initialLat != oldWidget.initialLat ||
        widget.initialLng != oldWidget.initialLng ||
        widget.initialZoom != oldWidget.initialZoom;
    if (centerChanged && !widget.fitToMarkers) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(_initialCenter, _mapController.camera.zoom);
      });
      return;
    }

    if (widget.fitToMarkers &&
        (widget.markers != oldWidget.markers ||
            widget.routePoints != oldWidget.routePoints)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitCamera());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AvroClientColors.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: widget.initialZoom,
                minZoom: 3,
                maxZoom: 19,
                onMapReady: () {
                  if (widget.fitToMarkers) _fitCamera();
                },
                onTap: (_, latLng) {
                  widget.onTap?.call(latLng.latitude, latLng.longitude);
                },
                onPositionChanged: (camera, hasGesture) {
                  if (!hasGesture) return;
                  final center = camera.center;
                  widget.onCameraMove?.call(
                    center.latitude,
                    center.longitude,
                  );
                },
                onMapEvent: (event) {
                  if (event is MapEventMoveStart &&
                          event.source == MapEventSource.dragStart ||
                      event is MapEventDoubleTapZoom ||
                      event is MapEventScrollWheelZoom) {
                    _userInteracted = true;
                  }
                  if (event is MapEventMoveEnd ||
                      event is MapEventFlingAnimationEnd) {
                    widget.onCameraEnd?.call();
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConstants.openStreetMapTileUrl,
                  userAgentPackageName: 'com.avro.app',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  maxZoom: 19,
                ),
                if (widget.routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.routePoints,
                        color: widget.routeColor ?? AvroClientColors.accent,
                        strokeWidth: 3,
                        borderColor: AvroClientColors.background,
                        borderStrokeWidth: 1.5,
                        strokeCap: StrokeCap.round,
                        strokeJoin: StrokeJoin.round,
                      ),
                    ],
                  ),
                if (_userLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _userLocation!,
                        width: PulsingLocationDot.size,
                        height: PulsingLocationDot.size,
                        alignment: Alignment.center,
                        child: const PulsingLocationDot(),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: widget.markers
                      .map(
                        (marker) {
                          final isCustom = marker.child != null;
                          return Marker(
                            point: LatLng(marker.lat, marker.lng),
                            width: isCustom ? 56 : 48,
                            height: isCustom ? 56 : 56,
                            alignment: isCustom ? Alignment.center : Alignment.topCenter,
                            child: _AnimatedMapMarker(marker: marker),
                          );
                        },
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
          if (widget.showControls)
            Positioned(
              right: 16,
              bottom: widget.controlsBottomOffset,
              child: _MapControls(
                showLocationButton: widget.showLocationButton,
                showRecenterButton: widget.showRecenterButton,
                isLocating: _isLocating,
                backgroundColor: widget.controlsBackgroundColor,
                iconColor: widget.controlsIconColor,
                onLocate: _moveToCurrentLocation,
                onRecenter: _recenterMap,
                onZoomIn: () => _mapController.move(
                  _mapController.camera.center,
                  (_mapController.camera.zoom + 1).clamp(3, 19),
                ),
                onZoomOut: () => _mapController.move(
                  _mapController.camera.center,
                  (_mapController.camera.zoom - 1).clamp(3, 19),
                ),
              ),
            ),
          if (widget.showStandaloneLocationButton)
            Positioned(
              right: 16,
              bottom: widget.locationButtonBottomOffset,
              child: _StandaloneLocationButton(
                onPressed: _centerOnMyPosition,
              ),
            ),
          Positioned(
            right: 16,
            bottom: widget.attributionBottomOffset,
            child: const Text(
              AppConstants.openStreetMapAttribution,
              style: TextStyle(color: AvroClientColors.textSecondary, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _unsubscribeFromUserLocation();
    super.dispose();
  }

  void _subscribeToUserLocation() {
    _userLocationSubscription?.cancel();
    _userLocationSubscription =
        LocationService.instance.getLocationStream().listen(
      (position) {
        if (!mounted) return;
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('EvikOsmMapView: ошибка потока геолокации: $error');
        if (!mounted || _locationErrorShown) return;
        _locationErrorShown = true;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Не удалось определить ваше местоположение'),
          ),
        );
      },
    );
  }

  void _unsubscribeFromUserLocation() {
    _userLocationSubscription?.cancel();
    _userLocationSubscription = null;
  }

  Future<void> _moveToCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final location = await OpenStreetMapService.getCurrentLocation();
      if (!mounted || location == null) return;
      final point = LatLng(location.latitude, location.longitude);
      _mapController.move(point, 17);
      widget.onLocationButtonPressed?.call(
        location.latitude,
        location.longitude,
        location.address,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Не удалось определить местоположение'),
          backgroundColor: AvroClientColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _recenterMap() {
    _userInteracted = false;
    _fitCamera();
    widget.onRecenter?.call();
  }

  /// Centers the camera on the position currently represented by the map
  /// (initialLat/initialLng — i.e. the client's known position) without
  /// issuing a new GPS request.
  void _centerOnMyPosition() {
    _mapController.move(_initialCenter, 17);
    widget.onRecenter?.call();
  }

  void _fitCamera() {
    if (!mounted || _userInteracted) return;
    final points = <LatLng>[
      ...widget.routePoints,
      ...widget.markers.map((marker) => LatLng(marker.lat, marker.lng)),
    ];
    if (points.length < 2) {
      if (points.length == 1) {
        _mapController.move(points.first, _mapController.camera.zoom);
      }
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(42),
      ),
    );
  }
}

/// Standalone round "my location" button used on screens that do not show the
/// zoom/control cluster (e.g. the client home screen).
class _StandaloneLocationButton extends StatelessWidget {
  const _StandaloneLocationButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: AvroClientColors.background.withValues(alpha: 0.96),
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        child: IconButton(
          tooltip: 'Моё местоположение',
          onPressed: onPressed,
          icon: const Icon(Icons.my_location_rounded),
          color: AvroClientColors.accent,
          iconSize: 22,
        ),
      ),
    );
  }
}

class _AnimatedMapMarker extends StatelessWidget {  const _AnimatedMapMarker({required this.marker});

  final EvikMapMarker marker;

  @override
  Widget build(BuildContext context) {
    if (marker.child != null) {
      return marker.child!;
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey('${marker.title}-${marker.lat}-${marker.lng}'),
      tween: Tween<double>(begin: 0.88, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Tooltip(
        message: marker.title ?? '',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: marker.color,
                shape: BoxShape.circle,
                border: Border.all(color: AvroClientColors.background, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                marker.icon ?? Icons.location_on,
                color: AvroClientColors.background,
                size: 18,
              ),
            ),
            Container(
              width: 3,
              height: 14,
              color: marker.color,
            ),
          ],
        ),
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.showLocationButton,
    required this.showRecenterButton,
    required this.isLocating,
    required this.backgroundColor,
    required this.iconColor,
    required this.onLocate,
    required this.onRecenter,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final bool showLocationButton;
  final bool showRecenterButton;
  final bool isLocating;
  final Color? backgroundColor;
  final Color? iconColor;
  final VoidCallback onLocate;
  final VoidCallback onRecenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLocationButton) ...[
          _MapControlButton(
            tooltip: 'Показать геолокацию',
            backgroundColor: backgroundColor,
            iconColor: iconColor,
            onPressed: isLocating ? null : onLocate,
            child: isLocating
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: iconColor ?? AvroClientColors.accent,
                    ),
                  )
                : const Icon(Icons.navigation_rounded),
          ),
          const SizedBox(height: 10),
        ],
        if (showRecenterButton) ...[
          _MapControlButton(
            tooltip: 'Вернуться к маршруту',
            backgroundColor: backgroundColor,
            iconColor: iconColor,
            onPressed: onRecenter,
            child: const Icon(Icons.fit_screen_rounded),
          ),
          const SizedBox(height: 10),
        ],
        _ZoomControls(
          backgroundColor: backgroundColor,
          iconColor: iconColor,
          onZoomIn: onZoomIn,
          onZoomOut: onZoomOut,
        ),
      ],
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.backgroundColor,
    required this.iconColor,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final Color? backgroundColor;
  final Color? iconColor;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: (backgroundColor ?? AvroClientColors.background)
            .withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          color: iconColor ?? AvroClientColors.textPrimary,
          icon: child,
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.backgroundColor,
    required this.iconColor,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final Color? backgroundColor;
  final Color? iconColor;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (backgroundColor ?? AvroClientColors.background)
            .withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Увеличить',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded),
            color: iconColor ?? AvroClientColors.textPrimary,
          ),
          const SizedBox(height: 1),
          IconButton(
            tooltip: 'Уменьшить',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded),
            color: iconColor ?? AvroClientColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

class EvikMapMarker {
  const EvikMapMarker({
    required this.lat,
    required this.lng,
    this.title,
    this.color = AvroClientColors.accent,
    this.icon,
    this.child,
  });

  final double lat;
  final double lng;
  final String? title;
  final Color color;
  final IconData? icon;
  final Widget? child;
}
