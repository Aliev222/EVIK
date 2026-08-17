import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;

/// Green pulsing dot marking the user's live location on a map.
///
/// Radar-pulse style: a solid green dot with a soft glow and [waveCount]
/// expanding rings that fade out as they grow. Driven by a single
/// [AnimationController] feeding a [CustomPainter] (no per-tick setState),
/// wrapped in a [RepaintBoundary] so the animation never repaints the whole
/// map layer.
class PulsingLocationDot extends StatefulWidget {
  const PulsingLocationDot({super.key});

  static const Color color = AvroClientColors.success;
  static const double dotSize = 14;
  static const double haloSize = 32;
  /// Full widget footprint: dot + glow + radar waves.
  static const double size = 56;
  static const int waveCount = 3;

  @override
  State<PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<PulsingLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Уважаем системную настройку "уменьшить движение": показываем
    // статичную точку без волн вместо бесконечной пульсации.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return RepaintBoundary(
      child: Center(
        child: SizedBox.square(
          dimension: PulsingLocationDot.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _RadarPulsePainter(
                progress: _controller.value,
                wavesEnabled: !reduceMotion,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPulsePainter extends CustomPainter {
  const _RadarPulsePainter({
    required this.progress,
    required this.wavesEnabled,
  });

  /// Animation clock in 0..1, loops forever.
  final double progress;

  /// When false (reduce-motion), only the dot and glow are painted.
  final bool wavesEnabled;

  static const double _centerDotRadius = PulsingLocationDot.dotSize / 2;
  static const double _maxWaveRadius = PulsingLocationDot.size / 2 - 4;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    if (wavesEnabled) {
      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < PulsingLocationDot.waveCount; i++) {
        final phase = (progress - i / PulsingLocationDot.waveCount) % 1.0;
        final radius = _centerDotRadius + phase * _maxWaveRadius;
        wavePaint.color =
            PulsingLocationDot.color.withValues(alpha: (1 - phase) * 0.4);
        canvas.drawCircle(center, radius, wavePaint);
      }
    }

    // Soft glow behind the dot.
    canvas.drawCircle(
      center,
      _centerDotRadius + 5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            PulsingLocationDot.color.withValues(alpha: 0.35),
            PulsingLocationDot.color.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: center,
            radius: _centerDotRadius + 5,
          ),
        ),
    );

    // Solid center dot.
    canvas.drawCircle(
      center,
      _centerDotRadius,
      Paint()..color = PulsingLocationDot.color,
    );

    // Thin white ring keeps the dot visible on any map background.
    canvas.drawCircle(
      center,
      _centerDotRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPulsePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.wavesEnabled != wavesEnabled;
  }
}
