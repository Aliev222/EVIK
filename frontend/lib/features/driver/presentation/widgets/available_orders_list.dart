import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/available_orders_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_status_provider.dart';

class AvailableOrdersList extends ConsumerWidget {
  const AvailableOrdersList({
    super.key,
    required this.orders,
    required this.onAccept,
  });

  final List<Order> orders;
  final Future<void> Function(Order order) onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(availableOrdersDistanceFilterProvider);
    final sort = ref.watch(availableOrdersSortProvider);
    final location = ref.watch(driverStatusProvider).location;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChoiceChip<AvailableOrdersDistanceFilter>(
              value: AvailableOrdersDistanceFilter.under5km,
              groupValue: filter,
              label: '< 5 км',
              onSelected: (value) => ref
                  .read(availableOrdersDistanceFilterProvider.notifier)
                  .state = value,
            ),
            _ChoiceChip<AvailableOrdersDistanceFilter>(
              value: AvailableOrdersDistanceFilter.under10km,
              groupValue: filter,
              label: '< 10 км',
              onSelected: (value) => ref
                  .read(availableOrdersDistanceFilterProvider.notifier)
                  .state = value,
            ),
            _ChoiceChip<AvailableOrdersDistanceFilter>(
              value: AvailableOrdersDistanceFilter.all,
              groupValue: filter,
              label: 'Все',
              onSelected: (value) => ref
                  .read(availableOrdersDistanceFilterProvider.notifier)
                  .state = value,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Wrap(
            spacing: 8,
            children: [
              _SortChip(
                label: 'По цене',
                selected: sort == AvailableOrdersSort.price,
                onTap: () => ref
                    .read(availableOrdersSortProvider.notifier)
                    .state = AvailableOrdersSort.price,
              ),
              _SortChip(
                label: 'По расстоянию',
                selected: sort == AvailableOrdersSort.distance,
                onTap: () => ref
                    .read(availableOrdersSortProvider.notifier)
                    .state = AvailableOrdersSort.distance,
              ),
              _SortChip(
                label: 'По времени',
                selected: sort == AvailableOrdersSort.createdAt,
                onTap: () => ref
                    .read(availableOrdersSortProvider.notifier)
                    .state = AvailableOrdersSort.createdAt,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 340,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(availableOrdersProvider);
            },
            child: orders.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 60),
                      Center(
                        child: Text(
                          'Заказов пока нет. Ожидайте...',
                          style: TextStyle(
                            color: AvroDriverColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final distanceText = location == null
                          ? '...'
                          : (Geolocator.distanceBetween(
                                    location.lat,
                                    location.lng,
                                    order.pickupLocation.lat,
                                    order.pickupLocation.lng,
                                  ) /
                                  1000)
                              .toStringAsFixed(1);

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AvroDriverColors.borderLight),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _vehicleLabel(order.vehicleType),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _line('📍 От: ${order.pickupLocation.address}'),
                            _line('📍 До: ${order.dropoffLocation.address}'),
                            _line(
                              '💰 ${order.estimatedPrice.toStringAsFixed(0)}₽ • 🏃 ${_minutesAgo(order.createdAt)} мин • 📏 $distanceText км',
                            ),
                            if ((order.notes ?? '').trim().isNotEmpty)
                              _line('💬 "${order.notes}"'),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => onAccept(order),
                                child: const Text('Принять заказ'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _line(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: AvroDriverColors.textPrimary,
        ),
      ),
    );
  }

  int _minutesAgo(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt).inMinutes;
    return diff < 1 ? 1 : diff;
  }

  String _vehicleLabel(VehicleType type) {
    return switch (type) {
      VehicleType.light => '🚗 Легковой автомобиль',
      VehicleType.suv => '🚙 SUV / Кроссовер',
      VehicleType.minibus => '🚐 Минивэн',
      VehicleType.truck => '🚚 Грузовой автомобиль',
    };
  }
}

class _ChoiceChip<T> extends StatelessWidget {
  const _ChoiceChip({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onSelected,
  });

  final T value;
  final T groupValue;
  final String label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
