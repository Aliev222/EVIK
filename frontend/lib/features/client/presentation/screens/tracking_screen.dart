import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/services/openstreetmap_service.dart';
import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/chat/presentation/chat_screen.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/order_flow_provider.dart';
import 'package:tow_truck_frontend/features/client/presentation/providers/real_time_driver_provider.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/live_driver_map.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

const _visualCaptureState = String.fromEnvironment(
  'EVIK_VISUAL_CAPTURE_STATE',
);

/// The only client order tracking screen. The realtime provider owns the
/// WebSocket; this screen renders its state and never creates another stream.
class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, this.auditDemo = false});
  final bool auditDemo;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  List<LatLng> _routePoints = const [];
  double? _routeDurationSeconds;
  String? _routeError;
  int _routeGeneration = 0;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteTarget;
  LatLng? _pendingRouteOrigin;
  LatLng? _pendingRouteTarget;
  OrderStatus? _lastRouteStatus;
  OrderStatus? _pendingRouteStatus;
  String? _lastRouteOrderId;
  String? _pendingRouteOrderId;
  bool _manualCamera = false;
  double _sheetExtent = .37;
  Timer? _auditReplayTimer;
  Timer? _staleStateTimer;
  int _auditReplayIndex = 0;
  bool _auditReplayForward = true;
  DateTime _auditSampledAt = DateTime.now();

  // Audit-only coordinates around Makhachkala. They exercise a turn and are
  // rendered through the same OSM route request as a real tracking session.
  static const _auditReplayPoints = <LatLng>[
    LatLng(42.96872, 47.49137),
    LatLng(42.96914, 47.49221),
    LatLng(42.96983, 47.49306),
    LatLng(42.97072, 47.49368),
    LatLng(42.97156, 47.49439),
    LatLng(42.97234, 47.49533),
    LatLng(42.97312, 47.49624),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.auditDemo) {
      if (_visualCaptureState == 'expanded') {
        _sheetExtent = .88;
      } else if (_visualCaptureState == 'close') {
        _manualCamera = true;
      }
      _startAuditReplay();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
    }
    _staleStateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  void _startSession() {
    final flow = ref.read(orderFlowProvider);
    final order = flow.activeOrder;
    if (order == null || _isTerminal(order.status)) return;
    final pickup = flow.pickupLocation;
    final target = pickup == null
        ? order.pickupLocation
        : LocationModel(
            lat: pickup.latitude,
            lng: pickup.longitude,
            address: pickup.displayAddress);
    ref.read(realTimeDriverProvider.notifier).startTracking(
          order.id,
          target,
          userId: ref.read(authProvider).user?.id,
          accessToken: ref.read(authProvider).accessToken,
          // The order carries the assignment before the richer driver profile
          // finishes loading after a restart/deep link.
          driverId: order.driverId ?? flow.assignedDriver?.userId,
          initialStatus: _markerStatus(order.status),
        );
  }

  DriverMarkerStatus _markerStatus(OrderStatus status) {
    if (status == OrderStatus.arrived) return DriverMarkerStatus.waiting;
    if (status == OrderStatus.evacuating ||
        status == OrderStatus.awaitingPayment) {
      return DriverMarkerStatus.toDestination;
    }
    return DriverMarkerStatus.toPickup;
  }

  @override
  void dispose() {
    _routeGeneration++;
    _auditReplayTimer?.cancel();
    _staleStateTimer?.cancel();
    super.dispose();
  }

  void _startAuditReplay() {
    _auditReplayTimer?.cancel();
    _auditReplayTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        if (_auditReplayIndex == _auditReplayPoints.length - 1) {
          _auditReplayForward = false;
        } else if (_auditReplayIndex == 0) {
          _auditReplayForward = true;
        }
        _auditReplayIndex += _auditReplayForward ? 1 : -1;
        _auditSampledAt = DateTime.now();
      });
    });
  }

  DriverLocationUpdate _auditReplayUpdate(String? orderId) {
    final point = _auditReplayPoints[_auditReplayIndex];
    final direction = _auditReplayIndex == _auditReplayPoints.length - 1
        ? -1
        : _auditReplayIndex == 0
            ? 1
            : (_auditReplayForward ? 1 : -1);
    final next = _auditReplayPoints[_auditReplayIndex + direction];
    return DriverLocationUpdate(
      driverId: 'audit-driver',
      lat: point.latitude,
      lng: point.longitude,
      bearing: _bearingBetween(point, next),
      speed: 9,
      status: DriverMarkerStatus.toPickup,
      orderId: orderId,
      timestamp: _auditSampledAt,
    );
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final fromLat = from.latitude * math.pi / 180;
    final toLat = to.latitude * math.pi / 180;
    final y = math.sin(dLng) * math.cos(toLat);
    final x = math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Future<void> _refreshRoute(Order order, DriverLocationUpdate update) async {
    final origin = LatLng(update.lat, update.lng);
    final target = _targetFor(order);
    final phaseChanged = _lastRouteStatus != order.status;
    final targetChanged =
        _lastRouteTarget == null || _distance(_lastRouteTarget!, target) >= 1;
    final samePending = _pendingRouteOrderId == order.id &&
        _pendingRouteStatus == order.status &&
        _pendingRouteOrigin != null &&
        _pendingRouteTarget != null &&
        _distance(_pendingRouteOrigin!, origin) < 75 &&
        _distance(_pendingRouteTarget!, target) < 1;
    if (samePending ||
        (!phaseChanged &&
            !targetChanged &&
            _lastRouteOrderId == order.id &&
            _lastRouteOrigin != null &&
            _distance(_lastRouteOrigin!, origin) < 75)) {
      return;
    }
    final generation = ++_routeGeneration;
    _pendingRouteOrigin = origin;
    _pendingRouteTarget = target;
    _pendingRouteStatus = order.status;
    _pendingRouteOrderId = order.id;
    final route = await OpenStreetMapService.getOrderRoutePreview(
      orderId: order.id,
      fromLat: origin.latitude,
      fromLng: origin.longitude,
    );
    if (!mounted || generation != _routeGeneration) return;
    _pendingRouteOrigin = null;
    _pendingRouteTarget = null;
    _pendingRouteStatus = null;
    _pendingRouteOrderId = null;
    if (route == null || route.points.length < 2) {
      setState(() => _routeError = 'Перестраиваем маршрут');
      return;
    }
    setState(() {
      _lastRouteOrigin = origin;
      _lastRouteTarget = target;
      _lastRouteStatus = order.status;
      _lastRouteOrderId = order.id;
      _routePoints = route.points;
      _routeDurationSeconds = route.durationSeconds;
      _routeError = null;
    });
  }

  LatLng _targetFor(Order order) {
    final isDelivery = order.status == OrderStatus.evacuating ||
        order.status == OrderStatus.awaitingPayment;
    final target = isDelivery ? order.dropoffLocation : order.pickupLocation;
    return LatLng(target.lat, target.lng);
  }

  double _distance(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double? get _remainingKm {
    if (_routePoints.length < 2) return null;
    var meters = 0.0;
    for (var i = 1; i < _routePoints.length; i++) {
      meters += _distance(_routePoints[i - 1], _routePoints[i]);
    }
    return meters / 1000;
  }

  void _openChat(Order order, Driver? driver) {
    final name = driver?.fullName?.trim().isNotEmpty == true
        ? driver!.fullName!
        : 'Водитель';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatScreen(
          orderId: order.id,
          title: name,
          auditDemo: widget.auditDemo,
          readOnly: _isTerminal(order.status)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(orderFlowProvider, (previous, next) {
      if (widget.auditDemo) return;
      final previousOrder = previous?.activeOrder;
      final nextOrder = next.activeOrder;
      final assignmentChanged = previousOrder?.id != nextOrder?.id ||
          previousOrder?.driverId != nextOrder?.driverId;
      if (nextOrder != null &&
          !_isTerminal(nextOrder.status) &&
          (assignmentChanged ||
              previous?.assignedDriver?.userId !=
                  next.assignedDriver?.userId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _startSession());
      }
    });
    final flow = ref.watch(orderFlowProvider);
    final order = flow.activeOrder;
    final driver = flow.assignedDriver;
    final session = ref.watch(realTimeDriverProvider);
    final update =
        widget.auditDemo ? _auditReplayUpdate(order?.id) : session.latestUpdate;
    if (order == null) {
      return const Scaffold(
          body: Center(child: Text('Информация о заказе недоступна')));
    }
    if (_isTerminal(order.status)) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => ref.read(realTimeDriverProvider.notifier).stopTracking());
    }
    if (!widget.auditDemo && update != null && update.orderId == order.id) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _refreshRoute(order, update));
    }
    final age =
        update == null ? null : DateTime.now().difference(update.timestamp);
    final fresh = age != null &&
        age >= Duration.zero &&
        age < const Duration(seconds: 45);
    return LayoutBuilder(builder: (context, constraints) {
      final safe = MediaQuery.paddingOf(context);
      final controlsBottom =
          constraints.maxHeight * _sheetExtent + safe.bottom + 24;
      return Scaffold(
        body: Stack(children: [
          Positioned.fill(
              child: LiveDriverMap(
            pickupLocation: flow.pickupLocation,
            destinationLocation: flow.destinationLocation,
            showSearchAnimation: false,
            routePoints: _routePoints,
            animatedDriverLocation: update,
            animateDriverMarker: true,
            driverMarkerBuilder: (location) => _TowTruckMarker(
              bearing: location.bearing,
              status: location.status,
            ),
            routeColor: order.status == OrderStatus.evacuating
                ? AvroClientColors.info
                : AvroClientColors.accent,
            // A wider, round-capped route with a light casing stays legible on
            // detailed OSM tiles without pretending a straight line is a road.
            routeStrokeWidth: 5,
            routeBorderStrokeWidth: 2.4,
            // At zoom 12 the markers are 28 px; at zoom 18 they reach 44 px.
            scaleMarkersWithZoom: true,
            controlsBottomOffset: controlsBottom,
            attributionBottomOffset: controlsBottom - 2,
            attributionRightOffset: 92,
            showRecenterButton: _manualCamera,
            onManualCamera: () => setState(() => _manualCamera = true),
            onRecenter: () => setState(() => _manualCamera = false),
            // Expanding the sheet changes the usable map viewport, but must
            // not repeatedly fit the camera while the marker animates.
            fitToMarkers: !_manualCamera && _sheetExtent < .6,
            fitPadding:
                EdgeInsets.fromLTRB(24, safe.top + 92, 24, controlsBottom + 16),
            initialZoom:
                widget.auditDemo && _visualCaptureState == 'close' ? 17 : 15,
          )),
          if (_sheetExtent < .6)
            Positioned(
                top: safe.top + 12,
                left: 16,
                right: 16,
                child: _ArrivalCard(
                    order: order,
                    fresh: fresh,
                    eta: _eta(order, fresh),
                    remainingKm: _remainingKm)),
          if (_routeError != null)
            Positioned(
                top: safe.top + 92,
                left: 16,
                child: _QuietNotice(text: _routeError!)),
          if (_connectionNotice(session, fresh) case final notice?)
            Positioned(
                top: safe.top + (_routeError == null ? 92 : 138),
                left: 16,
                child: _QuietNotice(text: notice)),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notice) {
              // A forceful downward gesture can settle at minChildSize (.34)
              // instead of the nearby compact snap (.37). Treat the whole
              // compact/expanded terminal bands as their stable viewport so
              // map controls never keep the previous expanded offset.
              final settledExtent = notice.extent <= .40
                  ? .37
                  : notice.extent >= .84
                      ? .88
                      : null;
              if (settledExtent != null &&
                  (_sheetExtent - settledExtent).abs() > .01) {
                setState(() => _sheetExtent = settledExtent);
              }
              return false;
            },
            child: DraggableScrollableSheet(
              initialChildSize: _sheetExtent,
              minChildSize: .34,
              maxChildSize: .88,
              snap: true,
              snapSizes: const [.37, .88],
              builder: (_, controller) => _TrackingDetailsSheet(
                controller: controller,
                expanded: _sheetExtent >= .6,
                order: order,
                driver: driver,
                fresh: fresh,
                age: age,
                pickupAddress: flow.pickupLocation?.displayAddress ??
                    order.pickupLocation.address,
                destinationAddress: flow.destinationLocation?.displayAddress ??
                    order.dropoffLocation.address,
                onChat: () => _openChat(order, driver),
              ),
            ),
          ),
        ]),
      );
    });
  }

  String _eta(Order order, bool fresh) {
    if (order.status == OrderStatus.arrived) return 'Эвакуатор прибыл';
    if (!fresh) return 'Время уточняется';
    if (order.status == OrderStatus.evacuating) return 'Везём автомобиль';
    if (order.status == OrderStatus.awaitingPayment) return 'Ожидаем оплату';
    final seconds = _routeDurationSeconds;
    return seconds == null || seconds <= 0
        ? 'Время уточняется'
        : 'Приедет через ${(seconds / 60).ceil()} минут';
  }

  String? _connectionNotice(RealTimeDriverState session, bool fresh) {
    if (widget.auditDemo) return null;
    return switch (session.connectionStatus) {
      'connecting' => 'Подключаемся к отслеживанию',
      'connection_failed' ||
      'error' ||
      'disconnected' when !fresh =>
        'Восстанавливаем связь',
      _ => null,
    };
  }

  bool _isTerminal(OrderStatus status) =>
      status == OrderStatus.completed || status == OrderStatus.cancelled;
}

