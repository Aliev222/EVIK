import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'edit_order_route_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tow_truck_frontend/core/config/build_flags.dart';
import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/services/location_service.dart';
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

/// UI audit is intentionally local-only: it must never create a real order,
/// request GPS, or open a WebSocket merely because a designer opens a screen.
final bool _isUiAuditMode = developmentFeatureEnabled(
  requested: const bool.fromEnvironment('EVIK_UI_AUDIT', defaultValue: false),
  releaseMode: kReleaseMode,
);

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
    if (!_isUiAuditMode) {
      _initializeRealTimeService();
    }
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
    if (!_isUiAuditMode) {
      ref.read(realTimeLocationServiceProvider).disconnect();
    }
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

  void _changeAddress() {
    if (_isNavigatingToDriverInfo) return;
    final order = ref.read(orderFlowProvider).activeOrder;
    if (order != null) unawaited(editOrderRoute(context, order));
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
    if (activeOrder != null &&
        activeOrder.isCrossCity &&
        activeOrder.surchargeAmount > 0) {
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
                          style: TextStyle(
                              fontSize: 14,
                              color: AvroClientColors.textSecondary),
                        ),
                        Text(
                          '${((activeOrder.surchargeAmount > 0 ? (activeOrder.surchargeAmount * 100 / activeOrder.surchargePercent).round() : 0) / 100).toStringAsFixed(0)} ₽',
                          style: const TextStyle(
                              fontSize: 14,
                              color: AvroClientColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Подача из другого города',
                          style: TextStyle(
                              fontSize: 14, color: AvroClientColors.accent),
                        ),
                        Text(
                          '+${(activeOrder.surchargeAmount / 100).toStringAsFixed(0)} ₽',
                          style: const TextStyle(
                              fontSize: 14, color: AvroClientColors.accent),
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

          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            child: Material(
              color: AvroClientColors.background,
              borderRadius: BorderRadius.circular(16),
              child: IconButton(
                tooltip: 'Закрыть поиск',
                onPressed: _cancelSearch,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.43,
            minChildSize: 0.40,
            maxChildSize: 0.88,
            builder: (context, scrollController) => CustomScrollView(
              controller: scrollController,
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverToBoxAdapter(
                    child: _FloatingSheetCard(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                        child: _SearchSummary(
                          state: orderFlowState,
                          searchTimer: searchTimer,
                          onCancel: _cancelSearch,
                          onChangeAddress: _changeAddress,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    MediaQuery.paddingOf(context).bottom + 12,
                  ),
                  sliver: const SliverToBoxAdapter(
                    child: _MarketplaceSheet(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _partnerPreviews = [
  _PartnerPreview(
    title: 'Выездной шиномонтаж',
    subtitle: 'Рядом с точкой подачи',
    icon: Icons.tire_repair_rounded,
  ),
  _PartnerPreview(
    title: 'Автосервис',
    subtitle: 'Диагностика и ремонт после эвакуации',
    icon: Icons.car_repair_rounded,
  ),
];

class _SearchSummary extends StatelessWidget {
  const _SearchSummary({
    required this.state,
    required this.searchTimer,
    required this.onCancel,
    required this.onChangeAddress,
  });

  final OrderFlowState state;
  final String searchTimer;
  final VoidCallback onCancel;
  final VoidCallback onChangeAddress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: AvroClientColors.surface,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const _SearchingDot(),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ищем свободного водителя',
                style: EvikTypography.h3.copyWith(
                  color: AvroClientColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              searchTimer,
              style: EvikTypography.bodyLarge.copyWith(
                color: AvroClientColors.accent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SearchRouteCard(
          pickup: state.pickupLocation?.displayAddress ?? 'Точка подачи',
          destination:
              state.destinationLocation?.displayAddress ?? 'Точка назначения',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SearchActionButton(
                label: 'Сменить адрес',
                icon: Icons.edit_location_alt_outlined,
                onPressed: onChangeAddress,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SearchActionButton(
                label: 'Отменить',
                icon: Icons.close_rounded,
                isDestructive: true,
                onPressed: onCancel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FloatingSheetCard extends StatelessWidget {
  const _FloatingSheetCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AvroClientColors.background,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
}

class _SearchingDot extends StatelessWidget {
  const _SearchingDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: AvroClientColors.accent,
          shape: BoxShape.circle,
        ),
      );
}

class _SearchRouteCard extends StatelessWidget {
  const _SearchRouteCard({required this.pickup, required this.destination});

  final String pickup;
  final String destination;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AvroClientColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _RouteLine(
              icon: Icons.trip_origin_rounded,
              color: AvroClientColors.success,
              label: 'Откуда',
              value: pickup,
            ),
            const Padding(
              padding: EdgeInsets.only(left: 7),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 10,
                  child: VerticalDivider(color: AvroClientColors.tabInactive),
                ),
              ),
            ),
            _RouteLine(
              icon: Icons.flag_rounded,
              color: AvroClientColors.accent,
              label: 'Куда',
              value: destination,
            ),
          ],
        ),
      );
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
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
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: EvikTypography.bodySmall
                        .copyWith(color: AvroClientColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EvikTypography.bodyMedium.copyWith(
                        color: AvroClientColors.textPrimary,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      );
}

class _SearchActionButton extends StatelessWidget {
  const _SearchActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? AvroClientColors.error : AvroClientColors.textPrimary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.25)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _PartnerPreviewHeader extends StatelessWidget {
  const _PartnerPreviewHeader();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
        child: Row(
          children: [
            Expanded(
              child: Text('Рядом с вами',
                  style: EvikTypography.h3.copyWith(
                      color: AvroClientColors.textPrimary,
                      fontWeight: FontWeight.w900)),
            ),
            Text('Скоро',
                style: EvikTypography.bodySmall
                    .copyWith(color: AvroClientColors.textSecondary)),
          ],
        ),
      );
}

class _MarketplaceSheet extends StatelessWidget {
  const _MarketplaceSheet();

  @override
  Widget build(BuildContext context) => _FloatingSheetCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            children: [
              const _PartnerPreviewHeader(),
              for (var index = 0; index < _partnerPreviews.length; index++) ...[
                _PartnerPreviewCard(preview: _partnerPreviews[index]),
                if (index < _partnerPreviews.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
}

class _PartnerPreview {
  const _PartnerPreview({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

class _PartnerPreviewCard extends StatelessWidget {
  const _PartnerPreviewCard({required this.preview});

  final _PartnerPreview preview;

  @override
  Widget build(BuildContext context) => Container(
        height: 118,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AvroClientColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 94,
              height: double.infinity,
              decoration: BoxDecoration(
                color: AvroClientColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child:
                  Icon(preview.icon, color: AvroClientColors.accent, size: 38),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preview.title,
                      style: EvikTypography.bodyLarge.copyWith(
                          color: AvroClientColors.textPrimary,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(preview.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EvikTypography.bodySmall
                          .copyWith(color: AvroClientColors.textSecondary)),
                  const Spacer(),
                  Text('Запись откроется скоро',
                      style: EvikTypography.bodySmall
                          .copyWith(color: AvroClientColors.tabInactive)),
                ],
              ),
            ),
          ],
        ),
      );
}
