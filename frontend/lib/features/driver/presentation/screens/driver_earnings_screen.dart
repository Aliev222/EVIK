import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../../shared/widgets/skeleton_card.dart';

enum EarningsState { loading, empty, loaded, error }

class DriverEarningsScreen extends ConsumerStatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  ConsumerState<DriverEarningsScreen> createState() =>
      _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends ConsumerState<DriverEarningsScreen> {
  EarningsState _state = EarningsState.loaded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        title: Text(
          'Доходы',
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
        actions: [
          _EarningsStateAction(
            label: 'Empty',
            onTap: () => setState(() => _state = EarningsState.empty),
          ),
          _EarningsStateAction(
            label: 'Loading',
            onTap: () => setState(() => _state = EarningsState.loading),
          ),
          _EarningsStateAction(
            label: 'Error',
            onTap: () => setState(() => _state = EarningsState.error),
          ),
          _EarningsStateAction(
            label: 'Loaded',
            onTap: () => setState(() => _state = EarningsState.loaded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case EarningsState.loading:
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          children: const [
            SkeletonCard(height: 168),
            SkeletonCard(height: 100),
            SkeletonCard(height: 100),
            SkeletonCard(height: 190),
          ],
        );
      case EarningsState.empty:
        return const EmptyState(
          icon: Icons.monetization_on_outlined,
          title: 'Пока доходов нет',
          subtitle: 'Выполните первый заказ чтобы увидеть статистику',
        );
      case EarningsState.error:
        return ErrorState(
          message: 'Статистика доходов временно недоступна.',
          onRetry: () => setState(() => _state = EarningsState.loading),
        );
      case EarningsState.loaded:
        return _buildLoadedContent();
    }
  }

  Widget _buildLoadedContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Эта неделя',
                      style: EvikTypography.bodyMedium.copyWith(
                        color: EvikColors.gray500,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: EvikColors.successGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+12%',
                        style: EvikTypography.bodySmall.copyWith(
                          color: EvikColors.primaryWhite,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '18 400 ₽',
                  style: EvikTypography.h1.copyWith(
                    color: EvikColors.accentOrange,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'чем на прошлой неделе',
                  style: EvikTypography.bodySmall.copyWith(
                    color: EvikColors.gray500,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _buildWeekCalendar(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.shopping_bag_outlined,
                  value: '12',
                  label: 'Заказов',
                  color: EvikColors.accentOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.attach_money,
                  value: '1 533 ₽',
                  label: 'Средний чек',
                  color: EvikColors.successGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.access_time_rounded,
                  value: '28 ч',
                  label: 'Часов в работе',
                  color: EvikColors.infoBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.star_outlined,
                  value: '4.9',
                  label: 'Рейтинг',
                  color: EvikColors.warningAmber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ВЫПЛАТА',
                  style: EvikTypography.sectionLabel.copyWith(
                    color: EvikColors.gray500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '18 400 ₽',
                  style: EvikTypography.h2.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Доступно для вывода',
                  style: EvikTypography.bodyMedium.copyWith(
                    color: EvikColors.gray500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: EvikColors.gray100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.credit_card,
                            size: 18,
                            color: EvikColors.gray700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Сбербанк •••• 4242',
                            style: EvikTypography.bodyMedium.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                EvikButton(
                  text: 'Вывести',
                  onPressed: () {},
                  width: double.infinity,
                  variant: EvikButtonVariant.green,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildWeekCalendar() {
    final days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final earnings = [
      2400,
      3100,
      2800,
      0,
      4200,
      3500,
      2400
    ]; // Заработок по дням
    const today = 4; // Пятница (индекс 4)

    return days.asMap().entries.map((entry) {
      final index = entry.key;
      final day = entry.value;
      final earning = earnings[index];
      final isToday = index == today;
      final hasEarning = earning > 0;

      return Container(
        width: 36,
        height: 52,
        decoration: BoxDecoration(
          color: isToday
              ? EvikColors.accentOrange
              : hasEarning
                  ? EvikColors.gray100
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day,
              style: EvikTypography.bodySmall.copyWith(
                color: isToday ? EvikColors.primaryWhite : EvikColors.gray500,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: hasEarning
                    ? (isToday
                        ? EvikColors.primaryWhite
                        : EvikColors.successGreen)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: EvikTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: EvikTypography.bodySmall.copyWith(
              color: EvikColors.gray500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsStateAction extends StatelessWidget {
  const _EarningsStateAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: EvikTypography.bodySmall.copyWith(
          color: EvikColors.accentOrange,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
