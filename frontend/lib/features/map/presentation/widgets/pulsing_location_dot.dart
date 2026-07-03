import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;

/// Green pulsing dot marking the user's live location on a map.
class PulsingLocationDot extends StatefulWidget {
  const PulsingLocationDot({super.key});

  static const Color color = AvroClientColors.success;
  static const double dotSize = 14;
  static const double haloSize = 32;

  @override
  State<PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<PulsingLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scale = Tween<double>(begin: 1, end: 1.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Уважаем системную настройку "уменьшить движение": показываем
    // статичную точку вместо бесконечной пульсации.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
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

    final halo = Container(
      width: PulsingLocationDot.haloSize,
      height: PulsingLocationDot.haloSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: PulsingLocationDot.color.withValues(alpha: 0.25),
      ),
    );

    return Center(
      child: SizedBox(
        width: PulsingLocationDot.haloSize,
        height: PulsingLocationDot.haloSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (reduceMotion)
              halo
            else
              ScaleTransition(scale: _scale, child: halo),
            Container(
              width: PulsingLocationDot.dotSize,
              height: PulsingLocationDot.dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PulsingLocationDot.color,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
