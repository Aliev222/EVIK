import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/review/domain/entities/review.dart';
import 'package:tow_truck_frontend/features/review/presentation/providers/review_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

class DriverRatingScreen extends ConsumerStatefulWidget {
  const DriverRatingScreen({super.key});

  @override
  ConsumerState<DriverRatingScreen> createState() => _DriverRatingScreenState();
}

class _DriverRatingScreenState extends ConsumerState<DriverRatingScreen> {
  int _rating = 0;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    final orderFlowState = ref.read(orderFlowProvider);
    final order = orderFlowState.activeOrder;
    final driver = orderFlowState.assignedDriver;

    if (order == null || driver == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: данные заказа не найдены'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final request = CreateReviewRequest(
        orderId: order.id,
        driverId: driver.userId,
        stars: _rating,
        text: _commentController.text.trim(),
      );

      await ref.read(reviewRepositoryProvider).createReview(request);

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Спасибо за отзыв!'),
            backgroundColor: AvroClientColors.success,
          ),
        );

        // Reset flow and go to home
        ref.read(orderFlowProvider.notifier).resetFlow();
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Ошибка отправки отзыва';

        if (e.toString().contains('409') || e.toString().contains('already reviewed')) {
          errorMessage = 'Вы уже оставили отзыв по этому заказу';
        } else if (e.toString().contains('403')) {
          errorMessage = 'Нет прав для оставления отзыва';
        } else if (e.toString().contains('400')) {
          errorMessage = 'Некорректные данные отзыва';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _orderAgain() {
    ref.read(orderFlowProvider.notifier).resetFlow();
    context.go('/');
  }

  void _skipRating() {
    ref.read(orderFlowProvider.notifier).resetFlow();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final orderFlowState = ref.watch(orderFlowProvider);
    final driver = orderFlowState.assignedDriver;

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      appBar: AppBar(
        backgroundColor: AvroClientColors.background,
        title: Text(
          'Оценить поездку',
          style: EvikTypography.h2.copyWith(color: AvroClientColors.textPrimary),
        ),
        centerTitle: true,
        leading: Container(), // Remove back button
        actions: [
          TextButton(
            onPressed: _skipRating,
            child: Text(
              'Пропустить',
              style: EvikTypography.bodyMedium.copyWith(
                color: AvroClientColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Success card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AvroClientColors.success.withValues(alpha: 0.1),
                            AvroClientColors.accent.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color:
                                AvroClientColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: AvroClientColors.success
                                  .withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: AvroClientColors.success,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Поездка завершена!',
                            style: EvikTypography.h3.copyWith(
                              color: AvroClientColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ваш автомобиль успешно эвакуирован',
                            style: EvikTypography.bodyMedium.copyWith(
                              color: AvroClientColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Driver card
                    if (driver != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AvroClientColors.background,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AvroClientColors.surface.withValues(alpha: 0.3),
                              offset: const Offset(0, 4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Driver avatar
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: AvroClientColors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AvroClientColors.accent
                                      .withValues(alpha: 0.3),
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.person,
                                size: 36,
                                color: AvroClientColors.tabInactive,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Driver info
                            Text(
                              driver.fullName ?? 'Водитель Авро',
                              style: EvikTypography.h3.copyWith(
                                color: AvroClientColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              driver.vehicleNumber,
                              style: EvikTypography.bodyMedium.copyWith(
                                color: AvroClientColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ...List.generate(5, (index) {
                                  return Icon(
                                    index < driver.rating.floor()
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: AvroClientColors.accent,
                                    size: 16,
                                  );
                                }),
                                const SizedBox(width: 8),
                                Text(
                                  '${driver.rating.toStringAsFixed(1)} • ${driver.totalOrders} поездок',
                                  style: EvikTypography.bodySmall.copyWith(
                                    color: AvroClientColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Rating section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AvroClientColors.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AvroClientColors.surface),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Как прошла поездка?',
                            style: EvikTypography.h3.copyWith(
                              color: AvroClientColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Star rating
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(5, (index) {
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _rating = index + 1;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: Icon(
                                      index < _rating
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: AvroClientColors.accent,
                                      size: 40,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Rating text
                          if (_rating > 0)
                            Center(
                              child: Text(
                                _getRatingText(_rating),
                                style: EvikTypography.bodyMedium.copyWith(
                                  color: AvroClientColors.textSecondary,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),

                          // Comment field
                          Text(
                            'Комментарий (по желанию)',
                            style: EvikTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AvroClientColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _commentController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Расскажите о своих впечатлениях...',
                              hintStyle: EvikTypography.bodyMedium.copyWith(
                                color: AvroClientColors.tabInactive,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: AvroClientColors.surface),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: AvroClientColors.surface),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: AvroClientColors.accent),
                              ),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                            style: EvikTypography.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: EvikButton(
                      text: 'Оставить отзыв',
                      onPressed: (_rating > 0 && !_isSubmitting) ? _submitRating : null,
                      isLoading: _isSubmitting,
                      variant: _rating > 0
                          ? EvikButtonVariant.primary
                          : EvikButtonVariant.ghost,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: EvikButton(
                      text: 'Заказать ещё раз',
                      onPressed: _orderAgain,
                      variant: EvikButtonVariant.secondary,
                      icon: const Icon(Icons.refresh, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Плохо';
      case 2:
        return 'Неудовлетворительно';
      case 3:
        return 'Нормально';
      case 4:
        return 'Хорошо';
      case 5:
        return 'Отлично!';
      default:
        return '';
    }
  }
}
