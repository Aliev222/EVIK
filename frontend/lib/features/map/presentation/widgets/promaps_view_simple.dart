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
                  style: TextStyle(
                    color: EvikColors.gray600,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _tileUrl() {
    final zoom = _currentZoom.round();
    final x = _lonToTileX(_currentLng, zoom);
    final y = _latToTileY(_currentLat, zoom);
    return '${AppConstants.promapsBaseUrl}/tiles/default/$zoom/$x/$y.png?key=$_apiKey';
  }

  int _lonToTileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  int _latToTileY(double lat, int zoom) {
    return ((90.0 - lat) / 180.0 * (1 << zoom)).floor();
  }

  void _handleTap(TapUpDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      widget.onTap?.call(_currentLat, _currentLng);
      return;
    }

    final size = box.size;
    final zoom = _currentZoom.round();
    final scale = (1 << zoom).toDouble();
    const tileSize = 256.0;
    final centerX = (_currentLng + 180.0) / 360.0 * scale;
    final centerY = (90.0 - _currentLat) / 180.0 * scale;
    final tappedX =
        centerX + ((details.localPosition.dx - size.width / 2) / tileSize);
    final tappedY =
        centerY + ((details.localPosition.dy - size.height / 2) / tileSize);
    final lng = (tappedX / scale * 360.0) - 180.0;
    final lat = 90.0 - (tappedY / scale * 180.0);

    widget.onTap?.call(lat.clamp(-90.0, 90.0), lng.clamp(-180.0, 180.0));
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
    final zoom = _currentZoom.round();
    final scale = (1 << zoom).toDouble();
    final centerX = (_currentLng + 180.0) / 360.0 * scale;
    final centerY = (90.0 - _currentLat) / 180.0 * scale;
    final markerX = (marker.lng + 180.0) / 360.0 * scale;
    final markerY = (90.0 - marker.lat) / 180.0 * scale;
    const tileSize = 256.0;
    final dx = (markerX - centerX) * tileSize + size.width / 2;
    final dy = (markerY - centerY) * tileSize + size.height / 2;
    return Offset(
      dx.clamp(8.0, size.width - 8.0),
      dy.clamp(8.0, size.height - 8.0),
    );
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
                'Карта недоступна',
                style: TextStyle(
                  color: EvikColors.primaryBlack,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Проверьте интернет-соединение',
                style: TextStyle(
                  color: EvikColors.gray600,
                  fontSize: 14,
                ),
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
