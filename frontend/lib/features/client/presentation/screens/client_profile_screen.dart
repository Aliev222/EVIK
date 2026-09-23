import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/client/presentation/screens/client_wallet_screen.dart';
import 'package:tow_truck_frontend/shared/widgets/feature_announcement_sheet.dart';
import 'package:tow_truck_frontend/shared/widgets/offline_sos_screen.dart';
import 'package:tow_truck_frontend/shared/widgets/account_settings_tiles.dart';

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
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AvroClientColors.accent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        'assets/img/app_icon_load.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Клиент Авро',
                            style: EvikTypography.h3.copyWith(fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(user?.phone ?? 'Номер телефона не указан',
                            style: EvikTypography.bodyMedium.copyWith(
                                color: AvroClientColors.textSecondary)),
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
                  const _ProfileSectionTitle('АККАУНТ'),
                  const SizedBox(height: 8),
                  _ProfileTile(
                    icon: Icons.notifications_none,
                    title: 'Уведомления',
                    subtitle: 'Оповещения о статусе заказа',
                    onTap: () => _openNotifications(context),
                  ),
                  const SizedBox(height: 12),
                  _ProfileTile(
                    icon: Icons.credit_card_outlined,
                    title: 'Способы оплаты',
                    subtitle: 'Карты, промокоды',
                    onTap: () => _openWallet(context),
                  ),
                  const SizedBox(height: 24),
                  const _ProfileSectionTitle('ПОМОЩЬ'),
                  const SizedBox(height: 8),
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
                    onTap: () => _openSupport(context),
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
                  const SizedBox(height: 24),
                  const LegalLinksTile(
                    backgroundColor: AvroClientColors.background,
                    textPrimaryColor: AvroClientColors.textPrimary,
                    textSecondaryColor: AvroClientColors.textSecondary,
                    iconColor: AvroClientColors.accent,
                  ),
                  const SizedBox(height: 16),
                  DeleteAccountEntry(
                    backgroundColor: AvroClientColors.background,
                    destructiveColor: AvroClientColors.error,
                    warningMessage: 'Аккаунт будет удалён без возможности '
                        'восстановления. Это действие необратимо.',
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
              const Icon(Icons.chevron_right, color: AvroClientColors.tabInactive),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: EvikTypography.bodySmall.copyWith(
          color: AvroClientColors.textSecondary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      );
}
