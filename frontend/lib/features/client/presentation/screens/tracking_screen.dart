import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/realtime_location_service.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../driver/domain/entities/driver.dart';
import '../../../map/presentation/widgets/animated_driver_marker.dart';
import '../../../map/presentation/widgets/live_driver_map.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/entities/order_flow_state.dart';
import '../providers/order_flow_provider.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  DriverLocationUpdate? _latestDriverLocation;
  String? _estimatedArrival;

  @override
  void initState() {
    super.initState();
    _initializeRealTimeTracking();
  }

  void _initializeRealTimeTracking() {
    final realTimeService = ref.read(realTimeLocationServiceProvider);

    // Listen for real-time driver location updates
    realTimeService.driverLocationStream.listen((driverUpdate) {
      if (!mounted) return;
      setState(() {
        _latestDriverLocation = driverUpdate;
        // Update ETA based on driver status
        _estimatedArrival = _calculateETA(driverUpdate);
      });
    });
  }

  String _calculateETA(DriverLocationUpdate driverUpdate) {
    switch (driverUpdate.status) {
      case DriverMarkerStatus.toPickup:
        return '5-10 мин';
      case DriverMarkerStatus.waiting:
        return 'прибыл';
      case DriverMarkerStatus.toDestination:
        return 'едет к месту назначения';
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderFlowProvider);
    final order = state.activeOrder;
    final driver = state.assignedDriver;

    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.completion &&
          previous?.currentStep != OrderFlowStep.completion) {
        context.go('/order/completion');
      }
    });

    if (order == null) {
      return const Scaffold(
        body: Center(child: Text('Информация о заказе недоступна')),
      );
    }

    return Scaffold(
      backgroundColor: EvikColors.gray50,
      body: Stack(
        children: [
          Positioned.fill(
            child: LiveDriverMap(
              pickupLocation: state.pickupLocation!,
              destinationLocation: state.destinationLocation,
              showRoute: true,
              showSearchAnimation: false,
              driverLocation: _latestDriverLocation,
              controlsBottomOffset: MediaQuery.paddingOf(context).bottom + 330,
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 14,
            left: 14,
            right: 14,
            child: _TopStatusCard(
              vehicleNumber: driver?.vehicleNumber.isNotEmpty == true
                  ? driver!.vehicleNumber
                  : 'Номер уточняется',
              eta: _estimatedArrival ?? 'уточняется',
              onBackToOrder: () => context.go('/order/driver-info'),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _TrackingSheet(
              order: order,
              driver: driver,
              pickupAddress: state.pickupLocation?.displayAddress ??
                  order.pickupLocation.address,
              destinationAddress: state.destinationLocation?.displayAddress ??
                  order.dropoffLocation.address,
              onBackToOrder: () => context.go('/order/driver-info'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopStatusCard extends StatelessWidget {
  const _TopStatusCard({
    required this.vehicleNumber,
    required this.eta,
    required this.onBackToOrder,
  });

  final String vehicleNumber;
  final String eta;
  final VoidCallback onBackToOrder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EvikColors.primaryWhite,
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: EvikColors.infoBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
                color: EvikColors.infoBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Эвакуатор едет к вам',
                    style: EvikTypography.bodyMedium.copyWith(
                      color: EvikColors.primaryBlack,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vehicleNumber,
                    style: EvikTypography.bodySmall.copyWith(
                      color: EvikColors.gray600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'ETA: $eta',
              style: EvikTypography.bodySmall.copyWith(
                color: EvikColors.accentOrange,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Вернуться к заказу',
              onPressed: onBackToOrder,
              icon: const Icon(Icons.receipt_long_rounded),
              color: EvikColors.primaryBlack,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingSheet extends StatelessWidget {
  const _TrackingSheet({
    required this.order,
    required this.driver,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.onBackToOrder,
  });

  final Order order;
  final Driver? driver;
  final String pickupAddress;
  final String destinationAddress;
  final VoidCallback onBackToOrder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Progress(status: order.status),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _LocationCard(
                      label: 'Откуда',
                      address: pickupAddress,
                      icon: Icons.trip_origin_rounded,
                      color: EvikColors.successGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LocationCard(
                      label: 'Куда',
                      address: destinationAddress,
                      icon: Icons.flag_rounded,
                      color: EvikColors.accentOrange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DriverCard(driver: driver),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: EvikButton(
                  text: 'К заказу',
                  onPressed: onBackToOrder,
                  variant: EvikButtonVariant.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Принят', OrderStatus.assigned),
      ('В пути', OrderStatus.onWay),
      ('Прибыл', OrderStatus.arrived),
      ('Погрузка', OrderStatus.evacuating),
    ];
    final current = steps.indexWhere((step) => step.$2 == status).clamp(0, 3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ход выполнения',
          style: EvikTypography.bodyMedium.copyWith(
            color: EvikColors.primaryBlack,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: steps.asMap().entries.map((entry) {
            final done = entry.key <= current;
            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color:
                          done ? EvikColors.accentOrange : EvikColors.gray300,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      done ? Icons.check : Icons.circle,
                      color:
                          done ? EvikColors.primaryWhite : EvikColors.gray500,
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.value.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EvikTypography.bodySmall.copyWith(
                        color:
                            done ? EvikColors.accentOrange : EvikColors.gray500,
                        fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.label,
    required this.address,
    required this.icon,
    required this.color,
  });

  final String label;
  final String address;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EvikColors.gray50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: EvikTypography.bodySmall.copyWith(
                  color: EvikColors.gray600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: EvikTypography.bodySmall.copyWith(
              color: EvikColors.primaryBlack,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.driver});

  final Driver? driver;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EvikColors.gray50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: EvikColors.primaryWhite,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: EvikColors.gray500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  driver?.fullName?.isNotEmpty == true
                      ? driver!.fullName!
                      : 'Водитель',
                  style: EvikTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  driver?.vehicleNumber.isNotEmpty == true
                      ? driver!.vehicleNumber
                      : 'Номер уточняется',
                  style: EvikTypography.bodySmall.copyWith(
                    color: EvikColors.gray600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            driver?.rating != null && driver?.rating != 0
                ? '★ ${driver!.rating.toStringAsFixed(1)}'
                : '★ —',
            style: EvikTypography.bodySmall.copyWith(
              color: EvikColors.accentOrange,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
