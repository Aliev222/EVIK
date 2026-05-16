import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/onboarding/presentation/screens/role_selection_screen.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';

class ClientProfileScreen extends ConsumerWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: EvikColors.gray50,
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
            color: EvikColors.primaryBlack,
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
              color: EvikColors.primaryWhite,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                      color: EvikColors.accentOrange,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'А',
                      style: EvikTypography.h3.copyWith(
                        color: EvikColors.primaryWhite,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Алексей Иванов',
                            style:
                                EvikTypography.h3.copyWith(fontSize: 34 / 2)),
                        const SizedBox(height: 2),
                        Text('+7 (999) 123-45-67',
                            style: EvikTypography.bodyMedium
                                .copyWith(color: EvikColors.gray600)),
                        const SizedBox(height: 4),
                        Text('★★★★☆ 4.0 · 7 поездок',
                            style: EvikTypography.bodySmall.copyWith(
                                color: const Color(0xFFF59E0B),
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: EvikColors.gray200),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  _ProfileTile(
                    icon: Icons.notifications_none,
                    title: 'Уведомления',
                    subtitle: 'SMS, Push-уведомления',
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
                    subtitle: 'Чат, email, телефон',
                    onTap: () => _openSupport(context),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(authProvider.notifier).signOut();
                        // Очищаем выбранную роль чтобы попасть на экран выбора роли
                        ref
                            .read(selectedOnboardingRoleProvider.notifier)
                            .state = null;
                      },
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: EvikColors.primaryWhite,
                        foregroundColor: EvikColors.primaryBlack,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Выйти из аккаунта',
                          style: EvikTypography.h3.copyWith(fontSize: 36 / 2)),
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

  void _openNotifications(BuildContext context) => _showFeatureSheet(
        context,
        'Уведомления',
        Icons.notifications_none,
        const ['Push-уведомления', 'SMS о заказах', 'Новости и акции'],
      );

  void _openEmergency(BuildContext context) => _showFeatureSheet(
        context,
        'Экстренная связь',
        Icons.health_and_safety_outlined,
        const ['112', 'ГИБДД', 'Скорая помощь'],
      );

  void _openSupport(BuildContext context) => _showFeatureSheet(
        context,
        'Поддержка',
        Icons.chat_bubble_outline,
        const ['Чат с оператором', 'Позвонить в поддержку', 'Написать email'],
      );

  void _showFeatureSheet(
    BuildContext context,
    String title,
    IconData icon,
    List<String> options,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FeatureBottomSheet(
        title: title,
        icon: icon,
        options: options,
      ),
    );
  }
}

class _FeatureBottomSheet extends StatelessWidget {
  const _FeatureBottomSheet({
    required this.title,
    required this.icon,
    required this.options,
  });

  final String title;
  final IconData icon;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: EvikColors.gray100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: EvikColors.accentOrange),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: EvikTypography.h3)),
              ],
            ),
            const SizedBox(height: 16),
            ...options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  minTileHeight: 54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: EvikColors.gray50,
                  title: Text(
                    option,
                    style: EvikTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: Text(
                    'Скоро',
                    style: EvikTypography.bodySmall.copyWith(
                      color: EvikColors.gray500,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$option будет доступно позже.')),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: child,
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
    return Material(
      color: EvikColors.primaryWhite,
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
                  color: EvikColors.gray100,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: EvikColors.gray800),
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
                            .copyWith(color: EvikColors.gray700)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: EvikColors.gray600),
            ],
          ),
        ),
      ),
    );
  }
}