class _TowTruckMarker extends StatelessWidget {
  const _TowTruckMarker({required this.bearing, required this.status});
  final double bearing;
  final DriverMarkerStatus status;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Позиция эвакуатора',
        child: SizedBox(
            width: 44,
            height: 44,
            child: Transform.rotate(
              angle: bearing * math.pi / 180,
              child: Image.asset(
                status == DriverMarkerStatus.toDestination
                    ? 'assets/images/vehicles/truck_loaded.png'
                    : 'assets/images/vehicles/truck.png',
                width: 42,
                height: 42,
                filterQuality: FilterQuality.high,
              ),
            )),
      );
}

class _ArrivalCard extends StatelessWidget {
  const _ArrivalCard(
      {required this.order,
      required this.fresh,
      required this.eta,
      required this.remainingKm});
  final Order order;
  final bool fresh;
  final String eta;
  final double? remainingKm;
  @override
  Widget build(BuildContext context) {
    final arrived = order.status == OrderStatus.arrived;
    final detail = arrived
        ? 'Ожидает у точки подачи'
        : !fresh
            ? 'Уточняем местоположение эвакуатора'
            : remainingKm != null
                ? 'Осталось ${remainingKm!.toStringAsFixed(1).replaceAll('.', ',')} км'
                : 'Маршрут уточняется';
    return Semantics(
        label: '$eta. $detail',
        child: Material(
          color: AvroClientColors.background.withValues(alpha: .97),
          borderRadius: BorderRadius.circular(20),
          elevation: 5,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eta,
                      style: EvikTypography.bodyLarge
                          .copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: EvikTypography.bodyMedium
                          .copyWith(color: AvroClientColors.textSecondary))
                ],
              )),
        ));
  }
}

