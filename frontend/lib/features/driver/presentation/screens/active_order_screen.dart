import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/theme/evik_colors.dart';
import '../../../../core/theme/evik_typography.dart';
import '../../../../shared/widgets/evik_button.dart';
import '../../../map/presentation/widgets/yandex_map_view.dart';
import '../../domain/entities/active_order.dart';
import '../providers/new_driver_provider.dart';

class ActiveOrderScreen extends ConsumerStatefulWidget {
  const ActiveOrderScreen({super.key});

  @override
  ConsumerState<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends ConsumerState<ActiveOrderScreen> {
  static const Point _driverPoint = Point(
    latitude: 55.7558,
    longitude: 37.6173,
  );

  YandexMapController? _mapController;
  DrivingSession? _drivingSession;
  List<MapObject> _routeObjects = const [];
  String? _routeSignature;

  @override
  void dispose() {
    _drivingSession?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(newDriverProvider);
    final order = driverState.activeOrder;

    ref.listen<DriverState>(newDriverProvider, (previous, next) {
      final message = next.error;
      if (message == null || message == previous?.error) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: EvikColors.errorRed,
        ),
      );
    });

    if (order == null) {
      return const Scaffold(
        backgroundColor: EvikColors.gray50,
        body: Center(child: Text('Нет активного заказа')),
      );
    }

    _syncRoute(order);

