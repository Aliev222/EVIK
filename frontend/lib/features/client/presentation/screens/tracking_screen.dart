import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/evik_osm_map_view.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/live_driver_map.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order_flow_state.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with TickerProviderStateMixin {
  DriverLocationUpdate? _latestDriverLocation;
  String? _estimatedArrival;

  late AnimationController _markerAnimController;
  LatLng? _prevDriverPos;
  LatLng? _currDriverPos;

  List<LatLng> _routePoints = [];
  double? _lastRouteLat;
  double? _lastRouteLng;
  DateTime? _lastRouteTime;
  bool _firstRouteFitted = false;

  @override
  void initState() {
    super.initState();
    _markerAnimController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _markerAnimController.addListener(() {
      if (mounted) setState(() {});
    });
    _initializeRealTimeTracking();
  }

  double get _interpolatedDriverLat {
    if (_prevDriverPos == null || _currDriverPos == null) {
      return _currDriverPos?.latitude ?? 55.7558;
    }
    final t = Curves.easeInOut.transform(_markerAnimController.value);
    return _prevDriverPos!.latitude +
        (_currDriverPos!.latitude - _prevDriverPos!.latitude) * t;
  }

  double get _interpolatedDriverLng {
    if (_prevDriverPos == null || _currDriverPos == null) {
      return _currDriverPos?.longitude ?? 37.6173;
    }
    final t = Curves.easeInOut.transform(_markerAnimController.value);
    return _prevDriverPos!.longitude +
        (_currDriverPos!.longitude - _prevDriverPos!.longitude) * t;
  }

  void _initializeRealTimeTracking() {
    final realTimeService = ref.read(realTimeLocationServiceProvider);

    realTimeService.driverLocationStream.listen((driverUpdate) {
      if (!mounted) return;
      setState(() {
        _prevDriverPos = _currDriverPos;
        _currDriverPos = LatLng(driverUpdate.lat, driverUpdate.lng);
        _latestDriverLocation = driverUpdate;
        _estimatedArrival = _calculateETA(driverUpdate);
      });
      if (_prevDriverPos != null) {
        _markerAnimController.reset();
        _markerAnimController.forward();
      }
      _refreshRouteIfNeeded(driverUpdate);
    });
  }

  Future<void> _refreshRouteIfNeeded(DriverLocationUpdate update) async {
    final order = ref.read(orderFlowProvider).activeOrder;
    debugPrint('[TRACKING] _refreshRouteIfNeeded called — '
        'driver: (${update.lat}, ${update.lng}), status: ${update.status}');
    if (order == null) {
      debugPrint('[TRACKING] order is null, skipping');
      return;
    }

    if (!_shouldRefreshRoute(update.lat, update.lng)) {
      debugPrint('[TRACKING] _shouldRefreshRoute returned false, skipping');
      return;
    }

    LatLng target;
    if (update.status == DriverMarkerStatus.toDestination) {
      target = LatLng(
        order.dropoffLocation.lat,
        order.dropoffLocation.lng,
      );
      debugPrint('[TRACKING] target = dropoff (${target.latitude}, ${target.longitude})');
    } else {
      target = LatLng(
        order.pickupLocation.lat,
        order.pickupLocation.lng,
      );
      debugPrint('[TRACKING] target = pickup (${target.latitude}, ${target.longitude})');
    }

    try {
      debugPrint('[TRACKING] calling OSRM getRoutePreview...');
      final route = await OpenStreetMapService.getRoutePreview(
        fromLat: update.lat,
        fromLng: update.lng,
        toLat: target.latitude,
        toLng: target.longitude,
      );
      debugPrint('[TRACKING] OSRM returned — route is null? ${route == null}, '
          'points count: ${route?.points.length ?? 0}');
      if (!mounted) return;
      setState(() {
        _routePoints = route?.points ?? [];
        _lastRouteLat = update.lat;
        _lastRouteLng = update.lng;
        _lastRouteTime = DateTime.now();
      });
      debugPrint('[TRACKING] _routePoints set to ${_routePoints.length} points');
      if (!_firstRouteFitted) {
        _firstRouteFitted = true;
        debugPrint('[TRACKING] _firstRouteFitted = true');
      }
    } catch (e) {
      debugPrint('[TRACKING] OSRM threw exception: $e');
    }
  }

  bool _shouldRefreshRoute(double newLat, double newLng) {
    if (_lastRouteLat == null) {
      debugPrint('[TRACKING] _shouldRefreshRoute: no previous route, refreshing');
      return true;
    }
    final distance = _calculateDistance(
      _lastRouteLat!,
      _lastRouteLng!,
      newLat,
      newLng,
    );
    final timeSince = DateTime.now().difference(_lastRouteTime!);
    final shouldRefresh = distance > 100 || timeSince.inSeconds > 30;
    debugPrint('[TRACKING] _shouldRefreshRoute: distance=${distance.toStringAsFixed(1)}m, '
        'timeSince=${timeSince.inSeconds}s, shouldRefresh=$shouldRefresh');
    return shouldRefresh;
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusM = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthRadiusM * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  void _onRecenter() {
    _firstRouteFitted = false;
    if (mounted) setState(() {});
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
    _markerAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderFlowProvider);
    final order = state.activeOrder;
    final driver = state.assignedDriver;

    ref.listen<OrderFlowState>(orderFlowProvider, (previous, next) {
      if (next.currentStep == OrderFlowStep.paymentConfirmation &&
          previous?.currentStep != OrderFlowStep.paymentConfirmation) {
        if (!mounted) return;
        context.go('/order/payment-confirmation');
        return;
      }
      if (next.currentStep == OrderFlowStep.completion &&
          previous?.currentStep != OrderFlowStep.completion) {
        if (!mounted || next.activeOrder == null) return;
        context.go('/order/review/${next.activeOrder!.id}');
      }
    });

    if (order == null) {
      return const Scaffold(
        body: Center(child: Text('Информация о заказе недоступна')),
      );
    }

    // Build driver marker with interpolated position
    final driverMarker = _latestDriverLocation != null
        ? EvikMapMarker(
            lat: _interpolatedDriverLat,
            lng: _interpolatedDriverLng,
            title: 'Водитель',
            icon: Icons.local_shipping_rounded,
            color: _latestDriverLocation!.status == DriverMarkerStatus.toDestination
                ? AvroClientColors.info
                : AvroClientColors.success,
          )
        : null;

    // Route colour based on driver status
    final routeColor = _latestDriverLocation?.status ==
            DriverMarkerStatus.toDestination
        ? AvroClientColors.info
        : AvroClientColors.accent;

    return Scaffold(
      backgroundColor: AvroClientColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: LiveDriverMap(
              pickupLocation: state.pickupLocation!,
              destinationLocation: state.destinationLocation,
              showSearchAnimation: false,
              driverLocation: _latestDriverLocation,
              routePoints: _routePoints,
              extraMarkers: driverMarker != null ? [driverMarker] : [],
              routeColor: routeColor,
              showRecenterButton: _firstRouteFitted,
              onRecenter: _onRecenter,
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
      color: AvroClientColors.background,
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
                color: AvroClientColors.info.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
                color: AvroClientColors.info,
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
                      color: AvroClientColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vehicleNumber,
                    style: EvikTypography.bodySmall.copyWith(
                      color: AvroClientColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'ETA: $eta',
              style: EvikTypography.bodySmall.copyWith(
                color: AvroClientColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Вернуться к заказу',
              onPressed: onBackToOrder,
              icon: const Icon(Icons.receipt_long_rounded),
              color: AvroClientColors.textPrimary,
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
        color: AvroClientColors.background,
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
                      color: AvroClientColors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LocationCard(
                      label: 'Куда',
                      address: destinationAddress,
                      icon: Icons.flag_rounded,
                      color: AvroClientColors.accent,
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
            color: AvroClientColors.textPrimary,
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
                          done ? AvroClientColors.accent : AvroClientColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      done ? Icons.check : Icons.circle,
                      color:
                          done ? AvroClientColors.background : AvroClientColors.tabInactive,
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
                            done ? AvroClientColors.accent : AvroClientColors.tabInactive,
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
        color: AvroClientColors.background,
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
                  color: AvroClientColors.textSecondary,
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
              color: AvroClientColors.textPrimary,
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
        color: AvroClientColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AvroClientColors.background,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: AvroClientColors.tabInactive),
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
                    color: AvroClientColors.textSecondary,
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
              color: AvroClientColors.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
