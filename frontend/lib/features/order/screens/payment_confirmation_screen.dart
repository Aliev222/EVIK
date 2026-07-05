import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/order/data/repository_impl/http_order_repository.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';
import 'package:tow_truck_frontend/features/client/domain/entities/payment_wallet.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/client_payment_methods_provider.dart';

class PaymentConfirmationScreen extends ConsumerStatefulWidget {
  const PaymentConfirmationScreen({super.key});

  @override
  ConsumerState<PaymentConfirmationScreen> createState() =>
      _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState
    extends ConsumerState<PaymentConfirmationScreen> {
  bool _isPaying = false;
  bool _isChangingMethod = false;

  @override
  Widget build(BuildContext context) {
    final flowState = ref.watch(orderFlowProvider);
    final order = flowState.activeOrder;

    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.completion &&
          previous?.currentStep != OrderFlowStep.completion) {
        if (!mounted || next.activeOrder == null) return;
        context.go('/order/review/${next.activeOrder!.id}');
      }
    });

    if (order == null) {
      return Scaffold(
        backgroundColor: AvroClientColors.background,
        body: const Center(child: Text('Информация о заказе недоступна')),
      );
    }

    final priceTotal = (order.finalPrice ?? order.estimatedPrice).round();
    final basePrice = priceTotal - (order.surchargeAmount / 100).round();
    final surchargeRub = (order.surchargeAmount / 100).round();

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      appBar: AppBar(
        backgroundColor: AvroClientColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AvroClientColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                'Заказ завершён',
                style: EvikTypography.h2.copyWith(
                  color: AvroClientColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Оплатите поездку',
                style: EvikTypography.bodyMedium.copyWith(
                  color: AvroClientColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              _PriceCard(
                basePrice: basePrice,
                distance: order.distance,
                surcharge: surchargeRub,
                total: priceTotal,
              ),
              const SizedBox(height: 20),
              _PaymentMethodCard(
                order: order,
                isChanging: _isChangingMethod,
                onChangeMethod: _showPaymentMethodSheet,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: EvikButton(
                  text: 'Оплатить $priceTotal ₽',
                  onPressed: _isPaying ? null : _handlePay,
                  isLoading: _isPaying,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handlePay() async {
    setState(() => _isPaying = true);
    try {
      final order = ref.read(orderFlowProvider).activeOrder;
      if (order == null) return;

      final repo = ref.read(orderRepositoryProvider);
      if (repo is! HttpOrderRepository) {
        _showError('Платёжный сервис недоступен');
        return;
      }

      final response = await repo.confirmPayment(order.id);
      final confirmationUrl = response['confirmation_url']?.toString();

      if (confirmationUrl != null && confirmationUrl.isNotEmpty) {
        final opened = await launchUrl(
          Uri.parse(confirmationUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          _showError('Не удалось открыть страницу оплаты');
          return;
        }
        _pollPaymentStatus(order.id);
      } else {
        ref.read(orderFlowProvider.notifier).goToCompletion();
      }
    } catch (e) {
      _showError('Ошибка оплаты: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  Future<void> _pollPaymentStatus(String orderId) async {
    final repo = ref.read(orderRepositoryProvider);
    if (repo is! HttpOrderRepository) return;

    for (var attempt = 0; attempt < 30; attempt++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final payment = await repo.getOrderPaymentStatus(orderId);
        if (payment.isSucceeded) {
          ref.read(orderFlowProvider.notifier).goToCompletion();
          return;
        }
        if (payment.isFailed) {
          _showError('Оплата не прошла. Попробуйте снова.');
          return;
        }
      } catch (_) {
        // continue polling
      }
    }
    _showError('Время ожидания оплаты истекло');
  }

  Future<void> _showPaymentMethodSheet() async {
    final cardsAsync = ref.read(clientPaymentMethodsProvider);
    final cards = cardsAsync.valueOrNull ?? const <PaymentCard>[];

    final result = await showModalBottomSheet<PaymentMethod>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PaymentMethodSheet(cards: cards),
    );

    if (result == null || !mounted) return;

    setState(() => _isChangingMethod = true);
    try {
      final order = ref.read(orderFlowProvider).activeOrder;
      if (order == null) return;
      final repo = ref.read(orderRepositoryProvider);
      if (repo is! HttpOrderRepository) return;
      await repo.updatePaymentMethod(order.id, result);
      ref.read(orderFlowProvider.notifier).selectPaymentMethod(result);
    } catch (e) {
      _showError('Не удалось изменить способ оплаты');
    } finally {
      if (mounted) setState(() => _isChangingMethod = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AvroClientColors.error,
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.basePrice,
    required this.distance,
    required this.surcharge,
    required this.total,
  });

  final int basePrice;
  final double distance;
  final int surcharge;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroClientColors.surface),
      ),
      child: Column(
        children: [
          _Row(label: 'Базовая стоимость', value: '$basePrice ₽'),
          const SizedBox(height: 10),
          _Row(label: 'Расстояние ${distance.toStringAsFixed(1)} км', value: ''),
          if (surcharge > 0) ...[
            const SizedBox(height: 10),
            _Row(label: 'Надбавки', value: '+$surcharge ₽'),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AvroClientColors.surface),
          ),
          _Row(
            label: 'Итого',
            value: '$total ₽',
            isBold: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  final String label;
  final String value;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: (isBold
                  ? EvikTypography.bodyMedium
                  : EvikTypography.bodySmall)
              .copyWith(
            color: isBold
                ? AvroClientColors.textPrimary
                : AvroClientColors.textSecondary,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        if (value.isNotEmpty)
          Text(
            value,
            style: (isBold
                    ? EvikTypography.h3
                    : EvikTypography.bodyMedium)
                .copyWith(
              color: AvroClientColors.textPrimary,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _PaymentMethodCard extends ConsumerWidget {
  const _PaymentMethodCard({
    required this.order,
    required this.isChanging,
    required this.onChangeMethod,
  });

  final Order order;
  final bool isChanging;
  final VoidCallback onChangeMethod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(clientPaymentMethodsProvider);
    final cards = cardsAsync.valueOrNull ?? const <PaymentCard>[];

    final isCard = order.paymentMethod == PaymentMethod.card;
    final defaultCard = cards.isEmpty ? null : cards.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroClientColors.surface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Способ оплаты',
            style: EvikTypography.bodySmall.copyWith(
              color: AvroClientColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                isCard ? Icons.credit_card_rounded : Icons.money_rounded,
                color: AvroClientColors.accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCard && defaultCard != null
                      ? '${defaultCard.displayBrand} •••• ${defaultCard.last4}'
                      : 'Наличные',
                  style: EvikTypography.bodyMedium.copyWith(
                    color: AvroClientColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isChanging)
                TextButton(
                  onPressed: onChangeMethod,
                  child: Text(
                    'Изменить →',
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroClientColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodSheet extends StatelessWidget {
  const _PaymentMethodSheet({required this.cards});

  final List<PaymentCard> cards;

  @override
  Widget build(BuildContext context) {
    final hasCards = cards.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Способ оплаты',
              style: EvikTypography.h3.copyWith(
                color: AvroClientColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            if (hasCards)
              _OptionTile(
                icon: Icons.credit_card_rounded,
                title: '${cards.first.displayBrand} •••• ${cards.first.last4}',
                subtitle: 'Банковская карта',
                onTap: () => Navigator.pop(context, PaymentMethod.card),
              ),
            const SizedBox(height: 8),
            _OptionTile(
              icon: Icons.money_rounded,
              title: 'Наличные',
              subtitle: 'Оплата наличными водителю',
              onTap: () => Navigator.pop(context, PaymentMethod.cash),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: AvroClientColors.surface),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AvroClientColors.accent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: EvikTypography.bodyMedium.copyWith(
                      color: AvroClientColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroClientColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AvroClientColors.tabInactive),
          ],
        ),
      ),
    );
  }
}
