import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../order/domain/entities/order_flow_state.dart';
import '../providers/order_flow_provider.dart';

class DriverInfoScreen extends ConsumerWidget {
  const DriverInfoScreen({super.key});

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _sendMessage(String phoneNumber) async {
    final Uri url = Uri.parse('sms:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _goToTracking(BuildContext context, WidgetRef ref) {
    ref.read(orderFlowProvider.notifier).goToTracking();
    context.go('/order/tracking');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderFlowState = ref.watch(orderFlowProvider);
    final driver = orderFlowState.assignedDriver;
    // final order = orderFlowState.activeOrder; // Unused for now

    // Listen for navigation to tracking when driver starts moving
    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.tracking &&
          previous?.currentStep != OrderFlowStep.tracking) {
        context.go('/order/tracking');
      }
    });

    if (driver == null) {
      return Scaffold(
        backgroundColor: EvikColors.gray50,
        appBar: AppBar(
          backgroundColor: EvikColors.gray50,
          title: Text(
            'Водитель не найден',
            style: EvikTypography.h2.copyWith(color: EvikColors.primaryBlack),
          ),
          centerTitle: true,
        ),
        body: const Center(
          child: Text('Информация о водителе недоступна'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        backgroundColor: EvikColors.gray50,
        title: Text(
          'Водитель найден!',
          style: EvikTypography.h2.copyWith(color: EvikColors.primaryBlack),
        ),
        centerTitle: true,
        leading: Container(), // Remove back button - can't go back
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Success banner
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    EvikColors.successGreen.withValues(alpha: 0.1),
                    EvikColors.accentOrange.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EvikColors.successGreen, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: EvikColors.successGreen,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Эвакуатор уже в пути к вам!',
                      style: EvikTypography.bodyLarge.copyWith(
                        color: EvikColors.primaryBlack,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Driver card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: EvikColors.primaryWhite,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: EvikColors.gray300.withValues(alpha: 0.3),
                            offset: const Offset(0, 4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Driver avatar
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: EvikColors.gray100,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: EvikColors.accentOrange,
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 34,
                              color: EvikColors.gray400,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Driver name and rating
                          Text(
                            'Водитель EVIK',
                            style: EvikTypography.h3.copyWith(
                              color: EvikColors.primaryBlack,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ...List.generate(5, (index) {
                                return Icon(
                                  index < driver.rating.floor()
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: EvikColors.accentOrange,
                                  size: 16,
                                );
                              }),
                              const SizedBox(width: 8),
                              Text(
                                '${driver.rating.toStringAsFixed(1)} • ${driver.totalOrders} поездок',
                                style: EvikTypography.bodySmall.copyWith(
                                  color: EvikColors.gray600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Vehicle info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: EvikColors.primaryWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: EvikColors.gray200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Эвакуатор',
                            style: EvikTypography.bodySmall.copyWith(
                              color: EvikColors.gray600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                width: 60,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: EvikColors.gray100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.local_shipping,
                                  color: EvikColors.gray400,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      driver.vehicleNumber,
                                      style: EvikTypography.h3.copyWith(
                                        color: EvikColors.primaryBlack,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      driver.vehicleModel,
                                      style: EvikTypography.bodySmall.copyWith(
                                        color: EvikColors.gray600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ETA
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: EvikColors.accentOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: EvikColors.accentOrange),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            color: EvikColors.accentOrange,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Время прибытия',
                                  style: EvikTypography.bodySmall.copyWith(
                                    color: EvikColors.gray600,
                                  ),
                                ),
                                Text(
                                  '10-15 минут',
                                  style: EvikTypography.h3.copyWith(
                                    color: EvikColors.accentOrange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Contact buttons
                    Row(
                      children: [
                        Expanded(
                          child: EvikButton(
                            text: 'Позвонить',
                            onPressed: () => _makePhoneCall('+7(999)123-45-67'),
                            variant: EvikButtonVariant.secondary,
                            icon: const Icon(Icons.phone, size: 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: EvikButton(
                            text: 'Написать',
                            onPressed: () => _sendMessage('+7(999)123-45-67'),
                            variant: EvikButtonVariant.ghost,
                            icon: const Icon(Icons.message, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Track button
                    SizedBox(
                      width: double.infinity,
                      child: EvikButton(
                        text: 'Отследить на карте',
                        onPressed: () => _goToTracking(context, ref),
                        variant: EvikButtonVariant.primary,
                        icon: const Icon(Icons.map, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Order summary
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: EvikColors.gray50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Детали заказа',
                              style: EvikTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildDetailRow(
                              'Тип автомобиля',
                              orderFlowState.selectedVehicleType?.displayName ??
                                  'Не указан',
                            ),
                            _buildDetailRow(
                              'Тип эвакуатора',
                              orderFlowState
                                      .selectedTowTruckType?.displayName ??
                                  'Не указан',
                            ),
                            _buildDetailRow(
                              'Расстояние',
                              '${orderFlowState.distance.toStringAsFixed(1)} км',
                            ),
                            _buildDetailRow(
                              'Стоимость',
                              '${orderFlowState.estimatedPrice.round()} ₽',
                              valueColor: EvikColors.accentOrange,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: EvikTypography.bodySmall.copyWith(
              color: EvikColors.gray600,
            ),
          ),
          Text(
            value,
            style: EvikTypography.bodySmall.copyWith(
              color: valueColor ?? EvikColors.primaryBlack,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