class _QuietNotice extends StatelessWidget {
  const _QuietNotice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: AvroClientColors.background.withValues(alpha: .95),
            borderRadius: BorderRadius.circular(99)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(text,
                style: EvikTypography.bodyMedium
                    .copyWith(color: AvroClientColors.textSecondary))),
      );
}

class _TrackingDetailsSheet extends StatelessWidget {
  const _TrackingDetailsSheet({
    required this.controller,
    required this.expanded,
    required this.order,
    required this.driver,
    required this.fresh,
    required this.age,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.onChat,
  });
  final ScrollController controller;
  final bool expanded;
  final Order order;
  final Driver? driver;
  final bool fresh;
  final Duration? age;
  final String pickupAddress;
  final String destinationAddress;
  final VoidCallback onChat;

  Future<void> _call(String phone) async =>
      launchUrl(Uri(scheme: 'tel', path: phone));

  @override
  Widget build(BuildContext context) {
    final phone = driver?.phone?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;
    final name = driver?.fullName?.trim().isNotEmpty == true
        ? driver!.fullName!
        : 'Водитель уточняется';
    final plate = driver?.vehicleNumber.trim().isNotEmpty == true
        ? driver!.vehicleNumber
        : 'Номер уточняется';
    final model = driver?.vehicleModel.trim().isNotEmpty == true
        ? driver!.vehicleModel
        : 'Эвакуатор уточняется';
    final arrived = order.status == OrderStatus.arrived;
    return Material(
      color: AvroClientColors.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(
                20, 10, 20, 18 + MediaQuery.paddingOf(context).bottom),
            children: [
              Center(
                  child: Semantics(
                      label: 'Потяните вверх, чтобы раскрыть детали',
                      child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                              color: AvroClientColors.tabInactive,
                              borderRadius: BorderRadius.circular(4))))),
              const SizedBox(height: 16),
              Text(_statusText(order.status),
                  style: EvikTypography.bodyLarge
                      .copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(children: [
                _DriverAvatar(driver: driver),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: EvikTypography.bodyLarge
                              .copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                          driver == null
                              ? 'Данные водителя загружаются'
                              : '★ ${driver!.rating.toStringAsFixed(1)} · ${driver!.totalOrders} заказов',
                          style: EvikTypography.bodyMedium
                              .copyWith(color: AvroClientColors.textSecondary)),
                    ])),
              ]),
              const SizedBox(height: 14),
              _VehicleCard(
                  model: model,
                  plate: plate,
                  type: _platformName(driver?.vehicleType)),
              const SizedBox(height: 14),
              if (arrived)
                const _ArrivalActions()
              else
                _ContactActions(
                    hasPhone: hasPhone,
                    phone: phone,
                    onCall: _call,
                    onChat: onChat),
              if (expanded) ...[
                const SizedBox(height: 12),
                Text(
                    fresh
                        ? 'Позиция эвакуатора обновляется'
                        : age == null
                            ? 'Уточняем местоположение эвакуатора'
                            : 'Последняя позиция получена ${age!.inMinutes} мин назад',
                    style: EvikTypography.bodyMedium.copyWith(
                        color: fresh
                            ? AvroClientColors.successDeep
                            : AvroClientColors.textSecondary)),
                const SizedBox(height: 26),
                Text('Детали заказа', style: EvikTypography.h3),
                const SizedBox(height: 14),
                _AddressRow(
                    icon: Icons.trip_origin_rounded,
                    label: 'Подача',
                    address: pickupAddress,
                    color: AvroClientColors.success),
                const SizedBox(height: 16),
                _AddressRow(
                    icon: Icons.flag_rounded,
                    label: 'Назначение',
                    address: destinationAddress,
                    color: AvroClientColors.accent),
                const SizedBox(height: 18),
                _DetailsCard(children: [
                  _DetailLine(
                      'Ваш автомобиль', _vehicleName(order.vehicleType)),
                  _DetailLine('Стоимость',
                      '${(order.finalPrice ?? order.estimatedPrice).toStringAsFixed(0)} ₽'),
                  _DetailLine(
                      'Оплата',
                      order.paymentMethod == PaymentMethod.card
                          ? 'Картой'
                          : 'Наличными'),
                  if (order.notes?.trim().isNotEmpty == true)
                    _DetailLine('Комментарий', order.notes!.trim(),
                        multiline: true),
                  _DetailLine('Платформа', _platformName(driver?.vehicleType)),
                  const _DetailLine(
                      'Допустимая масса', 'Уточняется у водителя'),
                ]),
                const SizedBox(height: 22),
                const _DisabledActionRow(
                    icon: Icons.ios_share_rounded,
                    label: 'Поделиться трекингом',
                    hint: 'Скоро будет доступно'),
                const _DisabledActionRow(
                    icon: Icons.support_agent_rounded,
                    label: 'Помощь и поддержка',
                    hint: 'Скоро будет доступно'),
                const _DisabledActionRow(
                    icon: Icons.edit_outlined,
                    label: 'Изменить детали заказа',
                    hint: 'Недоступно после назначения'),
                const _DisabledActionRow(
                    icon: Icons.cancel_outlined,
                    label: 'Отменить заказ',
                    hint: 'Обратитесь в поддержку',
                    danger: true),
              ],
            ]),
      ),
    );
  }

  static String _platformName(VehicleType? type) => switch (type) {
        VehicleType.light => 'Лебёдка',
        VehicleType.suv => 'Манипулятор',
        VehicleType.minibus => 'Усиленная платформа',
        VehicleType.truck => 'Платформа',
        null => 'Тип платформы уточняется',
      };
  static String _vehicleName(VehicleType type) => switch (type) {
        VehicleType.light => 'Легковой автомобиль',
        VehicleType.suv => 'Внедорожник',
        VehicleType.minibus => 'Минивэн',
        VehicleType.truck => 'Грузовой автомобиль',
      };
  static String _statusText(OrderStatus status) => switch (status) {
        OrderStatus.arrived => 'Эвакуатор ждёт у вас',
        OrderStatus.evacuating => 'Везём автомобиль',
        OrderStatus.awaitingPayment => 'Ожидаем оплату',
        OrderStatus.completed => 'Заказ завершён',
        OrderStatus.cancelled => 'Заказ отменён',
        _ => 'Водитель едет к вам',
      };
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.driver});
  final Driver? driver;
  @override
  Widget build(BuildContext context) {
    final letter = driver?.fullName?.trim().isNotEmpty == true
        ? driver!.fullName!.trim()[0].toUpperCase()
        : 'В';
    return Semantics(
        label: 'Фото водителя',
        child: CircleAvatar(
            radius: 26,
            backgroundColor: AvroClientColors.accent.withValues(alpha: .16),
            child: Text(letter,
                style: EvikTypography.h3
                    .copyWith(color: AvroClientColors.accent))));
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard(
      {required this.model, required this.plate, required this.type});
  final String model;
  final String plate;
  final String type;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: AvroClientColors.surface.withValues(alpha: .52),
            borderRadius: BorderRadius.circular(18)),
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.local_shipping_rounded,
                  color: AvroClientColors.accent, size: 28),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(model,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: EvikTypography.bodyLarge
                            .copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(type,
                        style: EvikTypography.bodyMedium
                            .copyWith(color: AvroClientColors.textSecondary)),
                  ])),
              const SizedBox(width: 8),
              Semantics(
                  label: 'Государственный номер $plate',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: AvroClientColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AvroClientColors.textPrimary)),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Text(plate,
                            style: EvikTypography.bodyMedium
                                .copyWith(fontWeight: FontWeight.w800))),
                  )),
            ])),
      );
}

