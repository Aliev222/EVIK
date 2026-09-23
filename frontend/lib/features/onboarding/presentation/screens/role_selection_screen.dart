import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors, AvroDriverColors;
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
      icon: 'assets/img/rolecar.png',
      title: 'Нужен эвакуатор?',
      subtitle: 'Укажите, где находится автомобиль и куда его доставить.',
      ctaText: 'Вызвать эвакуатор',
      stats: [_RoleStat(value: 'Водитель на карте', label: '')],
    ),
    _RoleData(
      id: UserRole.driver,
      backgroundColor: AvroDriverColors.darkBlue,
      textColor: AvroClientColors.background,
      icon: 'assets/img/rolecar2.png',
      title: 'Заказы для вашего эвакуатора',
      subtitle:
          'Принимайте заказы поблизости. Выбирайте, когда выходить на линию.',
      ctaText: 'Стать водителем',
      stats: [_RoleStat(value: 'Заказы поблизости', label: '')],
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
      body: PageView.builder(
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
            onSelectPage: (page) => _pageController.animateToPage(
              page,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
            ),
          );
        },
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
    required this.onSelectPage,
  });

  final _RoleData role;
  final int index;
  final int currentIndex;
  final int rolesCount;
  final ValueChanged<UserRole> onRoleSelected;
  final ValueChanged<int> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final isDarkCard = index == 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          isDarkCard ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
            color: isDarkCard
                ? AvroDriverColors.background
                : AvroClientColors.background),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final width = constraints.maxWidth;
              final compact = height < 820;
              final veryCompact = height < 700;

              final horizontalPadding = (width * 0.08).clamp(24.0, 40.0);
              final topGap = veryCompact ? 14.0 : (compact ? 20.0 : 32.0);
              final heroGap = veryCompact ? 14.0 : (compact ? 24.0 : 48.0);
              final imageHeight = veryCompact ? 150.0 : 180.0;
              final imageWidth =
                  veryCompact ? 198.0 : (compact ? 222.0 : 250.0);
              final blockGap = veryCompact ? 10.0 : (compact ? 14.0 : 24.0);
              final smallGap = veryCompact ? 6.0 : (compact ? 10.0 : 16.0);
              final titleFont = veryCompact ? 34.0 : 36.0;
              final subtitleFont = veryCompact ? 16.0 : 17.0;
              final subtitleLineHeight =
                  veryCompact ? 1.25 : (compact ? 1.35 : 1.6);
              final bottomGap = veryCompact ? 8.0 : (compact ? 12.0 : 24.0);

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: height),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: topGap),
                        _Header(
                          isDarkCard: isDarkCard,
                          currentIndex: currentIndex,
                          rolesCount: rolesCount,
                          onSelect: onSelectPage,
                        ),
                        SizedBox(height: heroGap),
                        Center(
                          child: _RoleImage(
                            role: role,
                            isDarkCard: isDarkCard,
                            width: imageWidth,
                            height: imageHeight,
                          ),
                        ),
                        SizedBox(height: blockGap),
                        SizedBox(height: smallGap),
                        Text(
                          role.title,
                          style: EvikTypography.h1.copyWith(
                            color: role.textColor,
                            fontSize: titleFont,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: smallGap),
                        Text(
                          role.subtitle,
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
                        Text(role.stats.first.value,
                            style: EvikTypography.bodyMedium.copyWith(
                                color: role.textColor.withValues(alpha: .72),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 32),
                        SizedBox(height: height < 700 ? 0 : 40),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: isDarkCard
                                      ? Colors.black.withValues(alpha: 0.18)
                                      : AvroClientColors.accent
                                          .withValues(alpha: 0.20),
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
                        SizedBox(height: bottomGap),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isDarkCard,
    required this.currentIndex,
    required this.rolesCount,
    required this.onSelect,
  });

  final bool isDarkCard;
  final int currentIndex;
  final int rolesCount;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = ['Заказать эвакуатор', 'Я водитель'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Авро',
          style: EvikTypography.h3.copyWith(
              color: isDarkCard
                  ? AvroDriverColors.textSecondary
                  : AvroClientColors.textPrimary,
              fontWeight: FontWeight.w900)),
      const SizedBox(height: 16),
      SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: [
              for (var i = 0; i < rolesCount; i++)
                ButtonSegment(value: i, label: Text(labels[i]))
            ],
            showSelectedIcon: false,
            selected: {currentIndex},
            onSelectionChanged: (values) => onSelect(values.first),
            style: ButtonStyle(
                textStyle: WidgetStatePropertyAll(EvikTypography.caption
                    .copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? AvroClientColors.textPrimary
                        : (isDarkCard
                            ? const Color(0xFFD4D7DD)
                            : AvroClientColors.textPrimary)),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AvroClientColors.accent.withValues(alpha: .9);
                  }
                  return isDarkCard
                      ? AvroDriverColors.surface
                      : AvroClientColors.background;
                }),
                overlayColor:
                    const WidgetStatePropertyAll(AvroClientColors.accent)),
          )),
    ]);
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
    return SizedBox(
      width: width,
      height: height,
      child: Transform.scale(
        scale: 1.2,
        child: Image.asset(role.icon, fit: BoxFit.contain),
      ),
    );
  }
}

class _RoleData {
  const _RoleData({
    required this.id,
    required this.backgroundColor,
    required this.textColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ctaText,
    required this.stats,
  });

  final UserRole id;
  final Color backgroundColor;
  final Color textColor;
  final String icon;
  final String title;
  final String subtitle;
  final String ctaText;
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
