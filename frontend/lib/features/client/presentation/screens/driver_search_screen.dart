import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

class DriverSearchScreen extends ConsumerStatefulWidget {
  const DriverSearchScreen({super.key});

  @override
  ConsumerState<DriverSearchScreen> createState() => _DriverSearchScreenState();
}

class _DriverSearchScreenState extends ConsumerState<DriverSearchScreen> {
  bool _isNavigatingToDriverInfo = false;
  Timer? _clientLocationTimer;
  StreamSubscription? _orderUpdateSub;

  @override
  void initState() {
    super.initState();
    _initializeRealTimeService();
  }

  void _initializeRealTimeService() async {
    final realTimeService = ref.read(realTimeLocationServiceProvider);
    final orderFlowState = ref.read(orderFlowProvider);

    // Connect as client when searching for driver. The real user id and
    // access token let the server address real-time events to this client.
    final authState = ref.read(authProvider);
    const fallbackClientId = 'client_app_user';
    final hasUserId =
        authState.user?.id != null && authState.user!.id.isNotEmpty;
    final clientId = hasUserId ? authState.user!.id : fallbackClientId;

    final connected = await realTimeService.connect(
      userId: clientId,
      userType: 'client',
      accessToken: authState.accessToken ?? '',
    );

    if (connected) {
      // Listen for order updates
      _orderUpdateSub = realTimeService.orderUpdateStream.listen((orderUpdate) {
        if (!mounted) return;

        if (orderUpdate.status == OrderUpdateType.driverFound) {
          // Driver found! Navigate to next screen
          ref.read(orderFlowProvider.notifier).goToDriverFound();
        } else if (orderUpdate.status == OrderUpdateType.noDriversAvailable) {
          // No drivers available - show error
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Свободные водители не найдены. Попробуйте позже.'),
              backgroundColor: AvroClientColors.error,
            ),
          );
        }
      });