class _ContactActions extends StatelessWidget {
  const _ContactActions(
      {required this.hasPhone,
      required this.phone,
      required this.onCall,
      required this.onChat});
  final bool hasPhone;
  final String? phone;
  final Future<void> Function(String) onCall;
  final VoidCallback onChat;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: _ActionButton(
                icon: Icons.call_rounded,
                label: 'Позвонить',
                enabled: hasPhone,
                tooltip: hasPhone
                    ? 'Позвонить водителю'
                    : 'Номер водителя пока недоступен',
                onPressed: hasPhone ? () => onCall(phone!) : null)),
        const SizedBox(width: 10),
        Expanded(
            child: _ActionButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Чат',
                tooltip: 'Открыть чат с водителем',
                onPressed: onChat)),
      ]);
}

class _ArrivalActions extends StatelessWidget {
  const _ArrivalActions();
  @override
  Widget build(BuildContext context) => const Row(children: [
        Expanded(
            child: _ActionButton(
                icon: Icons.visibility_rounded, label: 'Я вижу эвакуатор')),
        SizedBox(width: 10),
        Expanded(
            child: _ActionButton(
                icon: Icons.search_rounded,
                label: 'Не могу найти',
                outlined: true)),
      ]);
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon,
      required this.label,
      this.onPressed,
      this.enabled = true,
      this.tooltip,
      this.outlined = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final String? tooltip;
  final bool outlined;
  @override
  Widget build(BuildContext context) => Tooltip(
      message: tooltip ?? label,
      child: SizedBox(
          height: 48,
          child: outlined
              ? OutlinedButton.icon(
                  onPressed: enabled ? onPressed : null,
                  icon: Icon(icon, size: 19),
                  label:
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AvroClientColors.textPrimary,
                      side: const BorderSide(color: AvroClientColors.surface),
                      elevation: 1,
                      shadowColor: Colors.black.withValues(alpha: .12)))
              : FilledButton.icon(
                  onPressed: enabled ? onPressed : null,
                  icon: Icon(icon, size: 19),
                  label:
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(
                      backgroundColor: AvroClientColors.accent,
                      disabledBackgroundColor: AvroClientColors.surface,
                      foregroundColor: AvroClientColors.background,
                      disabledForegroundColor: AvroClientColors.textDisabled,
                      elevation: 2,
                      shadowColor: AvroClientColors.accentStrong
                          .withValues(alpha: .28)))));
}

