import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/realtime_location_service.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../map/presentation/widgets/evik_osm_map_view.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/entities/order_flow_state.dart';
import '../providers/order_flow_provider.dart';

class DriverSearchScreen extends ConsumerStatefulWidget {
  const DriverSearchScreen({super.key});

  @override
  ConsumerState<DriverSearchScreen> createState() => _DriverSearchScreenState();
}

class _DriverSearchScreenState extends ConsumerState<DriverSearchScreen> {
  bool _isNavigatingToDriverInfo = false;
  Timer? _clientLocationTimer;

  @override
  void initState() {
    super.initState();
    _initializeRealTimeService();
  }

  void _initializeRealTimeService() async {
    final realTimeService = ref.read(realTimeLocationServiceProvider);
    final orderFlowState = ref.read(orderFlowProvider);

    // Connect as client when searching for driver
    const clientId = 'client_app_user'; // Use a simple ID for now

    final connected =
        await realTimeService.connect(userId: clientId, userType: 'client');

    if (connected) {
      // Listen for order updates
      realTimeService.orderUpdateStream.listen((orderUpdate) {
        if (!mounted) return;

        if (orderUpdate.status == OrderUpdateType.driverFound) {
          // Driver found! Navigate to next screen
          ref.read(orderFlowProvider.notifier).goToDriverFound();
        } else if (orderUpdate.status == OrderUpdateType.noDriversAvailable) {
          // No drivers available - show error
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Свободные водители не найдены. Попробуйте позже.'),
              backgroundColor: EvikColors.errorRed,
            ),
          );
        }
      });

      // Create order if we have all required data
      if (orderFlowState.pickupLocation != null &&
          orderFlowState.destinationLocation != null) {
        await realTimeService.createOrder(
          pickupLat: orderFlowState.pickupLocation!.latitude,
          pickupLng: orderFlowState.pickupLocation!.longitude,
          dropoffLat: orderFlowState.destinationLocation!.latitude,
          dropoffLng: orderFlowState.destinationLocation!.longitude,
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
    // Disconnect from real-time service
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
    ref.read(orderFlowProvider.notifier).cancelSearch();
    context.go('/');
  }

  void _goToDriverInfo() {
    if (_isNavigatingToDriverInfo) return;
    _isNavigatingToDriverInfo = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/order/driver-info');
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderFlowState = ref.watch(orderFlowProvider);
    final searchTimer = ref.watch(searchTimerDisplayProvider);

    if (orderFlowState.currentStep == OrderFlowStep.driverFound) {
      _goToDriverInfo();
    }

    // Listen for navigation to next screen when driver is found
    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.driverFound &&
          previous?.currentStep != OrderFlowStep.driverFound) {
        _goToDriverInfo();
      }

      if (next.errorMessage != null &&
          previous?.errorMessage != next.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: EvikColors.errorRed,
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
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        backgroundColor: EvikColors.gray50,
        title: Text(
          'Поиск водителя',
          style: EvikTypography.h2.copyWith(color: EvikColors.primaryBlack),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: EvikColors.primaryBlack),
          onPressed: _cancelSearch,
        ),
      ),
      body: Stack(
        children: [
          // Map background only. Search feedback lives in the sheet below, so
          // fallback map states never compete with markers or pulse overlays.
          if (orderFlowState.pickupLocation != null)
            Positioned.fill(
              child: EvikOsmMapView(
                initialLat: orderFlowState.pickupLocation!.latitude,
                initialLng: orderFlowState.pickupLocation!.longitude,
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
                color: EvikColors.primaryWhite,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: EvikColors.gray300.withValues(alpha: 0.5),
                    offset: const Offset(0, -4),
                    blurRadius: 12,
                  ),
                ],
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
                            color: EvikColors.accentOrange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ищем свободного водителя...',
                            style: EvikTypography.h3.copyWith(
                              color: EvikColors.primaryBlack,
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
                        color: EvikColors.accentOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Order summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: EvikColors.gray50,
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
                            valueColor: EvikColors.accentOrange,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Cancel button
                    SizedBox(
                      width: double.infinity,
                      child: EvikButton(
                        text: 'Отменить поиск',
                        onPressed: _cancelSearch,
                        variant: EvikButtonVariant.secondary,
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
        Icon(icon, size: 16, color: EvikColors.gray500),
        const SizedBox(width: 8),
        Text(
          label,
          style: EvikTypography.bodySmall.copyWith(
            color: EvikColors.gray600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: EvikTypography.bodyMedium.copyWith(
            color: valueColor ?? EvikColors.primaryBlack,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
