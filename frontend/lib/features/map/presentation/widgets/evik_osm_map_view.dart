import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/openstreetmap_service.dart';
import '../../../../core/theme/evik_colors.dart';

class EvikOsmMapView extends StatefulWidget {
  const EvikOsmMapView({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialZoom = 14,
    this.onTap,
    this.onCameraMove,
    this.markers = const <EvikMapMarker>[],
    this.routePoints = const <LatLng>[],
    this.showControls = true,
    this.fitToMarkers = true,
    this.showUserLocation = true,
    this.showLocationButton = true,
    this.onLocationButtonPressed,
    this.controlsBottomOffset = 42,
    this.controlsBackgroundColor,
    this.controlsIconColor,
  });

  final double? initialLat;
  final double? initialLng;
  final double initialZoom;
  final void Function(double lat, double lng)? onTap;
  final void Function(double lat, double lng)? onCameraMove;
  final List<EvikMapMarker> markers;
  final List<LatLng> routePoints;
  final bool showControls;
  final bool fitToMarkers;
  final bool showUserLocation;
  final bool showLocationButton;
  final void Function(double lat, double lng, String address)?
      onLocationButtonPressed;
  final double controlsBottomOffset;
  final Color? controlsBackgroundColor;
  final Color? controlsIconColor;

  @override
  State<EvikOsmMapView> createState() => _EvikOsmMapViewState();
}

class _EvikOsmMapViewState extends State<EvikOsmMapView> {
  final MapController _mapController = MapController();
  bool _isLocating = false;

  LatLng get _initialCenter => LatLng(
        widget.initialLat ?? AppConstants.moscowLat,
        widget.initialLng ?? AppConstants.moscowLng,
      );

  @override
  void didUpdateWidget(covariant EvikOsmMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final centerChanged = widget.initialLat != oldWidget.initialLat ||
        widget.initialLng != oldWidget.initialLng ||
        widget.initialZoom != oldWidget.initialZoom;
    if (centerChanged && !widget.fitToMarkers) {
      _mapController.move(_initialCenter, widget.initialZoom);
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
      color: EvikColors.gray100,
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
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConstants.openStreetMapTileUrl,
                  userAgentPackageName: 'com.example.evik_frontend',
                  maxZoom: 19,
                ),
                if (widget.routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.routePoints,
                        color: EvikColors.accent,
                        strokeWidth: 5,
                        borderColor: EvikColors.primaryWhite,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: widget.markers
                      .map(
                        (marker) => Marker(
                          point: LatLng(marker.lat, marker.lng),
                          width: 48,
                          height: 56,
                          alignment: Alignment.topCenter,
                          child: _AnimatedMapMarker(marker: marker),
                        ),
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
                isLocating: _isLocating,
                backgroundColor: widget.controlsBackgroundColor,
                iconColor: widget.controlsIconColor,
                onLocate: _moveToCurrentLocation,
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
          const Positioned(
            right: 16,
            bottom: 16,
            child: Text(
              AppConstants.openStreetMapAttribution,
              style: TextStyle(color: EvikColors.gray600, fontSize: 10),
            ),
          ),
        ],
      ),
    );
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
          backgroundColor: EvikColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _fitCamera() {
    if (!mounted) return;
    final points = <LatLng>[
      ...widget.routePoints,
      ...widget.markers.map((marker) => LatLng(marker.lat, marker.lng)),
    ];
    if (points.length < 2) {
      if (points.length == 1) {
        _mapController.move(points.first, widget.initialZoom);
      }
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(42),
        maxZoom: widget.initialZoom,
      ),
    );
  }
}

class _AnimatedMapMarker extends StatelessWidget {
  const _AnimatedMapMarker({required this.marker});

  final EvikMapMarker marker;

  @override
  Widget build(BuildContext context) {
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
                border: Border.all(color: EvikColors.primaryWhite, width: 3),
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
                color: EvikColors.primaryWhite,
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
    required this.isLocating,
    required this.backgroundColor,
    required this.iconColor,
    required this.onLocate,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final bool showLocationButton;
  final bool isLocating;
  final Color? backgroundColor;
  final Color? iconColor;
  final VoidCallback onLocate;
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
                      color: iconColor ?? EvikColors.accentOrange,
                    ),
                  )
                : const Icon(Icons.navigation_rounded),
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
        color: (backgroundColor ?? EvikColors.primaryWhite)
            .withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          color: iconColor ?? EvikColors.primaryBlack,
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
        color: (backgroundColor ?? EvikColors.primaryWhite)
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
            color: iconColor ?? EvikColors.primaryBlack,
          ),
          const SizedBox(height: 1),
          IconButton(
            tooltip: 'Уменьшить',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded),
            color: iconColor ?? EvikColors.primaryBlack,
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
    this.color = EvikColors.accentOrange,
    this.icon,
  });

  final double lat;
  final double lng;
  final String? title;
  final Color color;
  final IconData? icon;
}