class _AddressRow extends StatelessWidget {
  const _AddressRow(
      {required this.icon,
      required this.label,
      required this.address,
      required this.color});
  final IconData icon;
  final String label;
  final String address;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: EvikTypography.bodyMedium
                  .copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(address,
              style: EvikTypography.bodyLarge
                  .copyWith(color: AvroClientColors.textSecondary)),
        ])),
      ]);
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          color: AvroClientColors.surface.withValues(alpha: .52),
          borderRadius: BorderRadius.circular(18)),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(children: children)));
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value, {this.multiline = false});
  final String label;
  final String value;
  final bool multiline;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: multiline
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: EvikTypography.bodyMedium
                      .copyWith(color: AvroClientColors.textSecondary)),
              const SizedBox(height: 5),
              Text(value,
                  style: EvikTypography.bodyLarge
                      .copyWith(fontWeight: FontWeight.w700)),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Text(label,
                      style: EvikTypography.bodyMedium
                          .copyWith(color: AvroClientColors.textSecondary))),
              const SizedBox(width: 16),
              Flexible(
                  child: Text(value,
                      textAlign: TextAlign.end,
                      style: EvikTypography.bodyMedium
                          .copyWith(fontWeight: FontWeight.w800))),
            ]));
}

class _DisabledActionRow extends StatelessWidget {
  const _DisabledActionRow(
      {required this.icon,
      required this.label,
      required this.hint,
      this.danger = false});
  final IconData icon;
  final String label;
  final String hint;
  final bool danger;
  @override
  Widget build(BuildContext context) => Semantics(
      label: '$label. $hint',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: false,
        leading: Icon(icon,
            color: danger
                ? AvroClientColors.error
                : AvroClientColors.textSecondary),
        title: Text(label,
            style: EvikTypography.bodyLarge.copyWith(
                color: danger
                    ? AvroClientColors.error
                    : AvroClientColors.textPrimary)),
        subtitle: Text(hint,
            style: EvikTypography.bodyMedium
                .copyWith(color: AvroClientColors.textSecondary)),
      ));
}

