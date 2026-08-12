import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;

enum ClientTab { home, services, history, profile }

class ClientBottomNav extends StatelessWidget {
  const ClientBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    this.onSosActivated,
  });

  final ClientTab activeTab;
  final ValueChanged<ClientTab> onTabChanged;
  final VoidCallback? onSosActivated;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: AvroClientColors.background,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            _NavItem(
              tab: ClientTab.home,
              activeTab: activeTab,
              icon: Icons.home_rounded,
              label: 'Главная',
              onTap: onTabChanged,
            ),
            _NavItem(
              tab: ClientTab.services,
              activeTab: activeTab,
              icon: Icons.grid_view_rounded,
              label: 'Услуги',
              onTap: onTabChanged,
            ),
            _SosNavButton(onActivated: onSosActivated),
            _NavItem(
              tab: ClientTab.history,
              activeTab: activeTab,
              icon: Icons.receipt_long_rounded,
              label: 'Заказы',
              onTap: onTabChanged,
            ),
            _NavItem(
              tab: ClientTab.profile,
              activeTab: activeTab,
              icon: Icons.person_rounded,
              label: 'Профиль',
              onTap: onTabChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.activeTab,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final ClientTab tab;
  final ClientTab activeTab;
  final IconData icon;
  final String label;
  final ValueChanged<ClientTab> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = tab == activeTab;
    final color = isActive ? AvroClientColors.accent : AvroClientColors.textSecondary;

    return Expanded(
      child: SizedBox(
        height: 72,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              try { HapticFeedback.selectionClick(); } catch (_) {}
              onTap(tab);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 23, color: color),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Center navbar SOS button. A quick tap never dials. Holding for 3 seconds
/// fills the progress ring and activates the SOS screen. Releasing early
/// cancels the hold with no activation. The hold is driven by raw pointer
/// events (Listener) so tiny finger movement during the hold does not cancel
/// the gesture and it never competes in the tap gesture arena.
class _SosNavButton extends StatefulWidget {
  const _SosNavButton({this.onActivated});

  final VoidCallback? onActivated;

  @override
  State<_SosNavButton> createState() => _SosNavButtonState();
}

class _SosNavButtonState extends State<_SosNavButton>
    with SingleTickerProviderStateMixin {
  static const Duration _holdDuration = Duration(seconds: 3);

  late final AnimationController _holdController;
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: _holdDuration,
    )..addStatusListener(_onHoldStatus);
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _activate();
    }
  }

  void _activate() {
    if (_activated) return;
    _activated = true;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
    widget.onActivated?.call();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _holdController.reset();
      _activated = false;
    });
  }

  void _onHoldStart() {
    if (_activated) return;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
    if (!_holdController.isAnimating) {
      _holdController.forward(from: 0);
    }
  }

  void _onHoldEnd() {
    if (_activated) return;
    if (_holdController.isAnimating) {
      _holdController.stop();
    }
    if (!_holdController.isDismissed) {
      _holdController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasHandler = widget.onActivated != null;
    return SizedBox(
      width: 64,
      height: 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: hasHandler ? (_) => _onHoldStart() : null,
              onPointerUp: hasHandler ? (_) => _onHoldEnd() : null,
              onPointerCancel: hasHandler ? (_) => _onHoldEnd() : null,
              child: AnimatedBuilder(
                animation: _holdController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _HoldRingPainter(
                      progress: _holdController.value,
                    ),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AvroClientColors.sosRed,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AvroClientColors.sosRed
                                .withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.phone_in_talk_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'SOS',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AvroClientColors.sosRed,
              letterSpacing: 0.6,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldRingPainter extends CustomPainter {
  const _HoldRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 4.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2 - 1;

    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, basePaint);

    if (progress <= 0) return;

    final progressPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HoldRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
