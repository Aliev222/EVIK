import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors, AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';

import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';

UserRole? _initialRoleFromEnvironment() {
  const rawRole = String.fromEnvironment('EVIK_INITIAL_ROLE');
  return switch (rawRole) {
    'client' => UserRole.client,
    'driver' => UserRole.driver,
    _ => null,
  };
}

final selectedOnboardingRoleProvider =
    StateProvider<UserRole?>((ref) => _initialRoleFromEnvironment());

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  static const _roles = [
    _RoleData(
      id: UserRole.client,
      backgroundColor: AvroClientColors.background,
      textColor: AvroClientColors.textPrimary,
      tag: 'Для владельцев авто',
      icon: 'assets/img/rolecar.png',
      title: 'Нужен\nэвакуатор?',
      subtitle: 'Вызовите эвакуатор онлайн.\nСледите за водителем\nна карте в реальном времени.',
      ctaText: 'Вызвать эвакуатор',
      switchLabel: 'Я водитель ->',
      stats: [
        _RoleStat(value: 'GPS', label: 'трекинг\nводителя'),
        _RoleStat(value: 'Онлайн', label: 'оплата\nкартой'),
        _RoleStat(value: 'Чек', label: 'после\nоплаты'),
      ],
    ),
    _RoleData(
      id: UserRole.driver,
      backgroundColor: AvroDriverColors.darkBlue,
      textColor: AvroClientColors.background,
      tag: 'Для водителей',
      icon: 'assets/img/rolecar2.png',
      title: 'Зарабатывай\nна эвакуации',
      subtitle:
          'Принимай заказы поблизости.\nСвободный график,\nпрозрачный заработок.',
      ctaText: 'Начать работать',
      switchLabel: '<- Я клиент',
      stats: [
        _RoleStat(value: 'Гибкий', label: 'график'),
        _RoleStat(value: 'Вывод', label: 'на карту'),
        _RoleStat(value: 'Прозрачно', label: 'комиссия'),
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
      backgroundColor: AvroClientColors.background,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemCount: _roles.length,
          itemBuilder: (context, index) {
            return _RolePage(
              role: _roles[index],
              index: index,
              currentIndex: _currentIndex,
              rolesCount: _roles.length,
              onRoleSelected: _selectRole,
              onSwitchRole: () {
                _pageController.animateToPage(
                  index == 0 ? 1 : 0,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOutCubic,
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _selectRole(UserRole role) {
    ref.read(selectedOnboardingRoleProvider.notifier).state = role;
  }
}

class _RolePage extends StatelessWidget {
  const _RolePage({
    required this.role,
    required this.index,
    required this.currentIndex,
    required this.rolesCount,
    required this.onRoleSelected,
    required this.onSwitchRole,
  });

  final _RoleData role;
  final int index;
  final int currentIndex;
  final int rolesCount;
  final ValueChanged<UserRole> onRoleSelected;
  final VoidCallback onSwitchRole;

  @override
  Widget build(BuildContext context) {
    final isDarkCard = index == 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final compact = height < 760;
        final veryCompact = height < 660;

        final horizontalPadding = (width * 0.08).clamp(24.0, 40.0);
        final topGap = veryCompact ? 14.0 : (compact ? 20.0 : 32.0);
        final heroGap = veryCompact ? 14.0 : (compact ? 24.0 : 48.0);
        final imageHeight = veryCompact ? 74.0 : (compact ? 92.0 : 120.0);
        final imageWidth = veryCompact ? 198.0 : (compact ? 222.0 : 250.0);
        final blockGap = veryCompact ? 10.0 : (compact ? 14.0 : 24.0);
        final smallGap = veryCompact ? 6.0 : (compact ? 10.0 : 16.0);
        final titleFont = veryCompact ? 34.0 : (compact ? 40.0 : 48.0);
        final subtitleFont = veryCompact ? 13.0 : (compact ? 15.0 : 18.0);
        final subtitleLineHeight = veryCompact ? 1.25 : (compact ? 1.35 : 1.6);
        final statsHeight = veryCompact ? 88.0 : (compact ? 102.0 : 112.0);
        final statsPadding = veryCompact ? 8.0 : (compact ? 11.0 : 20.0);
        final statValueFont = veryCompact ? 14.0 : (compact ? 17.0 : 20.0);
        final statLabelFont = veryCompact ? 9.0 : (compact ? 10.0 : 12.0);
        final buttonHeight = veryCompact ? 52.0 : (compact ? 58.0 : 64.0);
        final switchFont = veryCompact ? 13.0 : (compact ? 14.0 : 16.0);
        final bottomGap = veryCompact ? 8.0 : (compact ? 12.0 : 24.0);

        return Container(
          decoration: BoxDecoration(
              gradient: isDarkCard
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AvroDriverColors.darkBlue,
                        AvroDriverColors.background,
                        AvroDriverColors.surface,
                      ],
                      stops: [0, 0.58, 1],
                    )
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AvroClientColors.background,
                        AvroClientColors.background,
                        AvroClientColors.surface,
                      ],
                    )),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: topGap),
              _Header(
                isDarkCard: isDarkCard,
                currentIndex: currentIndex,
                rolesCount: rolesCount,
              ),
              SizedBox(height: heroGap),
              _RoleImage(
                role: role,
                isDarkCard: isDarkCard,
                width: imageWidth,
                height: imageHeight,
              ),
              SizedBox(height: blockGap),
              _Tag(role: role, isDarkCard: isDarkCard),
              SizedBox(height: smallGap),
              Text(
                role.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: EvikTypography.h1.copyWith(
                  color: role.textColor,
                  fontSize: titleFont,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: smallGap),
              Text(
                role.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: EvikTypography.bodyLarge.copyWith(
                  color: isDarkCard
                      ? role.textColor.withValues(alpha: 0.82)
                      : AvroClientColors.textSecondary,
                  height: subtitleLineHeight,
                  fontSize: subtitleFont,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: blockGap),
              SizedBox(
                height: statsHeight,
                child: _StatsCard(
                  role: role,
                  isDarkCard: isDarkCard,
                  padding: statsPadding,
                  valueFontSize: statValueFont,
                  labelFontSize: statLabelFont,
                ),
              ),
              const Expanded(child: SizedBox()),
              SizedBox(
                height: buttonHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: isDarkCard
                            ? Colors.black.withValues(alpha: 0.18)
                            : AvroClientColors.accent.withValues(alpha: 0.20),
                        blurRadius: isDarkCard ? 26 : 18,
                        spreadRadius: isDarkCard ? -8 : -4,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: EvikButton(
                    text: role.ctaText,
                    onPressed: () => onRoleSelected(role.id),
                    width: double.infinity,
                  ),
                ),
              ),
              SizedBox(height: veryCompact ? 6 : 12),
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onSwitchRole,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: veryCompact ? 6 : 10,
                    ),
                    child: Text(
                      role.switchLabel,
                      style: EvikTypography.bodyMedium.copyWith(
                        color: isDarkCard
                            ? AvroDriverColors.textSecondary.withValues(alpha: 0.7)
                            : AvroClientColors.tabInactive,
                        fontWeight: FontWeight.w700,
                        fontSize: switchFont,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: bottomGap),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isDarkCard,
    required this.currentIndex,
    required this.rolesCount,
  });

  final bool isDarkCard;
  final int currentIndex;
  final int rolesCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isDarkCard
                  ? AvroDriverColors.textSecondary.withValues(alpha: 0.10)
                  : AvroClientColors.background,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDarkCard
                    ? AvroDriverColors.textSecondary.withValues(alpha: 0.06)
                    : AvroClientColors.surface.withValues(alpha: 0.75),
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withValues(alpha: isDarkCard ? 0.07 : 0.04),
                  blurRadius: isDarkCard ? 22 : 16,
                  spreadRadius: -6,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              'Авро',
              style: EvikTypography.caption.copyWith(
                color:
                    isDarkCard ? AvroDriverColors.textSecondary : AvroClientColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Row(
            children: List.generate(rolesCount, (index) {
              final active = index == currentIndex;
              return Container(
                margin: const EdgeInsets.only(left: 8),
                width: active ? 32 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: active
                      ? AvroClientColors.accent
                      : isDarkCard
                          ? AvroDriverColors.textSecondary.withValues(alpha: 0.28)
                          : AvroClientColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color:
                                AvroClientColors.accent.withValues(alpha: 0.20),
                            blurRadius: 12,
                            spreadRadius: -3,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _RoleImage extends StatelessWidget {
  const _RoleImage({
    required this.role,
    required this.isDarkCard,
    required this.width,
    required this.height,
  });

  final _RoleData role;
  final bool isDarkCard;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDarkCard
            ? AvroDriverColors.textSecondary.withValues(alpha: 0.07)
            : AvroClientColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkCard
              ? AvroClientColors.accent.withValues(alpha: 0.24)
              : AvroClientColors.accent.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: isDarkCard
                ? Colors.black.withValues(alpha: 0.13)
                : AvroClientColors.accent.withValues(alpha: 0.08),
            blurRadius: isDarkCard ? 30 : 18,
            spreadRadius: isDarkCard ? -10 : -4,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Image.asset(role.icon, fit: BoxFit.contain),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.role,
    required this.isDarkCard,
  });

  final _RoleData role;
  final bool isDarkCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkCard
            ? AvroDriverColors.textSecondary.withValues(alpha: 0.10)
            : AvroClientColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkCard
              ? AvroDriverColors.textSecondary.withValues(alpha: 0.05)
              : AvroClientColors.surface.withValues(alpha: 0.65),
        ),
      ),
      child: Text(
        role.tag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: EvikTypography.caption.copyWith(
          color: isDarkCard
              ? AvroDriverColors.textSecondary.withValues(alpha: 0.85)
              : AvroClientColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.role,
    required this.isDarkCard,
    required this.padding,
    required this.valueFontSize,
    required this.labelFontSize,
  });

  final _RoleData role;
  final bool isDarkCard;
  final double padding;
  final double valueFontSize;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: isDarkCard
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AvroDriverColors.textSecondary.withValues(alpha: 0.075),
                  AvroDriverColors.textSecondary.withValues(alpha: 0.035),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AvroClientColors.background, AvroClientColors.accent.withValues(alpha: 0.04)],
              ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AvroClientColors.accent
              .withValues(alpha: isDarkCard ? 0.62 : 0.70),
        ),
        boxShadow: [
          BoxShadow(
            color: AvroClientColors.accent
                .withValues(alpha: isDarkCard ? 0.055 : 0.13),
            blurRadius: isDarkCard ? 34 : 24,
            spreadRadius: isDarkCard ? -12 : -6,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkCard ? 0.10 : 0.03),
            blurRadius: isDarkCard ? 28 : 12,
            spreadRadius: isDarkCard ? -10 : -4,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: role.stats.asMap().entries.map((entry) {
          final index = entry.key;
          final stat = entry.value;
          final isLast = index == role.stats.length - 1;

          return Expanded(
            child: Container(
              padding: EdgeInsets.only(right: isLast ? 0 : 10),
              margin: EdgeInsets.only(right: isLast ? 0 : 10),
              decoration: isLast
                  ? null
                  : BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: isDarkCard
                              ? AvroDriverColors.textSecondary.withValues(alpha: 0.08)
                              : AvroClientColors.surface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stat.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: EvikTypography.h3.copyWith(
                              color: role.textColor,
                              fontWeight: FontWeight.w900,
                              fontSize: valueFontSize,
                              height: 1.02,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stat.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: EvikTypography.caption.copyWith(
                              color: isDarkCard
                                  ? AvroDriverColors.textSecondary
                                      .withValues(alpha: 0.68)
                                  : AvroClientColors.tabInactive,
                              fontSize: labelFontSize,
                              fontWeight: FontWeight.w700,
                              height: 1.08,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RoleData {
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

  final UserRole id;
  final Color backgroundColor;
  final Color textColor;
  final String tag;
  final String icon;
  final String title;
  final String subtitle;
  final String ctaText;
  final String switchLabel;
  final List<_RoleStat> stats;
}

class _RoleStat {
  const _RoleStat({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}
