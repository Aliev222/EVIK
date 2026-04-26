import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../onboarding/presentation/screens/role_selection_screen.dart';

class DriverProfileScreen extends ConsumerWidget {
  const DriverProfileScreen({super.key});

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        child: Column(
          children: [
            // Header с информацией о водителе
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: EvikColors.primaryWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: EvikColors.primaryBlack,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        'М',
                        style: TextStyle(
                          color: EvikColors.primaryWhite,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Михаил Соколов',
                          style: EvikTypography.h3.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: EvikColors.warningAmber,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '4.9',
                              style: EvikTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '• 148 заказов',
                              style: EvikTypography.bodySmall.copyWith(
                                color: EvikColors.gray500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '+7 (916) 234-56-78',
                          style: EvikTypography.bodyMedium.copyWith(
                            color: EvikColors.gray500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: EvikColors.successGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Стаж\n2 года',
                      style: EvikTypography.bodySmall.copyWith(
                        color: EvikColors.successGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Меню опций
            ...[
              _ProfileMenuItem(
                icon: Icons.local_shipping_outlined,
                title: 'Мой эвакуатор',
                subtitle: 'КАМАЗ 65117 • А 234 КО 77',
                onTap: () => _openVehicleInfo(context),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.description_outlined,
                title: 'Документы',
                subtitle: 'Все документы действительны',
                onTap: () => _showDriverFeature(context, 'Документы', const [
                  'Водительское удостоверение: проверено',
                  'СТС: проверено',
                  'Лицензия перевозчика: активна',
                  'Медицинская справка: до 20.12.2025',
                ]),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.notifications_outlined,
                title: 'Уведомления',
                subtitle: 'Новые заказы, выплаты',
                onTap: () => _showDriverFeature(context, 'Уведомления', const [
                  'Новые заказы: включены',
                  'Выплаты: включены',
                  'Новости сервиса: отключены',
                ]),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.credit_card_outlined,
                title: 'Реквизиты',
                subtitle: 'Сбербанк •••• 4242',
                onTap: () => _showDriverFeature(context, 'Реквизиты', const [
                  'Банк: Сбербанк',
                  'Карта: •••• 4242',
                  'Выплаты: ежедневно',
                  'Минимальная сумма: 500 ₽',
                ]),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.security_outlined,
                title: 'Страхование',
                subtitle: 'ОСАГО до 01.2026',
                onTap: () => _showDriverFeature(context, 'Страхование', const [
                  'ОСАГО: активно до 01.2026',
                  'Полис: ХХХ 1234567890',
                  'Страховая: АльфаСтрахование',
                ]),
              ),
              const SizedBox(height: 12),
              _ProfileMenuItem(
                icon: Icons.support_agent_outlined,
                title: 'Поддержка водителей',
                subtitle: '24/7 • Приоритетная линия',
                onTap: () =>
                    _showDriverFeature(context, 'Поддержка водителей', const [
                  'Чат с диспетчером',
                  'Приоритетная линия: +7 (800) 555-35-35',
                  'Вопрос по выплатам',
                ]),
              ),
            ],

            const SizedBox(height: 32),

            // Кнопка выхода
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: EvikColors.primaryWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ref.read(authProvider.notifier).signOut();
                    // Очищаем выбранную роль чтобы попасть на экран выбора роли
                    ref.read(selectedOnboardingRoleProvider.notifier).state =
                        null;
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Выйти из аккаунта',
                        style: EvikTypography.bodyMedium.copyWith(
                          color: EvikColors.errorRed,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openVehicleInfo(BuildContext context) => _showDriverFeature(
        context,
        'Мой эвакуатор',
        const [
          'Модель: КАМАЗ 65117',
          'Грузоподъемность: 8 тонн',
          'Государственный номер: А 234 КО 77',
          'Техосмотр до: 15.08.2025',
        ],
      );

  void _showDriverFeature(
    BuildContext context,
    String title,
    List<String> options,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DriverFeatureSheet(
        title: title,
        options: options,
      ),
    );
  }
}

class _DriverFeatureSheet extends StatelessWidget {
  const _DriverFeatureSheet({
    required this.title,
    required this.options,
  });

  final String title;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: EvikTypography.h3)),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...options.map(
              (option) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: EvikColors.gray50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: EvikColors.gray200),
                ),
                child: Text(
                  option,
                  style: EvikTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: EvikColors.gray100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: EvikColors.gray600,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: EvikTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: EvikTypography.bodySmall.copyWith(
                          color: EvikColors.gray500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: EvikColors.gray400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
