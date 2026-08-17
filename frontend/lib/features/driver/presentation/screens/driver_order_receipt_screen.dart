import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/format/money.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_wallet_provider.dart';
import 'package:tow_truck_frontend/features/order/data/repository_impl/http_order_repository.dart';
import 'package:tow_truck_frontend/shared/widgets/error_state.dart';
import 'package:tow_truck_frontend/shared/widgets/skeleton_card.dart';

/// Чек заказа для водителя. Работает и для наличных заказов: бэкенд собирает
/// чек из данных заказа и wallet_transactions (payments-строки для наличных
/// не создаются). Для наличных меняется только отображение, деньги не трогаем.
class DriverOrderReceiptScreen extends ConsumerStatefulWidget {
  const DriverOrderReceiptScreen({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<DriverOrderReceiptScreen> createState() =>
      _DriverOrderReceiptScreenState();
}

class _DriverOrderReceiptScreenState
    extends ConsumerState<DriverOrderReceiptScreen> {
  late Future<OrderReceipt> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<OrderReceipt> _load() {
    return ref
        .read(driverWalletRepositoryProvider)
        .getOrderReceipt(widget.orderId);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        title:
            Text('Чек заказа', style: EvikTypography.h2.copyWith(fontSize: 22)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<OrderReceipt>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: const [
                SkeletonCard(height: 180),
                SizedBox(height: 12),
                SkeletonCard(height: 240),
              ],
            );
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Не удалось загрузить чек',
              onRetry: _retry,
            );
          }
          return _ReceiptBody(receipt: snapshot.requireData);
        },
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.receipt});

  final OrderReceipt receipt;

  bool get _isCash =>
      receipt.paymentMethod.toLowerCase() == 'cash' || receipt.paymentId.isEmpty;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _SummaryCard(receipt: receipt, isCash: _isCash),
        const SizedBox(height: 12),
        if (_isCash) ...[
          const _CashDebtNote(),
          const SizedBox(height: 12),
        ],
        _DetailsCard(receipt: receipt),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.receipt, required this.isCash});

  final OrderReceipt receipt;
  final bool isCash;

  @override
  Widget build(BuildContext context) {
    final color = isCash ? AvroDriverColors.warning : AvroDriverColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AvroDriverColors.border),
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isCash ? Icons.payments_rounded : Icons.credit_card_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isCash ? 'Наличный заказ' : 'Безналичный заказ',
                  style: EvikTypography.h3.copyWith(fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Сумма заказа',
            style: EvikTypography.bodyMedium.copyWith(
              color: AvroDriverColors.grayHint,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatKopecks(receipt.priceTotal),
              style: EvikTypography.h1.copyWith(fontSize: 40),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashDebtNote extends StatelessWidget {
  const _CashDebtNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AvroDriverColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AvroDriverColors.warning.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AvroDriverColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Оплата принята наличными водителю. Комиссия по этому заказу '
              'добавлена к вашему долгу за наличные.',
              style: EvikTypography.bodySmall.copyWith(
                fontSize: 12,
                height: 1.45,
                color: AvroDriverColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.receipt});

  final OrderReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AvroDriverColors.border),
      ),
      child: Column(
        children: [
          _Row(label: 'Заказ', value: receipt.orderId),
          _Row(
            label: 'Способ оплаты',
            value: _methodLabel(receipt.paymentMethod),
          ),
          _Row(
            label: 'Статус оплаты',
            value: _statusLabel(receipt.paymentStatus),
          ),
          _Row(
            label: 'Комиссия',
            value: formatKopecks(receipt.commissionAmount),
          ),
          _Row(
            label: 'Водителю',
            value: formatKopecks(receipt.driverAmount),
          ),
          if (receipt.pickupAddress != null && receipt.pickupAddress!.isNotEmpty)
            _Row(label: 'Откуда', value: receipt.pickupAddress!),
          if (receipt.dropoffAddress != null &&
              receipt.dropoffAddress!.isNotEmpty)
            _Row(label: 'Куда', value: receipt.dropoffAddress!),
          if (receipt.createdAt != null)
            _Row(label: 'Создан', value: _dateTime(receipt.createdAt!)),
          if (receipt.completedAt != null)
            _Row(label: 'Завершен', value: _dateTime(receipt.completedAt!)),
          if ((receipt.driverName ?? '').isNotEmpty)
            _Row(label: 'Водитель', value: receipt.driverName!),
        ],
      ),
    );
  }

  static String _methodLabel(String method) {
    return switch (method.toLowerCase()) {
      'cash' => 'Наличные',
      'card' => 'Карта',
      _ => method,
    };
  }

  static String _statusLabel(String status) {
    return switch (status.toLowerCase()) {
      'succeeded' => 'Оплачен',
      'completed' => 'Оплачен',
      'pending' => 'В обработке',
      'canceled' => 'Отменен',
      'failed' => 'Ошибка',
      '' => 'Оплачен',
      _ => status,
    };
  }

  static String _dateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.${value.year}, $hour:$minute';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AvroDriverColors.border, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: EvikTypography.bodySmall.copyWith(
                fontSize: 12,
                color: AvroDriverColors.grayHint,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style:
                  EvikTypography.bodyMedium.copyWith(fontSize: 14, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}