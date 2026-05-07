import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/evik_colors.dart';

class ProMapsViewSimple extends StatefulWidget {
  const ProMapsViewSimple({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialZoom = 14,
    this.onTap,
    this.markers = const <ProMapMarker>[],
    this.showControls = true,
  });

  final double? initialLat;
  final double? initialLng;
  final double initialZoom;
  final void Function(double lat, double lng)? onTap;
  final List<ProMapMarker> markers;
  final bool showControls;

  @override
  State<ProMapsViewSimple> createState() => _ProMapsViewSimpleState();
}

class _ProMapsViewSimpleState extends State<ProMapsViewSimple> {
  static const String _apiKey = AppConstants.promapsMapsApiKey;
  static const double _tileSize = 256;
  static const double _maxMercatorLat = 85.05112878;

  late double _currentLat;
  late double _currentLng;
  late double _currentZoom;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLat ?? AppConstants.moscowLat;
    _currentLng = widget.initialLng ?? AppConstants.moscowLng;
    _currentZoom = widget.initialZoom;
  }

  @override
  void didUpdateWidget(covariant ProMapsViewSimple oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextLat = widget.initialLat ?? _currentLat;
    final nextLng = widget.initialLng ?? _currentLng;
    if (nextLat != oldWidget.initialLat ||
        nextLng != oldWidget.initialLng ||
        widget.initialZoom != oldWidget.initialZoom) {
      _currentLat = nextLat;
      _currentLng = nextLng;
      _currentZoom = widget.initialZoom;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return ColoredBox(
          color: EvikColors.gray100,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTapUp: _handleTap,
                  child: CachedNetworkImage(
                    imageUrl: _tileUrl(),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const ColoredBox(
                      color: EvikColors.gray100,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) =>
                        const _ProMapsUnavailableState(),
                  ),
                ),
              ),
              ...widget.markers.map((marker) {
                final point = _projectMarker(marker, size);
                return Positioned(
                  left: point.dx - 9,
                  top: point.dy - 9,
                  child: Tooltip(
                    message: marker.title ?? '',
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: marker.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: EvikColors.primaryWhite,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (widget.showControls)
                Positioned(
                  right: 16,
                  bottom: 42,
                  child: _ZoomControls(
                    onZoomIn: _zoomIn,
                    onZoomOut: _zoomOut,
                  ),
                ),
              const Positioned(
                right: 16,
                bottom: 16,
                child: Text(
                  '© ProMaps',
                  style: TextStyle(color: EvikColors.gray600, fontSize: 10),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _tileUrl() {
    final zoom = _currentZoom.round().clamp(1, 18);
    final tiles = 1 << zoom;
    final x = _lonToTileX(_currentLng, zoom) % tiles;
    final y = _latToTileY(_currentLat, zoom).clamp(0, tiles - 1);
    return '${AppConstants.promapsBaseUrl}/tiles/default/$zoom/$x/$y.png?key=$_apiKey';
  }

  int _lonToTileX(double lon, int zoom) {
    final normalizedLon = ((lon + 180) % 360 + 360) % 360 - 180;
    return (((normalizedLon + 180) / 360) * (1 << zoom)).floor();
  }

  int _latToTileY(double lat, int zoom) {
    final clampedLat = lat.clamp(-_maxMercatorLat, _maxMercatorLat);
    final latRad = clampedLat * math.pi / 180;
    final n = math.pi - math.log(math.tan(math.pi / 4 + latRad / 2));
    return ((n / (2 * math.pi)) * (1 << zoom)).floor();
  }

  void _handleTap(TapUpDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      widget.onTap?.call(_currentLat, _currentLng);
      return;
    }

    final size = box.size;
    final zoom = _currentZoom.round().clamp(1, 18);
    final center = _latLngToWorld(_currentLat, _currentLng, zoom);
    final tapped = Offset(
      center.dx + details.localPosition.dx - size.width / 2,
      center.dy + details.localPosition.dy - size.height / 2,
    );
    final latLng = _worldToLatLng(tapped, zoom);
    widget.onTap?.call(latLng.$1, latLng.$2);
  }

  void _zoomIn() {
    if (_currentZoom < 18) {
      setState(() => _currentZoom += 1);
    }
  }

  void _zoomOut() {
    if (_currentZoom > 1) {
      setState(() => _currentZoom -= 1);
    }
  }

  Offset _projectMarker(ProMapMarker marker, Size size) {
    final zoom = _currentZoom.round().clamp(1, 18);
    final center = _latLngToWorld(_currentLat, _currentLng, zoom);
    final point = _latLngToWorld(marker.lat, marker.lng, zoom);
    final dx = point.dx - center.dx + size.width / 2;
    final dy = point.dy - center.dy + size.height / 2;
    return Offset(
      dx.clamp(8.0, size.width - 8.0),
      dy.clamp(8.0, size.height - 8.0),
    );
  }

  Offset _latLngToWorld(double lat, double lng, int zoom) {
    final scale = (1 << zoom) * _tileSize;
    final clampedLat = lat.clamp(-_maxMercatorLat, _maxMercatorLat);
    final sinLat = math.sin(clampedLat * math.pi / 180);
    final x = ((lng + 180) / 360) * scale;
    final y =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
    return Offset(x, y);
  }

  (double lat, double lng) _worldToLatLng(Offset point, int zoom) {
    final scale = (1 << zoom) * _tileSize;
    final lng = (point.dx / scale) * 360 - 180;
    final n = math.pi - 2 * math.pi * point.dy / scale;
    final sinhN = (math.exp(n) - math.exp(-n)) / 2;
    final lat = (180 / math.pi) * math.atan(sinhN);
    return (lat.clamp(-_maxMercatorLat, _maxMercatorLat), lng.clamp(-180, 180));
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite.withValues(alpha: 0.96),
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
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded),
            color: EvikColors.primaryBlack,
          ),
          const SizedBox(height: 1),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded),
            color: EvikColors.primaryBlack,
          ),
        ],
      ),
    );
  }
}

class _ProMapsUnavailableState extends StatelessWidget {
  const _ProMapsUnavailableState();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EvikColors.gray100,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: EvikColors.primaryWhite.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EvikColors.gray200),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                color: EvikColors.primaryBlack,
                size: 32,
              ),
              SizedBox(height: 8),
              Text(
                'ProMaps недоступна',
                style: TextStyle(
                  color: EvikColors.primaryBlack,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Проверьте ключ или endpoint карты',
                style: TextStyle(color: EvikColors.gray600, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProMapMarker {
  const ProMapMarker({
    required this.lat,
    required this.lng,
    this.title,
    this.color = EvikColors.accentOrange,
  });

  final double lat;
  final double lng;
  final String? title;
  final Color color;
}
