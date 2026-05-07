import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/evik_colors.dart';

/// Простая карта ProMaps через тайлы
class ProMapsViewSimple extends StatefulWidget {
  const ProMapsViewSimple({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialZoom = 14,
    this.onTap,
    this.markers = const [],
  });

  final double? initialLat;
  final double? initialLng;
  final double initialZoom;
  final void Function(double lat, double lng)? onTap;
  final List<ProMapMarker> markers;

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
    _currentLat = widget.initialLat ?? 55.7558; // Default Moscow
    _currentLng = widget.initialLng ?? 37.6173;
    _currentZoom = widget.initialZoom;
  }

  String _getTileUrl() {
    // Конвертируем координаты в тайловые координаты
    final zoom = _currentZoom.round();
    final x = _lonToTileX(_currentLng, zoom);
    final y = _latToTileY(_currentLat, zoom);

    return 'https://api.promaps.online/tiles/default/$zoom/$x/$y.png?key=$_apiKey';
  }

  int _lonToTileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  int _latToTileY(double lat, int zoom) {
    // Упрощенная формула для демонстрации
    return ((90.0 - lat) / 180.0 * (1 << zoom)).floor();
  }

  void _handleTap(TapUpDetails details) {
    // Простое приближение координат по тапу
    // В реальной реализации нужно было бы точное преобразование пикселей в координаты
    if (widget.onTap != null) {
      widget.onTap!(_currentLat, _currentLng);
    }
  }

  void _zoomIn() {
    if (_currentZoom < 18) {
      setState(() {
        _currentZoom += 1;
      });
    }
  }

  void _zoomOut() {
    if (_currentZoom > 1) {
      setState(() {
        _currentZoom -= 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: EvikColors.mapFallbackGradient),
      child: Stack(
        children: [
          // Основной тайл карты
          Positioned.fill(
            child: GestureDetector(
              onTapUp: _handleTap,
              child: CachedNetworkImage(
                imageUrl: _getTileUrl(),
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: EvikColors.surfaceDark,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  decoration: const BoxDecoration(gradient: EvikColors.mapFallbackGradient),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: EvikColors.surfaceDark.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: EvikColors.borderDark),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.map_outlined,
                            color: EvikColors.textPrimaryDark,
                            size: 32,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Карта недоступна',
                            style: TextStyle(
                              color: EvikColors.textPrimaryDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Проверьте интернет-соединение',
                            style: TextStyle(
                              color: EvikColors.textSecondaryDark,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Маркеры
          ...widget.markers.map((marker) => Positioned(
            left: 100, // В реальной реализации нужно преобразовать координаты в пиксели
            top: 100,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              width: 12,
              height: 12,
              child: marker.title != null
                  ? Tooltip(
                      message: marker.title!,
                      child: const SizedBox.shrink(),
                    )
                  : null,
            ),
          )),

          // Элементы управления
          Positioned(
            right: 16,
            bottom: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Кнопка приближения
                Container(
                  decoration: BoxDecoration(
                    color: EvikColors.surfaceDark.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: EvikColors.borderDark),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _zoomIn,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.add,
                          color: EvikColors.textPrimaryDark,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                // Кнопка отдаления
                Container(
                  decoration: BoxDecoration(
                    color: EvikColors.surfaceDark.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: EvikColors.borderDark),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _zoomOut,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.remove,
                          color: EvikColors.textPrimaryDark,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Индикатор зума
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: EvikColors.surfaceDark.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EvikColors.borderDark),
              ),
              child: Text(
                'Zoom: ${_currentZoom.toStringAsFixed(1)}',
                style: const TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // ProMaps attribution
          const Positioned(
            right: 16,
            bottom: 16,
            child: Text(
              '© ProMaps',
              style: TextStyle(
                color: EvikColors.textSecondaryDark,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Публичные методы для управления картой
  void setCenter(double lat, double lng) {
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
    });
  }

  void setZoom(double zoom) {
    setState(() {
      _currentZoom = zoom.clamp(1, 18);
    });
  }

  void animateToLocation(double lat, double lng, {double? zoom}) {
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
      if (zoom != null) {
        _currentZoom = zoom.clamp(1, 18);
      }
    });
  }
}

/// Простой маркер для карты
class ProMapMarker {
  final double lat;
  final double lng;
  final String? title;
  final Color color;

  const ProMapMarker({
    required this.lat,
    required this.lng,
    this.title,
    this.color = Colors.red,
  });
}