import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../auth/domain/entities/user.dart';

final selectedOnboardingRoleProvider = StateProvider<UserRole?>((ref) => null);

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  final _roles = [
    const _RoleData(
      id: UserRole.client,
      backgroundColor: EvikColors.primaryWhite,
      textColor: EvikColors.primaryBlack,
      tag: 'Для владельцев авто',
      icon: '🚗',
      title: 'Нужен\nэвакуатор?',
      subtitle: 'Вызовите за 30 секунд.\nВодитель приедет\nв течение 15 минут.',
      ctaText: 'Вызвать эвакуатор',
      switchLabel: 'Я водитель →',
      stats: [
        {'value': '< 15 мин', 'label': 'среднее время'},
        {'value': '4.9 ★', 'label': 'рейтинг'},
        {'value': '24/7', 'label': 'работаем'},
      ],
    ),
    const _RoleData(
      id: UserRole.driver,
      backgroundColor: EvikColors.primaryBlack,
      textColor: EvikColors.primaryWhite,
      tag: 'Для водителей',
      icon: '🚛',
      title: 'Зарабатывай\nна эвакуации',
      subtitle: 'Принимай заказы рядом.\nСвободный график,\nстабильный доход.',
      ctaText: 'Начать работать',
      switchLabel: '← Я клиент',
      stats: [
        {'value': '6 200 ₽', 'label': 'в среднем/день'},
        {'value': '148', 'label': 'заказов/мес'},
        {'value': 'Свой', 'label': 'график'},
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: _roles.length,
        itemBuilder: (context, index) {
          final role = _roles[index];
          return _buildRoleCard(context, role, index);
        },
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, _RoleData role, int index) {
    final cardIndex = index;

    return Container(
      decoration: BoxDecoration(color: role.backgroundColor),
      child: Stack(
        children: [
          // Декоративные круги
          Positioned(
            right: -60,
            top: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EvikColors.accentOrange.withValues(
                  alpha: cardIndex == 0 ? 0.07 : 0.13,
                ),
              ),
            ),
          ),
          Positioned(
            left: -90,
            bottom: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EvikColors.accentOrange.withValues(
                  alpha: cardIndex == 0 ? 0.04 : 0.08,
                ),
              ),
            ),
          ),

          Column(
            children: [
              // Header с точками
              Padding(
                padding: const EdgeInsets.only(top: 18, left: 24, right: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'EVIK',
                      style: EvikTypography.h3.copyWith(
                        color: role.textColor,
                        fontSize: 20,
                        letterSpacing: -0.03,
                      ),
                    ),
                    Row(children: _buildDots()),
                  ],
                ),
              ),

              // Tag pill
              Container(
                margin: const EdgeInsets.only(left: 24, top: 22),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cardIndex == 0
                          ? EvikColors.gray100
                          : EvikColors.primaryWhite.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(role.icon, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 7),
                        Text(
                          role.tag,
                          style: EvikTypography.caption.copyWith(
                            color: cardIndex == 0
                                ? EvikColors.gray500
                                : EvikColors.primaryWhite
                                    .withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    role.title,
                    style: EvikTypography.h1.copyWith(color: role.textColor),
                  ),
                ),
              ),

              // Subtitle
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    role.subtitle,
                    style: EvikTypography.bodyLarge.copyWith(
                      color: role.textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),

              // Stats
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, top: 28),
                child: Row(
                  children: role.stats.asMap().entries.map((entry) {
                    final statIndex = entry.key;
                    final stat = entry.value;
                    final isLast = statIndex == role.stats.length - 1;

                    return Expanded(
                      child: Container(
                        padding: EdgeInsets.only(right: isLast ? 0 : 14),
                        decoration: isLast
                            ? null
                            : BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: cardIndex == 0
                                        ? EvikColors.gray200
                                        : EvikColors.primaryWhite.withValues(
                                            alpha: 0.1,
                                          ),
                                    width: 1,
                                  ),
                                ),
                              ),
                        margin: EdgeInsets.only(right: isLast ? 0 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stat['value']!,
                              style: EvikTypography.bodyMedium.copyWith(
                                color: role.textColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              stat['label']!,
                              style: EvikTypography.caption.copyWith(
                                color: cardIndex == 0
                                    ? EvikColors.gray500
                                    : EvikColors.primaryWhite
                                        .withValues(alpha: 0.35),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const Spacer(),

              // CTA
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    EvikButton(
                      text: role.ctaText,
                      onPressed: () => _selectRole(role.id),
                      width: double.infinity,
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index == 0 ? 1 : 0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          role.switchLabel,
                          style: EvikTypography.bodyMedium.copyWith(
                            color: cardIndex == 0
                                ? EvikColors.gray500
                                : EvikColors.primaryWhite
                                    .withValues(alpha: 0.38),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDots() {
    return _roles.asMap().entries.map((entry) {
      final index = entry.key;
      final isActive = index == _currentIndex;

      return Container(
        margin: const EdgeInsets.only(left: 5),
        width: isActive ? 22 : 6,
        height: 6,
        decoration: BoxDecoration(
          color: isActive ? EvikColors.accentOrange : EvikColors.gray200,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }).toList();
  }

  void _selectRole(UserRole role) {
    ref.read(selectedOnboardingRoleProvider.notifier).state = role;
  }
}

class _RoleData {
  final UserRole id;
  final Color backgroundColor;
  final Color textColor;
  final String tag;
  final String icon;
  final String title;
  final String subtitle;
  final String ctaText;
  final String switchLabel;
  final List<Map<String, String>> stats;

  const _RoleData({
    required this.id,
    required this.backgroundColor,
    required this.textColor,
    required this.tag,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ctaText,
    required this.switchLabel,
    required this.stats,
  });
}
