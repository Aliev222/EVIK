import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

class TowTruckSelectionScreen extends ConsumerStatefulWidget {
  const TowTruckSelectionScreen({super.key});

  @override
  ConsumerState<TowTruckSelectionScreen> createState() =>
      _TowTruckSelectionScreenState();
}

class _TowTruckSelectionScreenState
    extends ConsumerState<TowTruckSelectionScreen> {
  PageController _pageController = PageController();
  int _currentPage = 0;

  final List<TowTruckType> _towTruckTypes = [
    TowTruckType.winch,
    TowTruckType.platform,
    TowTruckType.manipulator,
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTowTruckSelected(TowTruckType towTruckType) {
    ref.read(orderFlowProvider.notifier).selectTowTruckType(towTruckType);
  }

  Future<void> _continueToDriverSearch() async {
    final started = await ref.read(orderFlowProvider.notifier).goToDriverSearch();
    if (!mounted || !started) return;
    context.push('/order/search');
  }

  @override
  Widget build(BuildContext context) {
    final orderFlowState = ref.watch(orderFlowProvider);
    final paymentMethod = ref.watch(selectedOrderPaymentMethodProvider);

    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      appBar: AppBar(
        backgroundColor: EvikColors.primaryWhite,
        title: Text(
          'Выберите тип эвакуатора',
          style: EvikTypography.h2.copyWith(color: EvikColors.primaryBlack),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: EvikColors.primaryBlack),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Column(
        children: [
          // Progress summary
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EvikColors.primaryWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EvikColors.border, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: EvikColors.successGreen,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Автомобиль: ${orderFlowState.selectedVehicleType?.displayName ?? "Не выбран"}',
                      style: EvikTypography.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Расстояние: ${orderFlowState.distance.toStringAsFixed(1)} км',
                      style: EvikTypography.bodySmall.copyWith(
                        color: EvikColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Базовая цена: ${orderFlowState.estimatedPrice.round()} ₽',
                      style: EvikTypography.bodySmall.copyWith(
                        color: EvikColors.accentOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tow truck cards
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
                _onTowTruckSelected(_towTruckTypes[index]);
              },
              itemCount: _towTruckTypes.length,
              itemBuilder: (context, index) {
                final towTruckType = _towTruckTypes[index];
                final isSelected =
                    orderFlowState.selectedTowTruckType == towTruckType;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TowTruckCard(
                    towTruckType: towTruckType,
                    isSelected: isSelected,
                    basePrice: orderFlowState.estimatedPrice,
                    onTap: () {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                );
              },
            ),
          ),

          // Page indicators
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _towTruckTypes.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? EvikColors.accentOrange
                        : EvikColors.border,
                  ),
                ),
              ),
            ),
          ),

          // Continue button
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EvikColors.primaryWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EvikColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _PaymentChoice(
                    selected: paymentMethod == PaymentMethod.cash,
                    icon: Icons.payments_rounded,
                    label: 'Наличные',
                    onTap: () => ref
                        .read(orderFlowProvider.notifier)
                        .selectPaymentMethod(PaymentMethod.cash),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PaymentChoice(
                    selected: paymentMethod == PaymentMethod.card,
                    icon: Icons.credit_card_rounded,
                    label: 'Карта',
                    onTap: () => ref
                        .read(orderFlowProvider.notifier)
                        .selectPaymentMethod(PaymentMethod.card),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: EvikButton(
                text: 'Начать поиск водителя',
                onPressed: orderFlowState.selectedTowTruckType != null
                    ? _continueToDriverSearch
                    : null,
                variant: orderFlowState.selectedTowTruckType != null
                    ? EvikButtonVariant.primary
                    : EvikButtonVariant.ghost,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TowTruckCard extends StatelessWidget {
  const TowTruckCard({
    super.key,
    required this.towTruckType,
    required this.isSelected,
    required this.basePrice,
    required this.onTap,
  });

  final TowTruckType towTruckType;
  final bool isSelected;
  final double basePrice;
  final VoidCallback onTap;

  String get _priceText {
    final price = basePrice.round();
    return '$price ₽';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? EvikColors.accentOrange : EvikColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Tow truck image placeholder
            Container(
              width: 120,
              height: 80,
              decoration: BoxDecoration(
                color: EvikColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  towTruckType.assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      _getTowTruckIcon(towTruckType),
                      size: 48,
                      color: EvikColors.textHint,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              towTruckType.displayName,
              style: EvikTypography.h3.copyWith(
                color: EvikColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              towTruckType.description,
              style: EvikTypography.bodySmall.copyWith(
                color: EvikColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Price with multiplier indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? EvikColors.accentOrange.withValues(alpha: 0.1)
                    : EvikColors.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _priceText,
                style: EvikTypography.bodyMedium.copyWith(
                  color: isSelected
                      ? EvikColors.accentOrange
                      : EvikColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTowTruckIcon(TowTruckType type) {
    switch (type) {
      case TowTruckType.winch:
        return Icons.settings_ethernet;
      case TowTruckType.platform:
        return Icons.local_shipping;
      case TowTruckType.manipulator:
        return Icons.precision_manufacturing;
    }
  }
}

class _PaymentChoice extends StatelessWidget {
  const _PaymentChoice({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? EvikColors.accentOrangeAction : EvikColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? EvikColors.accentOrangeAction : EvikColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? EvikColors.primaryWhite
                  : EvikColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EvikTypography.bodyMedium.copyWith(
                  color: selected
                      ? EvikColors.primaryWhite
                      : EvikColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