      // Create order if we have all required data
      final pickup = orderFlowState.pickupLocation;
      final dropoff = orderFlowState.destinationLocation;
      if (pickup != null && dropoff != null) {
        await realTimeService.createOrder(
          pickupLat: pickup.latitude,
          pickupLng: pickup.longitude,
          dropoffLat: dropoff.latitude,
          dropoffLng: dropoff.longitude,
          vehicleType: VehicleType.light, // Based on selected vehicle
          notes: 'Order from client app',
        );
        _startClientLocationUpdates(realTimeService);
      }
    }
  }

  @override
  void dispose() {
    _clientLocationTimer?.cancel();
    _orderUpdateSub?.cancel();
    ref.read(realTimeLocationServiceProvider).disconnect();
    super.dispose();
  }

  void _startClientLocationUpdates(RealTimeLocationService realTimeService) {
    _clientLocationTimer?.cancel();
    Future<void> sendCurrentLocation() async {
      try {
        final location = await LocationService.instance.getCurrentLocation();
        if (location == null) return;
        await realTimeService.sendClientLocation(
          lat: location.lat,
          lng: location.lng,
        );
      } catch (_) {
        final pickup = ref.read(orderFlowProvider).pickupLocation;
        if (pickup == null) return;
        await realTimeService.sendClientLocation(
          lat: pickup.latitude,
          lng: pickup.longitude,
        );
      }
    }

    unawaited(sendCurrentLocation());
    _clientLocationTimer = Timer.periodic(
      AppConstants.clientLocationUpdateInterval,
      (_) => unawaited(sendCurrentLocation()),
    );
  }

  void _cancelSearch() {
    if (_isNavigatingToDriverInfo) return;
    _isNavigatingToDriverInfo = true;
    final notifier = ref.read(orderFlowProvider.notifier);
    unawaited(_finishCancel(notifier));
    context.go('/');
  }

  Future<void> _finishCancel(OrderFlowNotifier notifier) async {
    final cancelled = await notifier.cancelSearch();
    if (!cancelled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Не удалось отменить заказ — проверьте соединение',
          ),
          backgroundColor: AvroClientColors.error,
        ),
      );
    }
  }

  Future<void> _goToDriverInfo() async {
    if (_isNavigatingToDriverInfo) return;
    _isNavigatingToDriverInfo = true;

    final activeOrder = ref.read(orderFlowProvider).activeOrder;
    if (activeOrder != null && activeOrder.isCrossCity && activeOrder.surchargeAmount > 0) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Водитель из другого города',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AvroClientColors.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Водитель приедет из соседнего города. '
                'К стоимости будет добавлена надбавка за подачу.',
                style: TextStyle(
                  fontSize: 14,
                  color: AvroClientColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AvroClientColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AvroClientColors.surface),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Эвакуация',
                          style: TextStyle(fontSize: 14, color: AvroClientColors.textSecondary),
                        ),
                        Text(
                          '${((activeOrder.surchargeAmount > 0 ? (activeOrder.surchargeAmount * 100 / activeOrder.surchargePercent).round() : 0) / 100).toStringAsFixed(0)} ₽',
                          style: const TextStyle(fontSize: 14, color: AvroClientColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Подача из другого города',
                          style: TextStyle(fontSize: 14, color: AvroClientColors.accent),
                        ),
                        Text(
                          '+${(activeOrder.surchargeAmount / 100).toStringAsFixed(0)} ₽',
                          style: const TextStyle(fontSize: 14, color: AvroClientColors.accent),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Итого',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AvroClientColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${((activeOrder.surchargeAmount > 0 ? (activeOrder.surchargeAmount * 100 / activeOrder.surchargePercent).round() + activeOrder.surchargeAmount : 0) / 100).toStringAsFixed(0)} ₽',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AvroClientColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Отменить заказ',
                style: TextStyle(color: AvroClientColors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AvroClientColors.accent,
                foregroundColor: AvroClientColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Согласен'),
            ),
          ],
        ),
      );

      if (accepted != true) {
        final notifier = ref.read(orderFlowProvider.notifier);
        unawaited(_finishCancel(notifier));
        if (mounted) {
          _isNavigatingToDriverInfo = false;
          context.go('/');
        }
        return;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/order/driver-info');
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderFlowState = ref.watch(orderFlowProvider);
    final pickupLocation = orderFlowState.pickupLocation;
    final searchTimer = ref.watch(searchTimerDisplayProvider);

    if (orderFlowState.currentStep == OrderFlowStep.driverFound) {
      _goToDriverInfo();
    }

    // Listen for navigation to next screen when driver is found
    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (!mounted) return;
      if (next.currentStep == OrderFlowStep.driverFound &&
          previous?.currentStep != OrderFlowStep.driverFound) {
        _goToDriverInfo();
      }

      if (next.errorMessage != null &&
          previous?.errorMessage != next.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AvroClientColors.error,
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () {
                ref.read(orderFlowProvider.notifier).goToDriverSearch();
              },
            ),
          ),
        );
        ref.read(orderFlowProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      appBar: AppBar(
        backgroundColor: AvroClientColors.background,
        title: Text(
          'Поиск водителя',
          style: EvikTypography.h2.copyWith(color: AvroClientColors.textPrimary),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AvroClientColors.textPrimary),
          onPressed: _cancelSearch,
        ),
      ),
      body: Stack(
        children: [
          // Map background only. Search feedback lives in the sheet below, so
          // fallback map states never compete with markers or pulse overlays.
          if (pickupLocation != null)
            Positioned.fill(
              child: EvikOsmMapView(
                initialLat: pickupLocation.latitude,
                initialLng: pickupLocation.longitude,
                initialZoom: 15,
              ),
            ),

          // Search info panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: AvroClientColors.background,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: const Border(
                  top: BorderSide(color: AvroClientColors.surface),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search status
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AvroClientColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ищем свободного водителя...',
                            style: EvikTypography.h3.copyWith(
                              color: AvroClientColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Search timer
                    Text(
                      searchTimer,
                      style: EvikTypography.bodyLarge.copyWith(
                        color: AvroClientColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Order summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AvroClientColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryRow(
                            'Автомобиль',
                            orderFlowState.selectedVehicleType?.displayName ??
                                'Не выбран',
                            Icons.directions_car,
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Эвакуатор',
                            orderFlowState.selectedTowTruckType?.displayName ??
                                'Не выбран',
                            Icons.local_shipping,
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Расстояние',
                            '${orderFlowState.distance.toStringAsFixed(1)} км',
                            Icons.route,
                          ),
                          const SizedBox(height: 8),
                          _buildSummaryRow(
                            'Стоимость',
                            '${orderFlowState.estimatedPrice.round()} ₽',
                            Icons.payment,
                            valueColor: AvroClientColors.accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Cancel button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _cancelSearch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AvroClientColors.surface,
                          foregroundColor: AvroClientColors.error,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: EvikTypography.buttonText,
                        ),
                        child: const Text('Отменить поиск'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AvroClientColors.tabInactive),
        const SizedBox(width: 8),
        Text(
          label,
          style: EvikTypography.bodySmall.copyWith(
            color: AvroClientColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: EvikTypography.bodyMedium.copyWith(
            color: valueColor ?? AvroClientColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
