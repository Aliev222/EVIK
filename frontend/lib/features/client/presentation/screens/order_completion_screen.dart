import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/order/data/repository_impl/http_order_repository.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

class OrderCompletionScreen extends ConsumerStatefulWidget {
  const OrderCompletionScreen({super.key});

  @override
  ConsumerState<OrderCompletionScreen> createState() =>
      _OrderCompletionScreenState();
}

class _OrderCompletionScreenState extends ConsumerState<OrderCompletionScreen> {
  Future<OrderReceipt>? _receiptFuture;
  String? _receiptOrderId;

  void _goToReview() {
    ref.read(orderFlowProvider.notifier).goToRating();
    context.go('/order/rating');
  }

  void _orderAgain() {
    ref.read(orderFlowProvider.notifier).resetFlow();
    context.go('/');
  }

  Future<OrderReceipt> _loadReceipt(String orderId) {
    final repository = ref.read(orderRepositoryProvider);
    if (repository is! HttpOrderRepository) {
      throw StateError('Receipt endpoint is unavailable');
    }
    return repository.getOrderReceipt(orderId);
  }

  void _ensureReceiptFuture(String orderId) {
    if (_receiptOrderId == orderId && _receiptFuture != null) return;
    _receiptOrderId = orderId;
    _receiptFuture = _loadReceipt(orderId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderFlowProvider);
    final order = state.activeOrder;
    if (order != null) {
      _ensureReceiptFuture(order.id);
    }

    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.rating &&
          previous?.currentStep != OrderFlowStep.rating) {
        context.go('/order/rating');
      }
    });

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            children: [
              Text(
                'Заказ завершен',
                style: EvikTypography.h2.copyWith(
                  color: AvroClientColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              const _SuccessCard(),
              const SizedBox(height: 14),
              Expanded(
                child: order == null
                    ? const Center(child: Text('Заказ не найден'))
                    : FutureBuilder<OrderReceipt>(
                        future: _receiptFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return _ReceiptError(
                              onRetry: () => setState(() {
                                _receiptFuture = _loadReceipt(order.id);
                              }),
                            );
                          }
                          return _ReceiptCard(
                            order: order,
                            receipt: snapshot.requireData,
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              EvikButton(
                text: 'Оставить отзыв',
                onPressed: _goToReview,
                width: double.infinity,
              ),
              const SizedBox(height: 10),
              EvikButton(
                text: 'Заказать еще раз',
                onPressed: _orderAgain,
                variant: EvikButtonVariant.secondary,
                width: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AvroClientColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: AvroClientColors.success,
              size: 40,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Эвакуация завершена',
            style: EvikTypography.h3.copyWith(
              color: AvroClientColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptError extends StatelessWidget {
  const _ReceiptError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 40),
          const SizedBox(height: 10),
          const Text('Не удалось загрузить чек'),
          const SizedBox(height: 12),
          EvikButton(
            text: 'Повторить',
            onPressed: onRetry,
            width: 180,
            variant: EvikButtonVariant.secondary,
          ),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.order,
    required this.receipt,
  });

  final Order order;
  final OrderReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroClientColors.surface),
      ),
      child: ListView(
        children: [
          _ReceiptRow(label: 'Заказ', value: receipt.orderId),
          _ReceiptRow(label: 'Платеж', value: receipt.paymentId),
          _ReceiptRow(label: 'Сумма', value: _money(receipt.priceTotal)),
          _ReceiptRow(label: 'Способ оплаты', value: receipt.paymentMethod),
          _ReceiptRow(label: 'Статус оплаты', value: receipt.paymentStatus),
          _ReceiptRow(
              label: 'Комиссия', value: _money(receipt.commissionAmount)),
          _ReceiptRow(
            label: 'Водителю',
            value: _money(receipt.driverAmount),
          ),
          _ReceiptRow(
            label: 'Создан',
            value: _date(receipt.createdAt ?? order.createdAt),
          ),
          _ReceiptRow(
            label: 'Завершен',
            value: _date(receipt.completedAt ?? order.completedAt),
          ),
          if ((receipt.driverName ?? '').isNotEmpty)
            _ReceiptRow(label: 'Водитель', value: receipt.driverName!),
          if ((receipt.driverId ?? order.driverId ?? '').isNotEmpty)
            _ReceiptRow(
              label: 'ID водителя',
              value: receipt.driverId ?? order.driverId!,
            ),
        ],
      ),
    );
  }

  static String _money(int amount) => '${(amount / 100).toStringAsFixed(0)} ₽';

  static String _date(DateTime? value) {
    if (value == null) return '-';
    return '${value.day.toString().padLeft(2, '0')}.'
        '${value.month.toString().padLeft(2, '0')}.'
        '${value.year} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: EvikTypography.bodyMedium.copyWith(
                color: AvroClientColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: EvikTypography.bodyMedium.copyWith(
                color: AvroClientColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
