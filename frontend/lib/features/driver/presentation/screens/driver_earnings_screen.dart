import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/empty_state.dart';
import 'package:tow_truck_frontend/shared/widgets/error_state.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/shared/widgets/skeleton_card.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_wallet.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_wallet_provider.dart';

class DriverEarningsScreen extends ConsumerWidget {
  const DriverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverWalletProvider);
    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        title: Text(
          'Баланс',
          style: EvikTypography.h2.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        actions: [
          IconButton(
            onPressed: state.isLoading
                ? null
                : () => ref.read(driverWalletProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(driverWalletProvider.notifier).refresh(),
        child: _WalletBody(state: state),
      ),
    );
  }
}

class _WalletBody extends ConsumerWidget {
  const _WalletBody({required this.state});

  final DriverWalletState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading && state.wallet == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: const [
          SkeletonCard(height: 190),
          SkeletonCard(height: 96),
          SkeletonCard(height: 96),
          SkeletonCard(height: 260),
        ],
      );
    }

    if (state.wallet == null && state.errorMessage != null) {
      return ErrorState(
        message: state.errorMessage!,
        onRetry: () => ref.read(driverWalletProvider.notifier).refresh(),
      );
    }

    final wallet = state.wallet ??
        const DriverWallet(
          availableBalance: 0,
          pendingBalance: 0,
          debtBalance: 0,
          currency: 'RUB',
          recentTransactions: [],
          recentPayouts: [],
        );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        if (state.errorMessage != null) ...[
          _InlineError(message: state.errorMessage!),
          const SizedBox(height: 12),
        ],
        _AvailableBalanceCard(wallet: wallet, state: state),
        const SizedBox(height: 12),
        SizedBox(
          height: 156,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MetricTile(
                  title: 'В обработке',
                  amount: wallet.pendingBalance,
                  icon: Icons.schedule_rounded,
                  color: AvroDriverColors.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  title: 'Расчеты с Авро',
                  amount: wallet.debtBalance,
                  subtitle: wallet.debtBalance > 0
                      ? 'Будет удержано из следующих безналичных заказов'
                      : 'Расчеты закрыты',
                  icon: Icons.receipt_long_rounded,
                  color: wallet.debtBalance > 0
                      ? AvroDriverColors.error
                      : AvroDriverColors.success,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _FinanceActionTile(
          icon: Icons.account_balance_rounded,
          title: 'Способы вывода',
          subtitle: _payoutMethodSubtitle(state.payoutMethods),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DriverPayoutMethodsScreen(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _FinanceActionTile(
          icon: Icons.workspace_premium_rounded,
          title: 'Подписка',
          subtitle: _subscriptionSubtitle(state.subscriptionStatus),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DriverSubscriptionScreen(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _FinanceActionTile(
          icon: Icons.receipt_long_rounded,
          title: 'История операций',
          subtitle: _transactionsSubtitle(wallet.recentTransactions),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const DriverWalletTransactionsScreen(),
            ),
          ),
        ),
      ],
    );
  }
}

class _AvailableBalanceCard extends ConsumerWidget {
  const _AvailableBalanceCard({
    required this.wallet,
    required this.state,
  });

  final DriverWallet wallet;
  final DriverWalletState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWithdraw = state.canWithdraw;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AvroDriverColors.tabInactive),
        boxShadow: [
          BoxShadow(
            color: AvroDriverColors.textPrimary.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
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
                  color: AvroDriverColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: canWithdraw
                      ? AvroDriverColors.accent
                      : AvroDriverColors.tabInactive,
                ),
              ),
              const Spacer(),
              _StatusChip(
                label: canWithdraw ? 'Можно вывести' : 'Недоступно',
                color:
                    canWithdraw ? AvroDriverColors.success : AvroDriverColors.tabInactive,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Доступно к выводу',
            style: EvikTypography.bodyMedium.copyWith(
              color: AvroDriverColors.tabInactive,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(wallet.availableBalance),
              style: EvikTypography.h1.copyWith(
                color: AvroDriverColors.textPrimary,
                fontSize: 42,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: AvroDriverColors.surface,
          ),
          const SizedBox(height: 18),
          EvikButton(
            text: 'Вывести',
            icon: const Icon(Icons.arrow_outward_rounded, size: 18),
            width: double.infinity,
            variant: EvikButtonVariant.green,
            isLoading: state.isSubmitting,
            onPressed: canWithdraw
                ? () => _confirmPayout(context, ref, wallet.availableBalance)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayout(
    BuildContext context,
    WidgetRef ref,
    int amount,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Вывести деньги', style: EvikTypography.h3),
              const SizedBox(height: 8),
              Text(
                'Заявка на вывод ${_money(amount)} будет отправлена в обработку.',
                style: EvikTypography.bodyLarge
                    .copyWith(color: AvroDriverColors.tabInactive),
              ),
              const SizedBox(height: 20),
              EvikButton(
                text: 'Подтвердить вывод',
                width: double.infinity,
                variant: EvikButtonVariant.green,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              EvikButton(
                text: 'Отмена',
                width: double.infinity,
                variant: EvikButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(driverWalletProvider.notifier).requestFullPayout();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка на вывод создана')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ref.read(driverWalletProvider).errorMessage ??
                'Не удалось создать вывод')),
      );
    }
  }
}