    return Scaffold(
      backgroundColor: EvikColors.primaryWhite,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapKitAwareYandexMap(
              builder: (_) => YandexMap(
                onMapCreated: _onMapCreated,
                mapType: MapType.vector,
                mapObjects: _mapObjects(order),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            right: 16,
            child: _ActiveOrderTopBar(order: order),
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 246,
            child: _MapActionButton(
              icon: Icons.navigation_rounded,
              onTap: () => _openNavigation(order),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ActiveOrderBottomSheet(
              order: order,
              isLoading: driverState.isLoading,
              onCall: () => _makePhoneCall(order.clientPhone),
              onMessage: () => _openSMS(order.clientPhone),
              onPrimaryAction: () => _handlePrimaryAction(order),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMapCreated(YandexMapController controller) async {
    _mapController = controller;
    await controller.toggleTrafficLayer(visible: true);
    await _focusRoute();
  }

  void _syncRoute(ActiveOrder order) {
    final target = _targetPoint(order);
    final from = order.status == ActiveOrderStatus.drivingToDestination
        ? Point(latitude: order.pickupLat, longitude: order.pickupLng)
        : _driverPoint;
    final signature = [
      order.status.name,
      from.latitude.toStringAsFixed(6),
      from.longitude.toStringAsFixed(6),
      target.latitude.toStringAsFixed(6),
      target.longitude.toStringAsFixed(6),
    ].join(':');
    if (_routeSignature == signature) return;
    _routeSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestRoute(from: from, to: target, signature: signature);
    });
  }

  Future<void> _requestRoute({
    required Point from,
    required Point to,
    required String signature,
  }) async {
    await _drivingSession?.cancel();
    await _drivingSession?.close();

    try {
      final resultWithSession = await YandexDriving.requestRoutes(
        points: [
          RequestPoint(
            point: from,
            requestPointType: RequestPointType.wayPoint,
          ),
          RequestPoint(point: to, requestPointType: RequestPointType.wayPoint),
        ],
        drivingOptions: const DrivingOptions(
          routesCount: 1,
          annotationLanguage: AnnotationLanguage.russian,
          avoidanceFlags: DrivingAvoidanceFlags(),
        ),
      );
      _drivingSession = resultWithSession.$1;
      final result = await resultWithSession.$2;
      if (!mounted || _routeSignature != signature) return;
      final route =
          result.routes?.isNotEmpty == true ? result.routes!.first : null;
      setState(() {
        _routeObjects = route == null
            ? const []
            : [
                PolylineMapObject(
                  mapId: const MapObjectId('active_order_route'),
                  polyline: route.geometry,
                  strokeColor: EvikColors.accentOrange,
                  strokeWidth: 4,
                ),
              ];
      });
      await _focusRoute();
    } catch (_) {
      if (!mounted || _routeSignature != signature) return;
      setState(() => _routeObjects = const []);
    }
  }

  Future<void> _focusRoute() async {
    await _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(target: _driverPoint, zoom: 13.4),
      ),
      animation: const MapAnimation(
        type: MapAnimationType.smooth,
        duration: 0.45,
      ),
    );
  }

  List<MapObject> _mapObjects(ActiveOrder order) {
    return [
      ..._routeObjects,
      PlacemarkMapObject(
        mapId: const MapObjectId('driver_location'),
        point: _driverPoint,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(Uint8List.fromList([0, 180, 90])),
            scale: 1,
          ),
        ),
      ),
      PlacemarkMapObject(
        mapId: const MapObjectId('pickup_location'),
        point: Point(latitude: order.pickupLat, longitude: order.pickupLng),
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(
              Uint8List.fromList([255, 96, 50]),
            ),
            scale: 0.9,
          ),
        ),
      ),
      PlacemarkMapObject(
        mapId: const MapObjectId('dropoff_location'),
        point: Point(latitude: order.dropoffLat, longitude: order.dropoffLng),
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(
              Uint8List.fromList([80, 90, 110]),
            ),
            scale: 0.8,
          ),
        ),
      ),
    ];
  }

  Point _targetPoint(ActiveOrder order) {
    if (order.status == ActiveOrderStatus.drivingToDestination) {
      return Point(latitude: order.dropoffLat, longitude: order.dropoffLng);
    }
    return Point(latitude: order.pickupLat, longitude: order.pickupLng);
  }

  Future<void> _handlePrimaryAction(ActiveOrder order) async {
    HapticFeedback.heavyImpact();
    final notifier = ref.read(newDriverProvider.notifier);
    switch (order.status) {
      case ActiveOrderStatus.drivingToClient:
        await notifier.arrivedAtClient();
        break;
      case ActiveOrderStatus.arrivedAtClient:
        await notifier.startDrivingToDestination();
        break;
      case ActiveOrderStatus.drivingToDestination:
        await notifier.completeOrder();
        break;
      case ActiveOrderStatus.completed:
        break;
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openSMS(String phoneNumber) async {
    final uri = Uri.parse('sms:$phoneNumber');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openNavigation(ActiveOrder order) async {
    final target = _targetPoint(order);
    final uri = Uri.parse(
      'yandexnavi://build_route_on_map?lat_to=${target.latitude}&lon_to=${target.longitude}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

class _ActiveOrderTopBar extends StatelessWidget {
  const _ActiveOrderTopBar({required this.order});

  final ActiveOrder order;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EvikColors.primaryWhite,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: EvikColors.accentOrange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
                color: EvikColors.accentOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    order.statusDisplayName,
                    style: EvikTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${order.distanceToClient.toStringAsFixed(1)} км · ${order.estimatedMinutes} мин',
                    style: EvikTypography.bodySmall.copyWith(
                      color: EvikColors.gray600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${order.price.toInt()} ₽',
              style: EvikTypography.price.copyWith(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveOrderBottomSheet extends StatelessWidget {
  const _ActiveOrderBottomSheet({
    required this.order,
    required this.isLoading,
    required this.onCall,
    required this.onMessage,
    required this.onPrimaryAction,
  });

  final ActiveOrder order;
  final bool isLoading;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: EvikColors.primaryWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: EvikColors.accentOrange,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      order.clientInitial,
                      style: const TextStyle(
                        color: EvikColors.primaryWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.clientName,
                        style: EvikTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${order.vehicleModel} · колеса: ${order.blockedWheelsCount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EvikTypography.bodySmall.copyWith(
                          color: EvikColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onCall,
                  icon: const Icon(Icons.phone_rounded),
                  color: EvikColors.accentOrange,
                ),
                IconButton(
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_rounded),
                  color: EvikColors.gray700,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _RoutePoint(
              color: EvikColors.accentOrange,
              label: order.status == ActiveOrderStatus.drivingToDestination
                  ? 'Забрали'
                  : 'К клиенту',
              value: order.pickupAddress,
            ),
            const SizedBox(height: 8),
            _RoutePoint(
              color: EvikColors.gray500,
              label: 'Доставка',
              value: order.dropoffAddress,
            ),
            const SizedBox(height: 14),
            if (order.status == ActiveOrderStatus.drivingToDestination)
              _SlideToComplete(
                price: order.price,
                enabled: !isLoading,
                onCompleted: onPrimaryAction,
              )
            else
              EvikButton(
                text: _primaryText(order.status),
                onPressed: isLoading ? null : onPrimaryAction,
                isLoading: isLoading,
                width: double.infinity,
                variant: EvikButtonVariant.green,
              ),
          ],
        ),
      ),
    );
  }

  String _primaryText(ActiveOrderStatus status) {
    return switch (status) {
      ActiveOrderStatus.drivingToClient => 'Прибыл к клиенту',
      ActiveOrderStatus.arrivedAtClient => 'Погрузил, в путь',
      ActiveOrderStatus.drivingToDestination => 'Завершить заказ',
      ActiveOrderStatus.completed => 'Заказ завершен',
    };
  }
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: EvikTypography.sectionLabel),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: EvikTypography.bodyMedium.copyWith(
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

class _SlideToComplete extends StatefulWidget {
  const _SlideToComplete({
    required this.price,
    required this.enabled,
    required this.onCompleted,
  });

  final double price;
  final bool enabled;
  final VoidCallback onCompleted;

  @override
  State<_SlideToComplete> createState() => _SlideToCompleteState();
}

class _SlideToCompleteState extends State<_SlideToComplete> {
  double _drag = 0;
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const knobSize = 48.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 36;
        final maxDrag = (width - knobSize - 10).clamp(
          0.0,
          1000.0,
        );
        final progress = maxDrag == 0 ? 0.0 : (_drag / maxDrag).clamp(0.0, 1.0);

        return GestureDetector(
          onHorizontalDragUpdate: !widget.enabled || _completed
              ? null
              : (details) {
                  setState(() {
                    _drag = (_drag + details.delta.dx).clamp(0.0, maxDrag);
                  });
                },
          onHorizontalDragEnd: !widget.enabled || _completed
              ? null
              : (_) {
                  if (progress >= 0.96) {
                    setState(() {
                      _completed = true;
                      _drag = maxDrag;
                    });
                    HapticFeedback.heavyImpact();
                    widget.onCompleted();
                  } else {
                    setState(() => _drag = 0);
                  }
                },
          child: SizedBox(
            width: double.infinity,
            height: 58,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.enabled
                    ? EvikColors.accentOrange
                    : EvikColors.gray300,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 58, right: 16),
                    child: Text(
                      'Завершить заказ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EvikTypography.buttonText.copyWith(
                        color: EvikColors.primaryWhite,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5 + _drag,
                    child: Container(
                      width: knobSize,
                      height: knobSize,
                      decoration: const BoxDecoration(
                        color: EvikColors.primaryWhite,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: EvikColors.accentOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(16),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Icon(icon, color: EvikColors.accentOrange),
        ),
      ),
    );
  }
}
