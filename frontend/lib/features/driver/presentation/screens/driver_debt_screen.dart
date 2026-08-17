import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/format/money.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/shared/widgets/skeleton_card.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_wallet.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_debt_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_wallet_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_order_receipt_screen.dart';

/// «Погасить долг»: shows the driver their outstanding cash-commission debt,
/// the list of cash orders the debt came from (each tap opens the order
/// receipt) and the card-order repayments that reduced it. Repayment options
/// remain placeholder (SBP is Phase 4); card orders repay the debt
/// automatically.
class DriverDebtScreen extends ConsumerWidget {
  const DriverDebtScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverWalletProvider);
    final wallet = state.wallet;

    final debt = wallet?.debtBalance ?? 0;
    final blocked = wallet?.debtBlocked ?? false;

    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        title: Text('Погасить долг',
            style: EvikTypography.h2.copyWith(fontSize: 22)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(driverWalletProvider.notifier).refresh(),
            ref.read(driverDebtProvider.notifier).refresh(),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _DebtSummaryCard(debt: debt, blocked: blocked),
            const SizedBox(height: 12),
            const DriverDebtSourcesSection(),
            const SizedBox(height: 12),
            const _SbpPlaceholderCard(),
            const SizedBox(height: 12),
            const _CardNoteCard(),
            const SizedBox(height: 16),
            EvikButton(
              text: 'Обновить',
              icon: const Icon(Icons.refresh_rounded, size: 18),
              width: double.infinity,
              variant: EvikButtonVariant.ghost,
              onPressed: () async {
                await Future.wait([
                  ref.read(driverWalletProvider.notifier).refresh(),
                  ref.read(driverDebtProvider.notifier).refresh(),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// «Из чего сложился долг»: the cash orders that accrued the debt and the
/// card-order repayments that reduced it. Each cash order row opens its receipt.
class DriverDebtSourcesSection extends ConsumerWidget {
  const DriverDebtSourcesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverDebtProvider);
    final breakdown = state.breakdown;

    if (state.isLoading && breakdown == null) {
      return const Column(
        children: [
          SkeletonCard(height: 84),
          SizedBox(height: 8),
          SkeletonCard(height: 84),
        ],
      );
    }

    if (breakdown == null) {
      if (state.errorMessage != null) {
        return _SectionError(
          message: state.errorMessage!,
          onRetry: () => ref.read(driverDebtProvider.notifier).refresh(),
        );
      }
      return const SizedBox.shrink();
    }

    final accruals = breakdown.accruals;
    final repayments = breakdown.repayments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Из чего сложился долг',
                style: EvikTypography.h3.copyWith(fontSize: 17),
              ),
            ),
            if (breakdown.accrued > 0)
              Text(
                formatKopecks(breakdown.accrued),
                style: EvikTypography.bodyMedium.copyWith(
                  fontSize: 14,
                  color: AvroDriverColors.warning,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Комиссия с наличных заказов',
          style: EvikTypography.bodySmall.copyWith(
            fontSize: 12,
            color: AvroDriverColors.grayHint,
          ),
        ),
        const SizedBox(height: 10),
        if (accruals.isEmpty)
          const _EmptyNote(
              text: 'Наличных заказов с долгом пока нет.')
        else
          Container(
            decoration: _sourcesDecoration(),
            child: Column(
              children: [
                for (var index = 0; index < accruals.length; index++) ...[
                  _DebtSourceTile(transaction: accruals[index]),
                  if (index != accruals.length - 1)
                    const Divider(height: 1, color: AvroDriverColors.border),
                ],
              ],
            ),
          ),
        if (repayments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Погашения',
                  style: EvikTypography.h3.copyWith(fontSize: 17),
                ),
              ),
              if (breakdown.repaid > 0)
                Text(
                  formatKopecks(breakdown.repaid),
                  style: EvikTypography.bodyMedium.copyWith(
                    fontSize: 14,
                    color: AvroDriverColors.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Комиссия удержана из безналичных заказов',
            style: EvikTypography.bodySmall.copyWith(
              fontSize: 12,
              color: AvroDriverColors.grayHint,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: _sourcesDecoration(),
            child: Column(
              children: [
                for (var index = 0; index < repayments.length; index++) ...[
                  _DebtRepaymentTile(transaction: repayments[index]),
                  if (index != repayments.length - 1)
                    const Divider(height: 1, color: AvroDriverColors.border),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

BoxDecoration _sourcesDecoration() {
  return BoxDecoration(
    color: AvroDriverColors.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AvroDriverColors.border),
  );
}

class _DebtSourceTile extends StatelessWidget {
  const _DebtSourceTile({required this.transaction});

  final DriverDebtTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: transaction.orderId == null
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DriverOrderReceiptScreen(
                      orderId: transaction.orderId!,
                    ),
                  ),
                );
              },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AvroDriverColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AvroDriverColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dateLabel(transaction.createdAt),
                      style: EvikTypography.bodyMedium
                          .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _orderSummary(transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EvikTypography.bodySmall.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatKopecks(transaction.amount),
                    style: EvikTypography.bodyMedium.copyWith(
                      fontSize: 14,
                      color: AvroDriverColors.warning,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'заказ ${formatKopecks(transaction.orderAmount)}',
                    style: EvikTypography.bodySmall.copyWith(
                      fontSize: 11,
                      color: AvroDriverColors.grayHint,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: AvroDriverColors.grayHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateLabel(DateTime? value) {
    if (value == null) return 'Наличный заказ';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return 'Наличный заказ · $day.$month.${value.year}';
  }

  static String _orderSummary(DriverDebtTransaction transaction) {
    final orderId = transaction.orderId ?? '';
    if (orderId.isEmpty) return 'Комиссия за наличный заказ';
    return 'Заказ ${orderId.length > 10 ? orderId.substring(0, 10) : orderId}';
  }
}

class _DebtRepaymentTile extends StatelessWidget {
  const _DebtRepaymentTile({required this.transaction});

  final DriverDebtTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AvroDriverColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.payments_rounded,
              color: AvroDriverColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateLabel(transaction.createdAt),
                  style: EvikTypography.bodyMedium.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  transaction.orderId == null
                      ? 'Безналичный заказ'
                      : 'Из безналичного заказа ${transaction.orderId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EvikTypography.bodySmall.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '-${formatKopecks(transaction.amount)}',
            style: EvikTypography.bodyMedium.copyWith(
              fontSize: 14,
              color: AvroDriverColors.success,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static String _dateLabel(DateTime? value) {
    if (value == null) return 'Погашение';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return 'Погашение · $day.$month.${value.year}';
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _sourcesDecoration(),
      child: Text(
        text,
        style: EvikTypography.bodySmall.copyWith(
          fontSize: 13,
          color: AvroDriverColors.grayHint,
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AvroDriverColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AvroDriverColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: EvikTypography.bodySmall.copyWith(
                fontSize: 12,
                color: AvroDriverColors.error,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

class _DebtSummaryCard extends StatelessWidget {
  const _DebtSummaryCard({required this.debt, required this.blocked});

  final int debt;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final color = blocked ? AvroDriverColors.error : AvroDriverColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.payment_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  blocked ? 'Заказы приостановлены' : 'Долг за наличные',
                  style: EvikTypography.h3.copyWith(fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Погасите долг, чтобы принимать заказы',
            style: EvikTypography.bodyMedium.copyWith(
              color: AvroDriverColors.grayHint,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatKopecks(debt),
              style: EvikTypography.h1.copyWith(
                color: color,
                fontSize: 40,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SbpPlaceholderCard extends StatelessWidget {
  const _SbpPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AvroDriverColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AvroDriverColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.qr_code_rounded,
              color: AvroDriverColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Оплата по СБП',
                    style: EvikTypography.bodyMedium.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  'Перевод по СБП из вашего банка по QR-коду или номеру телефона. Оплата по СБП скоро — пополните баланс картой или отработайте безналично.',
                  style: EvikTypography.bodySmall
                      .copyWith(fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardNoteCard extends StatelessWidget {
  const _CardNoteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AvroDriverColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AvroDriverColors.info.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.credit_card_rounded,
              color: AvroDriverColors.info, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Карточные заказы погашают долг автоматически',
                    style: EvikTypography.bodyMedium.copyWith(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'Комиссия с безналичных заказов гасит накопленный долг автоматически. Принимайте заказы с оплатой картой от клиентов.',
                  style: EvikTypography.bodySmall
                      .copyWith(fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}