class DriverPayoutMethodsScreen extends ConsumerWidget {
  const DriverPayoutMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverWalletProvider);
    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        title: Text('Способы вывода',
            style: EvikTypography.h2.copyWith(fontSize: 22)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _InfoBanner(
            icon: Icons.security_rounded,
            title: 'Данные карт не хранятся в приложении',
            text:
                'Для вывода используется сохраненный идентификатор получателя в платежном провайдере.',
          ),
          const SizedBox(height: 16),
          if (state.payoutMethods.isEmpty)
            const EmptyState(
              icon: Icons.credit_card_off_rounded,
              title: 'Способ вывода не добавлен',
              subtitle:
                  'Добавьте карту, СБП или банковский счет для вывода средств.',
            )
          else
            for (final method in state.payoutMethods) ...[
              _PayoutMethodTile(method: method),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 12),
          EvikButton(
            text: 'Добавить способ',
            icon: const Icon(Icons.add_rounded, size: 18),
            width: double.infinity,
            variant: EvikButtonVariant.ghost,
            onPressed: state.isSubmitting
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DriverAddPayoutMethodScreen(),
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }
}

class DriverAddPayoutMethodScreen extends ConsumerStatefulWidget {
  const DriverAddPayoutMethodScreen({super.key});

  @override
  ConsumerState<DriverAddPayoutMethodScreen> createState() =>
      _DriverAddPayoutMethodScreenState();
}

class _DriverAddPayoutMethodScreenState
    extends ConsumerState<DriverAddPayoutMethodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recipientController = TextEditingController();
  final _maskedValueController = TextEditingController();
  String _type = 'card';
  bool _isDefault = true;

  @override
  void dispose() {
    _recipientController.dispose();
    _maskedValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverWalletProvider);

    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        title: Text(
          'Добавить способ',
          style: EvikTypography.h2.copyWith(fontSize: 22),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _surfaceDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Тип способа', style: EvikTypography.bodyMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PayoutTypeChip(
                        label: 'Карта',
                        selected: _type == 'card',
                        onTap: () => setState(() => _type = 'card'),
                      ),
                      _PayoutTypeChip(
                        label: 'СБП',
                        selected: _type == 'sbp',
                        onTap: () => setState(() => _type = 'sbp'),
                      ),
                      _PayoutTypeChip(
                        label: 'Счет',
                        selected: _type == 'bank_account',
                        onTap: () => setState(() => _type = 'bank_account'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _recipientController,
                    decoration: const InputDecoration(
                      labelText: 'ID получателя ЮKassa',
                      hintText: 'recipient_...',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _maskedValueController,
                    decoration: InputDecoration(
                      labelText: 'Как показывать в приложении',
                      hintText: _maskedHint(_type),
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _isDefault,
                    onChanged: (value) => setState(() => _isDefault = value),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Сделать основным',
                      style: EvikTypography.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              _InlineError(message: state.errorMessage!),
            ],
            const SizedBox(height: 16),
            EvikButton(
              text: 'Сохранить',
              width: double.infinity,
              isLoading: state.isSubmitting,
              onPressed: state.isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Заполните поле';
    return null;
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;

    try {
      await ref.read(driverWalletProvider.notifier).addPayoutMethod(
            type: _type,
            providerRecipientId: _recipientController.text.trim(),
            maskedValue: _maskedValueController.text.trim(),
            isDefault: _isDefault,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Способ вывода добавлен')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(driverWalletProvider).errorMessage ??
                'Не удалось добавить способ вывода',
          ),
        ),
      );
    }
  }
}

