import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../map/presentation/widgets/evik_map_widget.dart';
import '../../../order/domain/entities/order_flow_state.dart';
import '../providers/order_flow_provider.dart';

class DriverSearchScreen extends ConsumerStatefulWidget {
  const DriverSearchScreen({super.key});

  @override
  ConsumerState<DriverSearchScreen> createState() => _DriverSearchScreenState();
}

class _DriverSearchScreenState extends ConsumerState<DriverSearchScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isNavigatingToDriverInfo = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _cancelSearch() {
    ref.read(orderFlowProvider.notifier).cancelSearch();
    context.go('/');
  }

  void _goToDriverInfo() {
    if (_isNavigatingToDriverInfo) return;
    _isNavigatingToDriverInfo = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/order/driver-info');
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderFlowState = ref.watch(orderFlowProvider);
    final searchTimer = ref.watch(searchTimerDisplayProvider);

    if (orderFlowState.currentStep == OrderFlowStep.driverFound) {
      _goToDriverInfo();
    }

    // Listen for navigation to next screen when driver is found
    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.driverFound &&
          previous?.currentStep != OrderFlowStep.driverFound) {
        _goToDriverInfo();
      }

      if (next.errorMessage != null &&
          previous?.errorMessage != next.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: EvikColors.errorRed,
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () {
                ref.read(orderFlowProvider.notifier).goToDriverSearch();
              },
            ),
          ),
        );
        ref.read(orderFlowProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        backgroundColor: EvikColors.gray50,
        title: Text(
          'Поиск водителя',
          style: EvikTypography.h2.copyWith(color: EvikColors.primaryBlack),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: EvikColors.primaryBlack),
          onPressed: _cancelSearch,
        ),
      ),
      body: Stack(
        children: [
          // Map background
          if (orderFlowState.pickupLocation != null)
            const Positioned.fill(
              child: EvikMapWidget(
                isSelectionMode: false,
              ),
            ),

          // Search animation overlay
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: SearchPulsePainter(
                    animationValue: _pulseAnimation.value,
                    center: Offset(
                      MediaQuery.of(context).size.width * 0.5,
                      MediaQuery.of(context).size.height * 0.4,
                    ),
                  ),
                );
              },
            ),
          ),

          // Search info panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: EvikColors.primaryWhite,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: EvikColors.gray300.withValues(alpha: 0.5),
                    offset: const Offset(0, -4),
                    blurRadius: 12,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search status
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: EvikColors.accentOrange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ищем свободного водителя...',
                            style: EvikTypography.h3.copyWith(
                              color: EvikColors.primaryBlack,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Search timer
                    Text(
                      searchTimer,
                      style: EvikTypography.bodyLarge.copyWith(
                        color: EvikColors.accentOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Order summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: EvikColors.gray50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryRow(
                            'Автомобиль',
                            orderFlowState.selectedVehicleType?.displayName ??
                                'Не выбран',
                            Icons.directions_car,
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Эвакуатор',
                            orderFlowState.selectedTowTruckType?.displayName ??
                                'Не выбран',
                            Icons.local_shipping,
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Расстояние',
                            '${orderFlowState.distance.toStringAsFixed(1)} км',
                            Icons.route,
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Стоимость',
                            '${orderFlowState.estimatedPrice.round()} ₽',
                            Icons.payment,
                            valueColor: EvikColors.accentOrange,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Cancel button
                    SizedBox(
                      width: double.infinity,
                      child: EvikButton(
                        text: 'Отменить поиск',
                        onPressed: _cancelSearch,
                        variant: EvikButtonVariant.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: EvikColors.gray500),
        const SizedBox(width: 8),
        Text(
          label,
          style: EvikTypography.bodySmall.copyWith(
            color: EvikColors.gray600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: EvikTypography.bodyMedium.copyWith(
            color: valueColor ?? EvikColors.primaryBlack,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class SearchPulsePainter extends CustomPainter {
  const SearchPulsePainter({
    required this.animationValue,
    required this.center,
  });

  final double animationValue;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          EvikColors.accentOrange.withValues(alpha: 0.3 * (1 - animationValue))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw multiple expanding circles
    for (int i = 0; i < 3; i++) {
      final radius = 30.0 + (animationValue * 80.0) + (i * 20.0);
      final alpha = (0.3 * (1 - animationValue)) - (i * 0.1);

      if (alpha > 0) {
        paint.color =
            EvikColors.accentOrange.withValues(alpha: alpha.clamp(0.0, 1.0));
        canvas.drawCircle(center, radius, paint);
      }
    }

    // Draw center point
    final centerPaint = Paint()
      ..color = EvikColors.accentOrange
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8.0, centerPaint);
  }

  @override
  bool shouldRepaint(SearchPulsePainter oldDelegate) {
    return animationValue != oldDelegate.animationValue;
  }
}
