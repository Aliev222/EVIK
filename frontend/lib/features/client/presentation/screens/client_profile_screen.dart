import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_wallet_screen.dart';
import 'package:tow_truck_frontend/shared/widgets/feature_announcement_sheet.dart';
import 'package:tow_truck_frontend/shared/widgets/offline_sos_screen.dart';

class ClientProfileScreen extends ConsumerWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      backgroundColor: AvroClientColors.background,
      appBar: AppBar(
        title: Text(
          'Профиль',
          style: EvikTypography.h2.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AvroClientColors.textPrimary,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AvroClientColors.background,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                      color: AvroClientColors.accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      user?.fullName.isNotEmpty == true
                          ? user!.fullName[0].toUpperCase()
                          : '?',
                      style: EvikTypography.h3.copyWith(
                        color: AvroClientColors.background,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.fullName ?? 'Неизвестный',
                            style:
                                EvikTypography.h3.copyWith(fontSize: 34 / 2)),
                        const SizedBox(height: 2),
                        Text(user?.phone ?? '',
                            style: EvikTypography.bodyMedium
                                .copyWith(color: AvroClientColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text('Клиент Авро',
                            style: EvikTypography.bodySmall.copyWith(
                                color: AvroClientColors.warning,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AvroClientColors.surface),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  _ProfileTile(
                    icon: Icons.notifications_none,
                    title: 'Уведомления',
                    subtitle: 'Оповещения о статусе заказа',
                    comingSoon: true,
                    onTap: () => _openNotifications(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Экстренная связь',
                    subtitle: '112 · ГАИ · Скорая',
                    onTap: () => _openEmergency(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.chat_bubble_outline,
                    title: 'Поддержка',
                    subtitle: 'Связь с оператором Авро',
                    comingSoon: true,
                    onTap: () => _openSupport(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.credit_card_outlined,
                    title: 'Способы оплаты',
                    subtitle: 'Карты, промокоды',
                    onTap: () => _openWallet(context),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Выход'),
                            content: const Text('Вы уверены что хотите выйти?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Отмена'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  ref.read(authProvider.notifier).signOut();
                                },
                                child: const Text(
                                  'Выйти',
                                  style: TextStyle(color: AvroClientColors.error),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AvroClientColors.background,
                        foregroundColor: AvroClientColors.error,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Выйти из аккаунта',
                          style: TextStyle(
                            color: AvroClientColors.error,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          )),
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

  void _openWallet(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClientWalletScreen()),
    );
  }

  void _openNotifications(BuildContext context) {
    FeatureAnnouncementSheet.show(
      context,
      const FeatureAnnouncementSheet(
        title: 'Уведомления',
        icon: Icons.notifications_none,
        description:
            'Будем сообщать о статусе заказа: push и SMS, когда эвакуатор '
            'назначен, в пути и работа завершена.',
        items: [
          'Push-уведомления о заказе',
          'SMS о статусе эвакуатора',
          'Новости и акции',
        ],
      ),
    );
  }

  void _openEmergency(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const OfflineSosScreen(isSosOnly: true),
      ),
    );
  }

  void _openSupport(BuildContext context) {
    FeatureAnnouncementSheet.show(
      context,
      const FeatureAnnouncementSheet(
        title: 'Поддержка',
        icon: Icons.chat_bubble_outline,
        description:
            'Оператор поможет с заказом, оплатой и нештатными ситуациями: '
            'чат, звонок или email.',
        items: [
          'Чат с оператором',
          'Позвонить в поддержку',
          'Написать email',
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.comingSoon = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AvroClientColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: AvroClientColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: EvikTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w700, height: 1.2)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: EvikTypography.bodySmall
                            .copyWith(color: AvroClientColors.textSecondary)),
                  ],
                ),
              ),
              if (comingSoon) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AvroClientColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'скоро',
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroClientColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right, color: AvroClientColors.tabInactive),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