class _OrderChatSheet extends StatefulWidget {
  const _OrderChatSheet(
      {required this.order, required this.driver, required this.auditDemo});
  final Order order;
  final Driver? driver;
  final bool auditDemo;
  @override
  State<_OrderChatSheet> createState() => _OrderChatSheetState();
}

class _OrderChatSheetState extends State<_OrderChatSheet> {
  final _controller = TextEditingController();
  final _messages = <String>[];
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.driver?.fullName?.trim().isNotEmpty == true
        ? widget.driver!.fullName!
        : 'Водитель';
    final canSend = widget.auditDemo;
    return SafeArea(
        top: false,
        child: FractionallySizedBox(
            heightFactor: .92,
            child: Material(
              color: AvroClientColors.background,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(children: [
                      IconButton(
                          tooltip: 'Вернуться к карте',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded)),
                      _DriverAvatar(driver: widget.driver),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(name,
                                style: EvikTypography.bodyLarge
                                    .copyWith(fontWeight: FontWeight.w800)),
                            Text('Чат по текущему заказу',
                                style: EvikTypography.bodyMedium.copyWith(
                                    color: AvroClientColors.textSecondary)),
                          ])),
                      const IconButton(
                          tooltip: 'Позвонить водителю',
                          onPressed: null,
                          icon: Icon(Icons.call_rounded)),
                    ])),
                const Divider(height: 1),
                Expanded(
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                  Center(
                      child: Text('Сегодня',
                          style: EvikTypography.bodyMedium.copyWith(
                              color: AvroClientColors.textSecondary))),
                  const SizedBox(height: 18),
                  if (widget.auditDemo) ...[
                    const _ChatBubble(
                        text: 'Буду у машины через несколько минут.',
                        incoming: true),
                    const SizedBox(height: 10),
                    ..._messages.map((m) => Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _ChatBubble(text: m, incoming: false)))
                  ] else
                    const _ChatUnavailable(),
                ])),
                DecoratedBox(
                    decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: AvroClientColors.surface))),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 10, 16,
                          10 + MediaQuery.viewInsetsOf(context).bottom),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                                tooltip: 'Прикрепить фото или точку',
                                onPressed: canSend ? () {} : null,
                                icon: const Icon(
                                    Icons.add_circle_outline_rounded)),
                            Expanded(
                                child: TextField(
                                    controller: _controller,
                                    enabled: canSend,
                                    minLines: 1,
                                    maxLines: 4,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                        hintText: canSend
                                            ? 'Напишите сообщение'
                                            : 'Чат подключается…',
                                        filled: true,
                                        fillColor: AvroClientColors.surface
                                            .withValues(alpha: .45),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            borderSide: BorderSide.none)))),
                            IconButton(
                                tooltip: 'Отправить',
                                color: AvroClientColors.accent,
                                onPressed: canSend
                                    ? () {
                                        final value = _controller.text.trim();
                                        if (value.isEmpty) return;
                                        setState(() => _messages.add(value));
                                        _controller.clear();
                                      }
                                    : null,
                                icon: const Icon(Icons.send_rounded)),
                          ]),
                    )),
              ]),
            )));
  }
}

class _ChatUnavailable extends StatelessWidget {
  const _ChatUnavailable();
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 90),
      child: Column(children: [
        const Icon(Icons.lock_outline_rounded,
            size: 36, color: AvroClientColors.textSecondary),
        const SizedBox(height: 12),
        Text('Чат подключается', style: EvikTypography.h3),
        const SizedBox(height: 6),
        Text(
            'Сообщения станут доступны, когда сервер создаст чат этого заказа.',
            textAlign: TextAlign.center,
            style: EvikTypography.bodyLarge
                .copyWith(color: AvroClientColors.textSecondary)),
      ]));
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.incoming});
  final String text;
  final bool incoming;
  @override
  Widget build(BuildContext context) => Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Semantics(
          label: '${incoming ? 'Водитель' : 'Вы'}: $text',
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: incoming
                    ? AvroClientColors.surface.withValues(alpha: .62)
                    : AvroClientColors.accent.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(18)),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                child: Text(text, style: EvikTypography.bodyLarge)),
          )));
}