class DriverSubscriptionScreen extends ConsumerWidget {
  const DriverSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverWalletProvider);
    final subscription = state.subscriptionStatus;
    final isActive = subscription?.status == 'active';
    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        title:
            Text('Подписка', style: EvikTypography.h2.copyWith(fontSize: 22)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: _surfaceDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusChip(
                  label: isActive ? 'Активна' : 'Не активна',
                  color: isActive
                      ? AvroDriverColors.success
                      : AvroDriverColors.warning,
                ),
                const SizedBox(height: 14),
                Text('Авро Pro', style: EvikTypography.h2),
                const SizedBox(height: 8),
                Text(
                  'Приоритет в распределении заказов и доступ к финансовым инструментам водителя.',
                  style: EvikTypography.bodyLarge
                      .copyWith(color: AvroDriverColors.tabInactive),
                ),
                const SizedBox(height: 18),
                Text(
                  'Подписка активна',
                  style: EvikTypography.h3
                      .copyWith(color: AvroDriverColors.accent),
                ),
                if (subscription?.periodEnd != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Действует до ${_formatDate(subscription!.periodEnd!)}',
                    style: EvikTypography.bodyMedium.copyWith(
                      color: AvroDriverColors.tabInactive,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                EvikButton(
                  text: isActive ? 'Продлить подписку' : 'Оплатить подписку',
                  width: double.infinity,
                  isLoading: state.isSubmitting,
                  onPressed: () async {
                    try {
                      final url = await ref
                          .read(driverWalletProvider.notifier)
                          .createSubscriptionPayment('pro_month');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            url == null || url.isEmpty
                                ? 'Платеж подписки создан'
                                : 'Платеж создан. Откройте страницу оплаты.',
                          ),
                        ),
                      );
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                ref.read(driverWalletProvider).errorMessage ??
                                    'Не удалось создать платеж')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DriverWalletTransactionsScreen extends ConsumerWidget {
  const DriverWalletTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverWalletProvider);
    final transactions =
        state.wallet?.recentTransactions ?? const <WalletTransaction>[];

    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        title: Text(
          'История операций',
          style: EvikTypography.h2.copyWith(fontSize: 22),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(driverWalletProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (state.errorMessage != null) ...[
              _InlineError(message: state.errorMessage!),
              const SizedBox(height: 12),
            ],
            if (state.isLoading && state.wallet == null) ...[
              const SkeletonCard(height: 84),
              const SkeletonCard(height: 84),
              const SkeletonCard(height: 84),
            ] else if (transactions.isEmpty)
              const EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Операций пока нет',
                subtitle:
                    'После завершенного заказа начисления появятся здесь.',
              )
            else
              _TransactionsList(
                transactions: transactions,
                onTransactionTap: (transaction) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WalletTransactionDetailsScreen(
                        transaction: transaction,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class WalletTransactionDetailsScreen extends StatelessWidget {
  const WalletTransactionDetailsScreen({
    required this.transaction,
    super.key,
  });

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isDebit = transaction.direction == 'debit';
    final amountColor = isDebit ? AvroDriverColors.error : AvroDriverColors.success;

    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        title: Text(
          'Операция',
          style: EvikTypography.h2.copyWith(fontSize: 22),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _surfaceDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: amountColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _transactionIcon(transaction.type),
                        color: amountColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _transactionTitle(transaction),
                            style: EvikTypography.h3.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _transactionSubtitle(transaction),
                            style: EvikTypography.bodySmall.copyWith(
                              fontSize: 13,
                              color: AvroDriverColors.tabInactive,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '${isDebit ? '-' : '+'}${_money(transaction.amount)}',
                  style: EvikTypography.h1.copyWith(
                    fontSize: 34,
                    color: amountColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: _surfaceDecoration(),
            child: Column(
              children: [
                _DetailRow(
                    label: 'Статус', value: _statusLabel(transaction.status)),
                const Divider(height: 1, color: AvroDriverColors.surface),
                _DetailRow(
                  label: 'Тип',
                  value: _transactionTypeLabel(transaction.type),
                ),
                const Divider(height: 1, color: AvroDriverColors.surface),
                _DetailRow(
                  label: 'Направление',
                  value: isDebit ? 'Списание' : 'Зачисление',
                ),
                if (transaction.createdAt != null) ...[
                  const Divider(height: 1, color: AvroDriverColors.surface),
                  _DetailRow(
                    label: 'Дата',
                    value: _formatDateTime(transaction.createdAt!),
                  ),
                ],
                if (transaction.description.isNotEmpty) ...[
                  const Divider(height: 1, color: AvroDriverColors.surface),
                  _DetailRow(
                    label: 'Описание',
                    value: transaction.description,
                  ),
                ],
                const Divider(height: 1, color: AvroDriverColors.surface),
                _DetailRow(label: 'ID', value: transaction.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String title;
  final int amount;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _surfaceDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 18),
          Text(
            _money(amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EvikTypography.h3.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EvikTypography.bodyMedium.copyWith(fontSize: 13),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: EvikTypography.bodySmall.copyWith(
                fontSize: 12,
                color: AvroDriverColors.tabInactive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FinanceActionTile extends StatelessWidget {
  const _FinanceActionTile({
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
    return Material(
      color: AvroDriverColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AvroDriverColors.tabInactive),
          ),
          child: Row(
            children: [
              Icon(icon, color: AvroDriverColors.accent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style:
                            EvikTypography.bodyMedium.copyWith(fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EvikTypography.bodySmall.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AvroDriverColors.tabInactive),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionsList extends StatelessWidget {
  const _TransactionsList({
    required this.transactions,
    this.onTransactionTap,
  });

  final List<WalletTransaction> transactions;
  final ValueChanged<WalletTransaction>? onTransactionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _surfaceDecoration(),
      child: Column(
        children: [
          for (var index = 0; index < transactions.length; index++) ...[
            _TransactionTile(
              transaction: transactions[index],
              onTap: onTransactionTap == null
                  ? null
                  : () => onTransactionTap!(transactions[index]),
            ),
            if (index != transactions.length - 1)
              const Divider(height: 1, color: AvroDriverColors.surface),
          ],
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    this.onTap,
  });

  final WalletTransaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDebit = transaction.direction == 'debit';
    final color = isDebit ? AvroDriverColors.error : AvroDriverColors.success;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_transactionIcon(transaction.type),
                    color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _transactionTitle(transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EvikTypography.bodyMedium.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _transactionSubtitle(transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EvikTypography.bodySmall.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isDebit ? '-' : '+'}${_money(transaction.amount)}',
                style: EvikTypography.bodyMedium
                    .copyWith(color: color, fontSize: 14),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AvroDriverColors.tabInactive,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: EvikTypography.bodySmall.copyWith(
                fontSize: 12,
                color: AvroDriverColors.tabInactive,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: EvikTypography.bodyMedium.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutMethodTile extends StatelessWidget {
  const _PayoutMethodTile({required this.method});

  final DriverPayoutMethod method;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _surfaceDecoration(),
      child: Row(
        children: [
          const Icon(Icons.credit_card_rounded, color: AvroDriverColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_methodType(method.type),
                    style: EvikTypography.bodyMedium.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Text(method.maskedValue,
                    style: EvikTypography.bodySmall.copyWith(fontSize: 12)),
              ],
            ),
          ),
          if (method.isDefault)
            const _StatusChip(
                label: 'Основной', color: AvroDriverColors.success),
        ],
      ),
    );
  }
}

class _PayoutTypeChip extends StatelessWidget {
  const _PayoutTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AvroDriverColors.accent.withValues(alpha: 0.12),
      backgroundColor: AvroDriverColors.surface,
      labelStyle: EvikTypography.bodySmall.copyWith(
        color: selected ? AvroDriverColors.accent : AvroDriverColors.textSecondary,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(
        color: selected ? AvroDriverColors.accent : AvroDriverColors.tabInactive,
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AvroDriverColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AvroDriverColors.info.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AvroDriverColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: EvikTypography.bodyMedium.copyWith(fontSize: 14)),
                const SizedBox(height: 4),
                Text(text,
                    style: EvikTypography.bodySmall
                        .copyWith(fontSize: 12, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AvroDriverColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AvroDriverColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: EvikTypography.bodySmall.copyWith(
                color: AvroDriverColors.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: EvikTypography.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

BoxDecoration _surfaceDecoration() {
  return BoxDecoration(
    color: AvroDriverColors.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AvroDriverColors.tabInactive),
  );
}

String _money(int kopecks) {
  final rubles = kopecks ~/ 100;
  final text = rubles.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ' ',
      );
  return '$text ₽';
}

String _payoutMethodSubtitle(List<DriverPayoutMethod> methods) {
  if (methods.isEmpty) return 'Карта, СБП или банковский счет';
  final primary = methods.firstWhere(
    (method) => method.isDefault,
    orElse: () => methods.first,
  );
  return '${_methodType(primary.type)} · ${primary.maskedValue}';
}

String _subscriptionSubtitle(DriverSubscriptionStatus? status) {
  if (status == null || status.status == 'unknown') return 'Статус не загружен';
  if (status.status == 'active') {
    final periodEnd = status.periodEnd ?? status.endsAt;
    if (periodEnd != null) return 'Активна до ${_formatDate(periodEnd)}';
    return 'Активна';
  }
  if (status.status == 'expired') return 'Истекла';
  if (status.status == 'none') return 'Не активна';
  return 'Не активна';
}

String _maskedHint(String type) {
  return switch (type) {
    'sbp' => '+7 ••• •••-45-67',
    'bank_account' => 'Счет •••• 1234',
    _ => 'Карта •••• 4242',
  };
}

String _transactionsSubtitle(List<WalletTransaction> transactions) {
  if (transactions.isEmpty) return 'Операций пока нет';
  final count = transactions.length;
  return '$count ${_plural(count, 'операция', 'операции', 'операций')}';
}

String _methodType(String type) {
  return switch (type) {
    'sbp' => 'СБП',
    'bank_account' => 'Банковский счет',
    _ => 'Карта',
  };
}

String _transactionTitle(WalletTransaction transaction) {
  return switch (transaction.type) {
    'order_income' => 'Доход за заказ',
    'cash_commission_debt' => 'Удержание комиссии за наличный заказ',
    'debt_repayment' => 'Комиссия удержана из безналичного заказа',
    'pending_to_available' => 'Доступно к выводу',
    'payout' => 'Вывод средств',
    'refund' => 'Возврат',
    'bonus' => 'Бонус',
    'penalty' => 'Штраф',
    _ => transaction.description.isEmpty ? 'Операция' : transaction.description,
  };
}

String _statusLabel(String status) {
  return switch (status) {
    'pending' => 'В обработке',
    'available' => 'Доступно',
    'succeeded' => 'Выполнено',
    'failed' => 'Ошибка',
    _ => status,
  };
}

String _transactionTypeLabel(String type) {
  return switch (type) {
    'order_income' => 'Доход за заказ',
    'commission' => 'Комиссия',
    'cash_commission_debt' => 'Комиссия за наличный заказ',
    'debt_repayment' => 'Удержание комиссии',
    'pending_to_available' => 'Перевод в доступные',
    'payout' => 'Вывод средств',
    'refund' => 'Возврат',
    'adjustment' => 'Корректировка',
    'subscription_payment' => 'Подписка',
    'bonus' => 'Бонус',
    'penalty' => 'Штраф',
    _ => type,
  };
}

String _transactionSubtitle(WalletTransaction transaction) {
  final status = _statusLabel(transaction.status);
  final date = transaction.createdAt;
  if (date == null) return status;
  return '$status · ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
}

String _formatDateTime(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month.$year, $hour:$minute';
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();
  return '$day.$month.$year';
}

String _plural(int count, String one, String few, String many) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

IconData _transactionIcon(String type) {
  return switch (type) {
    'order_income' => Icons.local_shipping_rounded,
    'cash_commission_debt' => Icons.receipt_long_rounded,
    'debt_repayment' => Icons.payments_rounded,
    'pending_to_available' => Icons.check_circle_rounded,
    'payout' => Icons.account_balance_rounded,
    'refund' => Icons.undo_rounded,
    _ => Icons.swap_vert_rounded,
  };
}
