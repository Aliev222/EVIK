import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../../shared/widgets/skeleton_card.dart';
import '../../domain/entities/payment_wallet.dart';
import '../providers/client_payment_methods_provider.dart';
import '../providers/payment_wallet_provider.dart';

class ClientWalletScreen extends ConsumerStatefulWidget {
  const ClientWalletScreen({super.key});

  @override
  ConsumerState<ClientWalletScreen> createState() => _ClientWalletScreenState();
}

class _ClientWalletScreenState extends ConsumerState<ClientWalletScreen>
    with WidgetsBindingObserver {
  bool _refreshOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_refreshOnResume || state != AppLifecycleState.resumed) return;
    _refreshOnResume = false;
    ref.read(clientPaymentMethodsProvider.notifier).load();
    ref.read(paymentWalletProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final cardsState = ref.watch(clientPaymentMethodsProvider);
    final walletState = ref.watch(paymentWalletProvider);

    return Scaffold(
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        title: Text('Оплата', style: EvikTypography.h2.copyWith(fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: EvikColors.primaryBlack,
                  size: 20,
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(clientPaymentMethodsProvider.notifier).load();
          await ref.read(paymentWalletProvider.notifier).load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: [
            _PaymentMethodsSection(
              cardsState: cardsState,
              onExternalConfirmationStarted: () {
                _refreshOnResume = true;
              },
            ),
            if ((walletState.wallet?.payments ?? const []).isNotEmpty) ...[
              const SizedBox(height: 12),
              _PaymentHistorySection(wallet: walletState.wallet),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodsSection extends ConsumerWidget {
  const _PaymentMethodsSection({
    required this.cardsState,
    required this.onExternalConfirmationStarted,
  });

  final AsyncValue<List<PaymentCard>> cardsState;
  final VoidCallback onExternalConfirmationStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: _surfaceDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.credit_card_rounded,
                color: EvikColors.accentOrange,
              ),
              const SizedBox(width: 10),
              Text('Способы оплаты', style: EvikTypography.h3),
            ],
          ),
          const SizedBox(height: 14),
          cardsState.when(
            loading: () => const Column(
              children: [
                SkeletonCard(height: 76),
                SkeletonCard(height: 76),
              ],
            ),
            error: (error, _) => ErrorState(
              message: 'Не удалось загрузить карты',
              onRetry: () =>
                  ref.read(clientPaymentMethodsProvider.notifier).load(),
            ),
            data: (cards) {
              if (cards.isEmpty) {
                return EmptyState(
                  icon: Icons.credit_card_off_rounded,
                  title: 'У вас пока нет сохранённых карт',
                  subtitle: 'Добавьте карту через защищённую страницу ЮKassa.',
                  buttonText: 'Добавить карту',
                  onButtonTap: () => _initAddCard(context, ref),
                );
              }
              return Column(
                children: [
                  for (final card in cards) ...[
                    _PaymentCardTile(
                      card: card,
                      onMenuTap: () => _openCardActions(context, ref, card),
                    ),
                    if (card != cards.last) const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  EvikButton(
                    text: 'Добавить карту',
                    icon: const Icon(Icons.add_rounded, size: 18),
                    width: double.infinity,
                    variant: EvikButtonVariant.ghost,
                    onPressed: () => _initAddCard(context, ref),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openCardActions(
    BuildContext context,
    WidgetRef ref,
    PaymentCard card,
  ) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!card.isDefault)
                _ActionSheetTile(
                  icon: Icons.star_rounded,
                  title: 'Сделать основной',
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await ref
                        .read(clientPaymentMethodsProvider.notifier)
                        .setDefault(card.id);
                  },
                ),
              _ActionSheetTile(
                icon: Icons.delete_outline_rounded,
                title: 'Удалить',
                color: EvikColors.errorRed,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDeleteCard(context, ref, card);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCard(
    BuildContext context,
    WidgetRef ref,
    PaymentCard card,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить карту?'),
        content: Text('${card.displayBrand} •••• ${card.last4} будет удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(clientPaymentMethodsProvider.notifier).deleteCard(card.id);
  }

  Future<void> _initAddCard(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    try {
      final paymentMethodId =
          await ref.read(clientPaymentMethodsProvider.notifier).addCard();
      onExternalConfirmationStarted();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ожидаем подтверждения карты: ${paymentMethodId.substring(0, 8)}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyAddCardError(error))),
      );
    }
  }

  String _friendlyAddCardError(Object error) {
    final text = error.toString();
    if (text.contains('yookassa credentials are not configured')) {
      return 'ЮKassa не настроена для dev-окружения';
    }
    return 'Не удалось открыть добавление карты';
  }
}

class _PaymentCardTile extends StatelessWidget {
  const _PaymentCardTile({
    required this.card,
    required this.onMenuTap,
  });

  final PaymentCard card;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: card.isDefault ? EvikColors.accentOrange : EvikColors.gray200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: EvikColors.accentOrange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.credit_card_rounded,
              color: EvikColors.accentOrange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${card.displayBrand} •••• ${card.last4}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EvikTypography.bodyMedium.copyWith(fontSize: 15),
                      ),
                    ),
                    if (card.isDefault) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.star_rounded,
                        color: EvikColors.accentOrange,
                        size: 18,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  card.isDefault ? 'По умолчанию' : card.expiresAt,
                  style: EvikTypography.bodySmall.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onMenuTap,
            icon: const Icon(Icons.more_vert_rounded),
            color: EvikColors.gray600,
          ),
        ],
      ),
    );
  }
}

class _PaymentHistorySection extends StatelessWidget {
  const _PaymentHistorySection({required this.wallet});

  final PaymentWallet? wallet;

  @override
  Widget build(BuildContext context) {
    final payments = wallet?.payments ?? const <PaymentTransaction>[];
    final visiblePayments = payments.take(5).toList();
    return Container(
      decoration: _surfaceDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: EvikColors.accentOrange,
              ),
              const SizedBox(width: 10),
              Text('История платежей', style: EvikTypography.h3),
            ],
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < visiblePayments.length; index++) ...[
            _PaymentRow(payment: visiblePayments[index]),
            if (index != visiblePayments.length - 1)
              const Divider(height: 18, color: EvikColors.gray100),
          ],
        ],
      ),
    );
  }
}

class _ActionSheetTile extends StatelessWidget {
  const _ActionSheetTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color = EvikColors.primaryBlack,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title:
          Text(title, style: EvikTypography.bodyMedium.copyWith(color: color)),
      onTap: onTap,
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final PaymentTransaction payment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payment.title,
                style: EvikTypography.bodyMedium.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 3),
              Text(
                _formatDate(payment.createdAt),
                style: EvikTypography.bodySmall.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          '${payment.amount} ₽',
          style: EvikTypography.bodyMedium.copyWith(fontSize: 14),
        ),
      ],
    );
  }
}

BoxDecoration _surfaceDecoration() {
  return BoxDecoration(
    color: EvikColors.primaryWhite,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: EvikColors.gray200),
  );
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month';
}
