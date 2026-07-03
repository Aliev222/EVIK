import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/tariff.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

class VehicleSelectionScreen extends ConsumerWidget {
  const VehicleSelectionScreen({super.key});

  static const _vehicleTypes = [
    VehicleType.light,
    VehicleType.suv,
    VehicleType.minibus,
  ];

  static const _towTruckTypes = [
    TowTruckType.winch,
    TowTruckType.platform,
    TowTruckType.manipulator,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderFlowProvider);
    final paymentMethod = ref.watch(selectedOrderPaymentMethodProvider);
    final hasPrice = state.estimatedPrice > 0 ||
        (state.selectedTowTruckType != null &&
            state.tariffs[state.selectedTowTruckType] != null);
    final canStart = state.selectedVehicleType != null &&
        state.selectedTowTruckType != null &&
        hasPrice &&
        !state.isLoading;

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 760;
            return Column(
              children: [
                _Header(onBack: () => Navigator.of(context).pop()),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        _RouteSummary(state: state),
                        SizedBox(height: compact ? 8 : 10),
                        _OrderField(
                          label: '��� ���������',
                          value: state.selectedVehicleType?.displayName ??
                              '�������� ��� ����',
                          icon: Icons.directions_car_rounded,
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        _BlockedWheelsStepper(
                          count: state.blockedWheelsCount,
                          onChanged: (value) => ref
                              .read(orderFlowProvider.notifier)
                              .setBlockedWheelsCount(value),
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        _VehicleSelector(
                          vehicles: _vehicleTypes,
                          selected: state.selectedVehicleType,
                          onSelected: (type) => ref
                              .read(orderFlowProvider.notifier)
                              .selectVehicleType(type),
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        _TowTruckSelector(
                          towTrucks: _towTruckTypes,
                          selected: state.selectedTowTruckType,
                          estimatedPrice: state.estimatedPrice,
                          tariffs: state.tariffs,
                          distanceKm: state.distance,
                          onSelected: (type) => ref
                              .read(orderFlowProvider.notifier)
                              .selectTowTruckType(type),
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        _CommentTile(
                          comment: state.clientComment,
                          onTap: () => _editComment(context, ref, state),
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        _PaymentSelector(
                          selected: paymentMethod,
                          onSelected: (method) => ref
                              .read(selectedOrderPaymentMethodProvider.notifier)
                              .state = method,
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: EvikButton(
                    text: 'Начать поиск водителя',
                    width: double.infinity,
                    onPressed: canStart
                        ? () {
                            ref
                                .read(orderFlowProvider.notifier)
                                .goToDriverSearch();
                            context.push('/order/search');
                          }
                        : null,
                    variant: canStart
                        ? EvikButtonVariant.primary
                        : EvikButtonVariant.ghost,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _editComment(
    BuildContext context,
    WidgetRef ref,
    OrderFlowState state,
  ) async {
    final controller = TextEditingController(text: state.clientComment);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        return SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
            decoration: const BoxDecoration(
              color: AvroClientColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Комментарий водителю', style: EvikTypography.h3),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Например: подъезд со двора, не сигналить',
                    filled: true,
                    fillColor: AvroClientColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                EvikButton(
                  text: 'Сохранить',
                  width: double.infinity,
                  onPressed: () => Navigator.of(context).pop(controller.text),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
    if (result != null) {
      ref.read(orderFlowProvider.notifier).setClientComment(result);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(
              'Детали заказа',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EvikTypography.h2.copyWith(
                color: AvroClientColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.state});

  final OrderFlowState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _SummaryRow(
            icon: Icons.trip_origin_rounded,
            color: AvroClientColors.success,
            label: 'Точка подачи',
            value: state.pickupLocation?.displayAddress ?? 'Не указано',
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            icon: Icons.flag_rounded,
            color: AvroClientColors.accent,
            label: 'Точка назначения',
            value: state.destinationLocation?.displayAddress ?? 'Не указано',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: EvikTypography.bodySmall.copyWith(
                  color: AvroClientColors.tabInactive,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EvikTypography.bodyMedium.copyWith(
                  color: AvroClientColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderField extends StatelessWidget {
  const _OrderField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _GreyTile(
      child: Row(
        children: [
          Icon(icon, color: AvroClientColors.tabInactive),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: EvikTypography.bodySmall.copyWith(
                    color: AvroClientColors.tabInactive,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EvikTypography.bodyLarge.copyWith(
                    color: AvroClientColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AvroClientColors.tabInactive),
        ],
      ),
    );
  }
}

class _BlockedWheelsStepper extends StatelessWidget {
  const _BlockedWheelsStepper({
    required this.count,
    required this.onChanged,
  });

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Количество\nзаблокированных колёс',
              style: EvikTypography.bodyMedium.copyWith(
                color: AvroClientColors.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.remove_rounded,
            onTap: count > 0 ? () => onChanged(count - 1) : null,
          ),
          SizedBox(
            width: 42,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: EvikTypography.h3.copyWith(
                color: AvroClientColors.textPrimary,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
            onTap: count < 4 ? () => onChanged(count + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: onTap == null ? AvroClientColors.surface : AvroClientColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Icon(icon, color: AvroClientColors.textPrimary),
        ),
      ),
    );
  }
}

class _VehicleSelector extends StatelessWidget {
  const _VehicleSelector({
    required this.vehicles,
    required this.selected,
    required this.onSelected,
  });

  final List<VehicleType> vehicles;
  final VehicleType? selected;
  final ValueChanged<VehicleType> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Row(
        children: [
          for (var index = 0; index < vehicles.length; index++) ...[
            Expanded(
              child: _VehicleCard(
                vehicle: vehicles[index],
                selected: selected == vehicles[index],
                onTap: () => onSelected(vehicles[index]),
              ),
            ),
            if (index < vehicles.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.selected,
    required this.onTap,
  });

  final VehicleType vehicle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AvroClientColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AvroClientColors.accent : AvroClientColors.surface,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Center(
                child: Image.asset(
                  vehicle.assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.directions_car),
                ),
              ),
            ),
            const Spacer(),
            Text(
              vehicle.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EvikTypography.bodySmall.copyWith(
                color: selected
                    ? AvroClientColors.accent
                    : AvroClientColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TowTruckSelector extends StatelessWidget {
  const _TowTruckSelector({
    required this.towTrucks,
    required this.selected,
    required this.estimatedPrice,
    required this.tariffs,
    required this.distanceKm,
    required this.onSelected,
  });

  final List<TowTruckType> towTrucks;
  final TowTruckType? selected;
  final double estimatedPrice;
  final Map<TowTruckType, Tariff> tariffs;
  final double distanceKm;
  final ValueChanged<TowTruckType> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 136,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: towTrucks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final type = towTrucks[index];
          final isSelected = selected == type;
          int? price;
          if (isSelected && estimatedPrice > 0) {
            price = estimatedPrice.round();
          } else {
            final tariff = tariffs[type];
            if (tariff != null) {
              price = tariff.estimateRub(distanceKm).round();
            }
          }
          return _TowTruckCard(
            towTruck: type,
            selected: isSelected,
            price: price,
            onTap: () => onSelected(type),
          );
        },
      ),
    );
  }
}

class _TowTruckCard extends StatelessWidget {
  const _TowTruckCard({
    required this.towTruck,
    required this.selected,
    required this.price,
    required this.onTap,
  });

  final TowTruckType towTruck;
  final bool selected;
  final int? price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 206,
        height: 136,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AvroClientColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AvroClientColors.textPrimary : AvroClientColors.surface,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 82,
              height: double.infinity,
              child: Center(
                child: Image.asset(
                  towTruck.assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.local_shipping_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    towTruck.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EvikTypography.bodyMedium.copyWith(
                      color: AvroClientColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '~${_durationLabel(towTruck)}',
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroClientColors.tabInactive,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    price == null ? '—' : '$price ₽',
                    style: EvikTypography.bodyLarge.copyWith(
                      color: AvroClientColors.textPrimary,
                      fontWeight: FontWeight.w900,
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

  String _durationLabel(TowTruckType type) {
    switch (type) {
      case TowTruckType.winch:
        return '1 час 22 минуты';
      case TowTruckType.platform:
        return '1 час 40 минут';
      case TowTruckType.manipulator:
        return '2 часа 10 минут';
    }
  }
}

class _PaymentSelector extends StatelessWidget {
  const _PaymentSelector({
    required this.selected,
    required this.onSelected,
  });

  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          Expanded(
            child: _PaymentChip(
              method: PaymentMethod.cash,
              selected: selected,
              label: 'Наличные',
              icon: Icons.payments_rounded,
              onSelected: onSelected,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PaymentChip(
              method: PaymentMethod.card,
              selected: selected,
              label: 'Карта',
              icon: Icons.credit_card_rounded,
              onSelected: onSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  const _PaymentChip({
    required this.method,
    required this.selected,
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final PaymentMethod method;
  final PaymentMethod selected;
  final String label;
  final IconData icon;
  final ValueChanged<PaymentMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    final isSelected = method == selected;
    return Material(
      color: isSelected
          ? AvroClientColors.accent.withValues(alpha: 0.1)
          : AvroClientColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onSelected(method),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AvroClientColors.accent : AvroClientColors.surface,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color:
                    isSelected ? AvroClientColors.accent : AvroClientColors.tabInactive,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EvikTypography.bodyMedium.copyWith(
                    color: isSelected
                        ? AvroClientColors.accent
                        : AvroClientColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onTap,
  });

  final String comment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _GreyTile(
        child: Row(
          children: [
            const Icon(Icons.comment_rounded, color: AvroClientColors.tabInactive),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                comment.isEmpty ? 'Комментарий' : comment,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EvikTypography.bodyLarge.copyWith(
                  color: comment.isEmpty
                      ? AvroClientColors.tabInactive
                      : AvroClientColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AvroClientColors.tabInactive),
          ],
        ),
      ),
    );
  }
}

class _GreyTile extends StatelessWidget {
  const _GreyTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AvroClientColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
