import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../driver/domain/entities/driver.dart';
import '../../../map/presentation/widgets/yandex_map_view.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/entities/order_flow_state.dart';
import '../providers/order_flow_provider.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  YandexMapController? _mapController;
  DrivingSession? _drivingSession;
  List<MapObject> _routeObjects = const [];
  String? _routeSignature;
  String? _routeEta;

  @override
  void dispose() {
    _drivingSession?.close();
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

    final pickup = Point(
      latitude: state.pickupLocation?.latitude ?? order.pickupLocation.lat,
      longitude: state.pickupLocation?.longitude ?? order.pickupLocation.lng,
    );
    final destination = Point(
      latitude:
          state.destinationLocation?.latitude ?? order.dropoffLocation.lat,
      longitude:
          state.destinationLocation?.longitude ?? order.dropoffLocation.lng,
    );
    final driverPoint = _driverPoint(driver, pickup);
    _updateYandexRoute(
      driverPoint: driverPoint,
      pickup: pickup,
      destination: destination,
    );

    return Scaffold(
      backgroundColor: EvikColors.gray50,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapKitAwareYandexMap(
              builder: (_) => YandexMap(
                onMapCreated: (controller) async {
                  _mapController = controller;
                  await controller.toggleTrafficLayer(visible: true);
                  await _focusDriver(driverPoint);
                },
                onTrafficChanged: (_) {},
                mapObjects: _mapObjects(
                  driverPoint: driverPoint,
                  pickup: pickup,
                  destination: destination,
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 14,
            left: 14,
            right: 14,
            child: _TopStatusCard(
              vehicleNumber: driver?.vehicleNumber ?? 'А923АА 777',
              eta: _routeEta ?? 'уточняется',
              onBackToOrder: () => context.go('/order/driver-info'),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 376,
            child: _FocusDriverButton(
              onPressed: () => _focusDriver(driverPoint),
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

  Point _driverPoint(Driver? driver, Point pickup) {
    final current = driver?.currentLocation;
    if (current != null) {
      return Point(latitude: current.lat, longitude: current.lng);
    }

    return Point(
      latitude: pickup.latitude + 0.012,
      longitude: pickup.longitude + 0.010,
    );
  }

  Future<void> _focusDriver(Point point) async {
    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: point, zoom: 15.8),
      ),
      animation: const MapAnimation(
        type: MapAnimationType.smooth,
        duration: 0.45,
      ),
    );
  }

  void _updateYandexRoute({
    required Point driverPoint,
    required Point pickup,
    required Point destination,
  }) {
    final signature = [
      driverPoint.latitude.toStringAsFixed(6),
      driverPoint.longitude.toStringAsFixed(6),
      pickup.latitude.toStringAsFixed(6),
      pickup.longitude.toStringAsFixed(6),
      destination.latitude.toStringAsFixed(6),
      destination.longitude.toStringAsFixed(6),
    ].join(':');

    if (_routeSignature == signature) return;
    _routeSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestYandexRoute(
        driverPoint: driverPoint,
        pickup: pickup,
        destination: destination,
        signature: signature,
      );
    });
  }

  Future<void> _requestYandexRoute({
    required Point driverPoint,
    required Point pickup,
    required Point destination,
    required String signature,
  }) async {
    await _drivingSession?.cancel();
    await _drivingSession?.close();

    try {
      final resultWithSession = await YandexDriving.requestRoutes(
        points: [
          RequestPoint(
            point: driverPoint,
            requestPointType: RequestPointType.wayPoint,
          ),
          RequestPoint(
            point: pickup,
            requestPointType: RequestPointType.viaPoint,
          ),
          RequestPoint(
            point: destination,
            requestPointType: RequestPointType.wayPoint,
          ),
        ],
        drivingOptions: const DrivingOptions(
          routesCount: 1,
          annotationLanguage: AnnotationLanguage.russian,
          avoidanceFlags: DrivingAvoidanceFlags(),
        ),
      );

      _drivingSession = resultWithSession.$1;
      final result = await resultWithSession.$2;
      if (!mounted || _routeSignature != signature || result.error != null) {
        return;
      }

      final routes = result.routes;
      if (routes == null || routes.isEmpty) {
        setState(() {
          _routeObjects = const [];
          _routeEta = null;
        });
        return;
      }

      final route = routes.first;
      setState(() {
        _routeEta = route.metadata.weight.timeWithTraffic.text;
        _routeObjects = [
          PolylineMapObject(
            mapId: const MapObjectId('yandex_driver_route'),
            polyline: route.geometry,
            strokeColor: EvikColors.accentOrange,
            strokeWidth: 4,
          ),
        ];
      });
    } catch (_) {
      if (!mounted || _routeSignature != signature) return;
      setState(() {
        _routeObjects = const [];
        _routeEta = null;
      });
    }
  }

  List<MapObject> _mapObjects({
    required Point driverPoint,
    required Point pickup,
    required Point destination,
  }) {
    return [
      ..._routeObjects,
      CircleMapObject(
        mapId: const MapObjectId('driver_position_outer'),
        circle: Circle(center: driverPoint, radius: 72),
        fillColor: EvikColors.infoBlue.withValues(alpha: 0.16),
        strokeColor: EvikColors.infoBlue.withValues(alpha: 0.28),
        strokeWidth: 2,
      ),
      CircleMapObject(
        mapId: const MapObjectId('driver_position'),
        circle: Circle(center: driverPoint, radius: 18),
        fillColor: EvikColors.infoBlue,
        strokeColor: EvikColors.primaryWhite,
        strokeWidth: 4,
      ),
      CircleMapObject(
        mapId: const MapObjectId('pickup_position'),
        circle: Circle(center: pickup, radius: 16),
        fillColor: EvikColors.successGreen,
        strokeColor: EvikColors.primaryWhite,
        strokeWidth: 4,
      ),
      CircleMapObject(
        mapId: const MapObjectId('destination_position'),
        circle: Circle(center: destination, radius: 16),
        fillColor: EvikColors.accentOrange,
        strokeColor: EvikColors.primaryWhite,
        strokeWidth: 4,
      ),
    ];
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

class _FocusDriverButton extends StatelessWidget {
  const _FocusDriverButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: const Icon(
            Icons.my_location_rounded,
            color: EvikColors.accentOrange,
          ),
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
                  'Водитель EVIK',
                  style: EvikTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  driver?.vehicleNumber ?? 'А923АА 777',
                  style: EvikTypography.bodySmall.copyWith(
                    color: EvikColors.gray600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '★ ${driver?.rating.toStringAsFixed(1) ?? '4.7'}',
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
