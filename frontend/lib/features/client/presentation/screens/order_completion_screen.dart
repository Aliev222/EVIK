import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/entities/order_flow_state.dart';
import '../providers/order_flow_provider.dart';
import 'client_wallet_screen.dart';

class OrderCompletionScreen extends ConsumerStatefulWidget {
  const OrderCompletionScreen({super.key});

  @override
  ConsumerState<OrderCompletionScreen> createState() =>
      _OrderCompletionScreenState();
}

class _OrderCompletionScreenState extends ConsumerState<OrderCompletionScreen> {
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;

  void _processPayment() {
    ref.read(orderFlowProvider.notifier).goToRating();
    context.go('/order/rating');
  }

  void _orderAgain() {
    ref.read(orderFlowProvider.notifier).resetFlow();
    context.go('/');
  }

  Future<void> _changeCard() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ClientWalletScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderFlowProvider);
    final total =
        state.estimatedPrice > 0 ? state.estimatedPrice.round() : 1550;

    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.rating &&
          previous?.currentStep != OrderFlowStep.rating) {
        context.go('/order/rating');
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F4),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 760;
            final horizontal = compact ? 18.0 : 24.0;
            final topGap = compact ? 12.0 : 22.0;
            final successHeight = compact ? 150.0 : 194.0;
            final iconSize = compact ? 58.0 : 76.0;
            final cardGap = compact ? 10.0 : 16.0;
            final paymentGap = compact ? 8.0 : 12.0;
            final buttonHeight = compact ? 52.0 : 56.0;

            return Padding(
              padding: EdgeInsets.fromLTRB(horizontal, topGap, horizontal, 12),
              child: Column(
                children: [
                  Text(
                    'Заказ завершён',
                    style: EvikTypography.h2.copyWith(
                      color: EvikColors.primaryBlack,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: cardGap),
                  _SuccessCard(
                    height: successHeight,
                    iconSize: iconSize,
                    compact: compact,
                  ),
                  SizedBox(height: cardGap),
                  _TotalCard(total: total),
                  SizedBox(height: cardGap),
                  _PaymentMethodCard(
                    selected: _selectedPaymentMethod,
                    compact: compact,
                    onChanged: (method) {
                      setState(() => _selectedPaymentMethod = method);
                    },
                    onChangeCard: _changeCard,
                  ),
                  SizedBox(height: paymentGap),
                  _PaymentNotice(
                    method: _selectedPaymentMethod,
                    total: total,
                    onChangeCard: _changeCard,
                  ),
                  const Spacer(),
                  SizedBox(
                    height: buttonHeight,
                    width: double.infinity,
                    child: EvikButton(
                      text: _selectedPaymentMethod == PaymentMethod.cash
                          ? 'Подтвердить оплату'
                          : 'Оплатить картой',
                      onPressed: _processPayment,
                      width: double.infinity,
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 12),
                  SizedBox(
                    height: buttonHeight,
                    width: double.infinity,
                    child: EvikButton(
                      text: 'Заказать ещё раз',
                      onPressed: _orderAgain,
                      variant: EvikButtonVariant.secondary,
                      width: double.infinity,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.height,
    required this.iconSize,
    required this.compact,
  });

  final double height;
  final double iconSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: EvikColors.successGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle,
              color: EvikColors.successGreen,
              size: iconSize * 0.62,
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          Text(
            'Эвакуация завершена!',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EvikTypography.h2.copyWith(
              color: EvikColors.primaryBlack,
              fontSize: compact ? 22 : 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ваш автомобиль успешно доставлен',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EvikTypography.bodyMedium.copyWith(
              color: EvikColors.gray600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EvikColors.gray200),
      ),
      child: Row(
        children: [
          Text(
            'ИТОГО',
            style: EvikTypography.bodyLarge.copyWith(
              color: EvikColors.primaryBlack,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            '$total ₽',
            style: EvikTypography.price.copyWith(
              color: EvikColors.accentOrange,
              fontSize: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.selected,
    required this.compact,
    required this.onChanged,
    required this.onChangeCard,
  });

  final PaymentMethod selected;
  final bool compact;
  final ValueChanged<PaymentMethod> onChanged;
  final VoidCallback onChangeCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EvikColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Способ оплаты',
            style: EvikTypography.bodyMedium.copyWith(
              color: EvikColors.primaryBlack,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          _PaymentOption(
            method: PaymentMethod.cash,
            selected: selected,
            title: 'Наличными водителю',
            subtitle: 'Оплатите водителю наличными',
            icon: Icons.payments_rounded,
            onTap: onChanged,
          ),
          SizedBox(height: compact ? 6 : 8),
          _PaymentOption(
            method: PaymentMethod.card,
            selected: selected,
            title: 'Банковской картой',
            subtitle: 'Автоматическое списание с карты',
            icon: Icons.credit_card_rounded,
            trailing: TextButton(
              onPressed: onChangeCard,
              child: const Text('Сменить'),
            ),
            onTap: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.method,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  final PaymentMethod method;
  final PaymentMethod selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<PaymentMethod> onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isSelected = method == selected;

    return InkWell(
      onTap: () => onTap(method),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? EvikColors.accentOrange.withValues(alpha: 0.08)
              : EvikColors.primaryWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? EvikColors.accentOrange : EvikColors.gray200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? EvikColors.accentOrange : EvikColors.gray500,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EvikTypography.bodyMedium.copyWith(
                      color: isSelected
                          ? EvikColors.accentOrange
                          : EvikColors.primaryBlack,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EvikTypography.bodySmall.copyWith(
                      color: EvikColors.gray600,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null && !isSelected) trailing!,
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? EvikColors.accentOrange : EvikColors.gray400,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentNotice extends StatelessWidget {
  const _PaymentNotice({
    required this.method,
    required this.total,
    required this.onChangeCard,
  });

  final PaymentMethod method;
  final int total;
  final VoidCallback onChangeCard;

  @override
  Widget build(BuildContext context) {
    final isCash = method == PaymentMethod.cash;

    return Container(
      height: 58,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isCash
            ? EvikColors.warningAmber.withValues(alpha: 0.10)
            : EvikColors.successGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCash ? EvikColors.warningAmber : EvikColors.successGreen,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCash ? Icons.info_outline_rounded : Icons.check_circle_outline,
            color: isCash ? EvikColors.warningAmber : EvikColors.successGreen,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isCash
                  ? 'Оплатите $total ₽ водителю наличными'
                  : 'Если на карте не хватает средств, смените карту',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: EvikTypography.bodyMedium.copyWith(
                color: EvikColors.primaryBlack,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!isCash)
            TextButton(
              onPressed: onChangeCard,
              child: const Text('Карта'),
            ),
        ],
      ),
    );
  }
}
