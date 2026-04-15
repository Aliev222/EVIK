import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/evik_colors.dart';

class YandexMapView extends StatelessWidget {
  const YandexMapView({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialZoom = 14,
    this.onMapCreated,
  });

  final double? initialLat;
  final double? initialLng;
  final double initialZoom;
  final ValueChanged<int>? onMapCreated;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Container(
        decoration:
            const BoxDecoration(gradient: EvikColors.mapFallbackGradient),
        child: CustomPaint(
          painter: _MapFallbackPainter(),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: EvikColors.surfaceDark.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: EvikColors.borderDark),
              ),
              child: const Text(
                'Предпросмотр карты',
                style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AndroidView(
      viewType: 'evik/yandex_map_view',
      onPlatformViewCreated: onMapCreated,
      creationParamsCodec: const StandardMessageCodec(),
      creationParams: <String, dynamic>{
        'initialLat': initialLat,
        'initialLng': initialLng,
        'initialZoom': initialZoom,
      },
    );
  }
}

class _MapFallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF303030).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (double y = -40; y < size.height + 40; y += 36) {
      final path = Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(size.width * 0.25, y + 10, size.width, y - 10);
      canvas.drawPath(path, paint);
    }

    for (double x = -40; x < size.width + 40; x += 48) {
      final path = Path()
        ..moveTo(x, 0)
        ..quadraticBezierTo(x - 14, size.height * 0.35, x + 8, size.height);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
