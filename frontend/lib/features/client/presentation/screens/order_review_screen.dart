import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/new_driver_provider.dart';
import 'package:tow_truck_frontend/features/review/domain/entities/review.dart';
import 'package:tow_truck_frontend/features/review/presentation/providers/review_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

class OrderReviewScreen extends ConsumerStatefulWidget {
  const OrderReviewScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends ConsumerState<OrderReviewScreen> {
  Driver? _driver;
  Order? _order;
  bool _loading = true;
  int _rating = 0;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final order = await orderRepo.getOrder(widget.orderId);
      if (!mounted) return;
      if (order == null) {
        setState(() => _loading = false);
        return;
      }
      _order = order;

      if (order.driverId != null && order.driverId!.isNotEmpty) {
        try {
          final driverRepo = ref.read(httpDriverRepositoryProvider);
          final driver = await driverRepo.getDriver(order.driverId!);
          if (mounted) {
            _driver = driver;
          }
        } catch (_) {}
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    final order = _order;
    final driver = _driver;
    if (!mounted) return;
    if (order == null) {
      _showError('Информация о заказе не найдена');
      return;
    }
    if (driver == null) {
      _showError('Не удалось загрузить данные водителя. Попробуйте позже или нажмите «Пропустить»');
      return;
    }
    if (_rating == 0) {
      _showError('Пожалуйста, поставьте оценку');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final request = CreateReviewRequest(
        orderId: order.id,
        driverId: driver.userId,
        stars: _rating,
        text: _commentController.text.trim(),
      );
      await ref.read(reviewRepositoryProvider).createReview(request);
      if (!mounted) return;
      ref.read(orderFlowProvider.notifier).resetFlow();
      context.go('/');
    } catch (e) {
      if (mounted) {
        String msg = 'Ошибка отправки отзыва';
        if (e is ApiClientException && e.statusCode == 0) {
          msg = 'Нет подключения к интернету — проверьте соединение';
        } else if (e.toString().contains('409')) {
          msg = 'Вы уже оставили отзыв по этому заказу';
        }
        _showError(msg);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _skip() {
    try {
      ref.read(orderFlowProvider.notifier).resetFlow();
    } catch (_) {
      // Non-critical — navigation proceeds even if resetFlow fails.
    }
    if (!mounted) return;
    try {
      context.go('/');
    } catch (e) {
      if (mounted) {
        _showError('Не удалось перейти на главный экран: $e');
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AvroClientColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Column(
                  children: [
                    if (_driver != null) ...[
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AvroClientColors.surface,
                        backgroundImage: _driver!.avatarUrl != null
                            ? NetworkImage(_driver!.avatarUrl!)
                            : null,
                        child: _driver!.avatarUrl == null
                            ? const Icon(Icons.person, size: 40, color: AvroClientColors.tabInactive)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _driver!.fullName ?? 'Водитель',
                        style: EvikTypography.h2.copyWith(
                          color: AvroClientColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.star, color: AvroClientColors.accent, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            _driver!.rating > 0
                                ? _driver!.rating.toStringAsFixed(1)
                                : '—',
                            style: EvikTypography.bodyLarge.copyWith(
                              color: AvroClientColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AvroClientColors.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AvroClientColors.surface),
                      ),
                      child: Column(
                        children: [
                          if (_driver != null) ...[
                            _InfoRow(
                              icon: Icons.local_shipping_rounded,
                              label: 'Машина',
                              value: _driver!.vehicleModel.isNotEmpty
                                  ? _driver!.vehicleModel
                                  : 'Не указано',
                            ),
                            const SizedBox(height: 10),
                            _InfoRow(
                              icon: Icons.confirmation_number_rounded,
                              label: 'Номер',
                              value: _driver!.vehicleNumber.isNotEmpty
                                  ? _driver!.vehicleNumber
                                  : 'Не указан',
                            ),
                            const SizedBox(height: 10),
                          ],
                          _InfoRow(
                            icon: Icons.phone_rounded,
                            label: 'Телефон',
                            value: _driver?.phone?.isNotEmpty == true
                                ? _driver!.phone!
                                : 'Не указан',
                            isPhone: true,
                            onPhoneTap: _driver?.phone?.isNotEmpty == true
                                ? () => _callDriver(_driver!.phone!)
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Оцените поездку',
                      style: EvikTypography.bodyLarge.copyWith(
                        color: AvroClientColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () => setState(() => _rating = index + 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              index < _rating ? Icons.star : Icons.star_border,
                              color: index < _rating
                                  ? AvroClientColors.accent
                                  : AvroClientColors.tabInactive,
                              size: 40,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _commentController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Напишите отзыв...',
                        hintStyle: EvikTypography.bodyMedium.copyWith(
                          color: AvroClientColors.tabInactive,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AvroClientColors.surface),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AvroClientColors.surface),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AvroClientColors.accent),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: EvikTypography.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: EvikButton(
                        text: 'Отправить отзыв',
                        onPressed: (_rating > 0 && !_isSubmitting)
                            ? _submitReview
                            : null,
                        isLoading: _isSubmitting,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _skip,
                      child: Text(
                        'Пропустить',
                        style: EvikTypography.bodyMedium.copyWith(
                          color: AvroClientColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isPhone = false,
    this.onPhoneTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isPhone;
  final VoidCallback? onPhoneTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AvroClientColors.accent),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: EvikTypography.bodySmall.copyWith(
            color: AvroClientColors.textSecondary,
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onPhoneTap,
            child: Text(
              value,
              style: EvikTypography.bodyMedium.copyWith(
                color: isPhone ? AvroClientColors.accent : AvroClientColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
