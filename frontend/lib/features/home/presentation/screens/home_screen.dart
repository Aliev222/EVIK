import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/bootstrap/app_bootstrap.dart';
import '../../../../core/map/map_provider.dart';
import '../../../../core/realtime/event_dispatcher.dart';
import '../../../../core/theme/evik_colors.dart';
import '../../../map/data/yandex_map_provider.dart';
import '../../../map/presentation/widgets/yandex_map_view.dart';
import '../../../order/domain/entities/order.dart';
import '../../../order/domain/repositories/order_repository.dart';
import '../../../order/presentation/state/order_state_notifier.dart';
import '../state/app_flow_notifier.dart';

const _demoClientId = 'demo-user';
const _demoDriverId = 'demo-driver';
const _demoClientPhone = '+7 999 123-45-67';
const _defaultDriverLocation = Location(lat: 55.751244, lng: 37.618423);

class DriverRouteSnapshot {
  const DriverRouteSnapshot({
    required this.distanceKm,
    required this.etaMinutes,
  });

  final double distanceKm;
  final int etaMinutes;
}

final driverRouteSnapshotProvider =
    StateProvider<DriverRouteSnapshot?>((ref) => null);

class _UiText {
  static const h1 = TextStyle(
    color: EvikColors.textPrimaryDark,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.15,
  );

  static const h2 = TextStyle(
    color: EvikColors.textPrimaryDark,
    fontSize: 23,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const body = TextStyle(
    color: EvikColors.textPrimaryDark,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const caption = TextStyle(
    color: EvikColors.textSecondaryDark,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _phone = TextEditingController(text: '+7 (999) 123-45-67');
  final _otp = TextEditingController();
  final _addressSearch = TextEditingController();
  final _comment = TextEditingController();

  String _fromAddress = 'Моё местоположение';
  String? _toAddress;
  bool _pickFrom = false;
  String _vehicleType = 'Седан';
  int _lockedWheels = 0;
  bool _running = true;
  String _tariff = 'Стандарт';
  String? _driverOrderId;
  Coordinate? _fromCoordinate;
  Coordinate? _toCoordinate;
  Location? _deviceLocation;
  StreamSubscription<Event>? _driverEventsSub;
  StreamSubscription<Location>? _deviceLocationSub;
  Timer? _driverPollTimer;
  DateTime? _lastDriverLocationPushAt;
  bool _driverEventsStarting = false;
  bool _clientCancelInFlight = false;
  bool _driverAcceptInFlight = false;
  bool _driverCancelInFlight = false;
  bool _driverCompleteInFlight = false;
  static const _driverOfferMaxAge = Duration(minutes: 5);
  String? _clientTerminalNotice;
  String? _driverTerminalNotice;

  static const _suggestions = <String>[
    'Лесная улица, 15',
    'Кирова, 78А',
    'ТЦ «Сокол», Летняя, 14',
    'Аэропорт, терминал B',
    'Южный вокзал',
  ];

  static const _vehicleTypes = <String>[
    'Седан',
    'Кроссовер',
    'Минивэн',
    'Фургон'
  ];

  static const _tariffs = <_Tariff>[
    _Tariff('Стандарт', 3900, '12 мин'),
    _Tariff('Комфорт', 4900, '10 мин'),
    _Tariff('Экспресс', 6200, '7 мин'),
  ];

  _Tariff get _activeTariff => _tariffs.firstWhere((t) => t.name == _tariff,
      orElse: () => _tariffs.first);

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final mapProvider = ref.read(mapProviderProvider);
      await mapProvider.init();
      _deviceLocationSub = mapProvider.onLocationChanged().listen((location) {
        _deviceLocation = location;
        unawaited(_pushDriverLocation(location));
      });
    });
  }

  @override
  void dispose() {
    _driverEventsSub?.cancel();
    _deviceLocationSub?.cancel();
    _driverPollTimer?.cancel();
    _phone.dispose();
    _otp.dispose();
    _addressSearch.dispose();
    _comment.dispose();
    super.dispose();
  }

  void _resetClient() {
    setState(() {
      _fromAddress = 'Моё местоположение';
      _toAddress = null;
      _fromCoordinate = null;
      _toCoordinate = null;
      _pickFrom = false;
      _vehicleType = 'Седан';
      _lockedWheels = 0;
      _running = true;
      _tariff = 'Стандарт';
      _comment.clear();
      _clientTerminalNotice = null;
    });
    ref.read(appFlowProvider.notifier).setClientStage(ClientHomeStage.idle);
  }

  Future<void> _cancelClientOrder() async {
    if (_clientCancelInFlight) return;
    final status = ref.read(orderStateNotifierProvider).status;
    if (status == OrderState.searching ||
        status == OrderState.accepted ||
        status == OrderState.arrived ||
        status == OrderState.inProgress) {
      _clientCancelInFlight = true;
      try {
        await ref
            .read(orderStateNotifierProvider.notifier)
            .cancelCurrentOrder(reason: 'client_cancelled');
      } finally {
        _clientCancelInFlight = false;
      }
      return;
    }
    _resetClient();
  }

  Future<void> _submitOrder() async {
    if (_clientTerminalNotice != null) {
      setState(() => _clientTerminalNotice = null);
    }
    final pickup = await _resolvePickupCoordinate();
    final dropoff = _resolveDropoffCoordinate(pickup);
    ref.read(orderStateNotifierProvider.notifier).submitOrder(
          CreateOrderCommand(
            userId: _demoClientId,
            pickup: pickup,
            dropoff: dropoff,
          ),
        );
  }

  Future<void> _setDriverOnline(bool value) async {
    try {
      await ref.read(driverRemoteDataSourceProvider).setStatus(
            driverId: _demoDriverId,
            userId: _demoDriverId,
            status: value ? 'online' : 'offline',
            lat: value
                ? (_deviceLocation?.lat ?? _defaultDriverLocation.lat)
                : null,
            lng: value
                ? (_deviceLocation?.lng ?? _defaultDriverLocation.lng)
                : null,
          );
      if (!mounted) return;
      if (!value) {
        _driverOrderId = null;
      }
      ref.read(appFlowProvider.notifier).toggleDriverOnline(value);
      if (value) {
        unawaited(_ensureDriverEvents());
      }
    } catch (e) {
      if (!mounted) return;
      _showActionError(e);
    }
  }

  Future<void> _acceptDriverOrder() async {
    if (_driverAcceptInFlight) return;
    final orderId = await _resolveDriverOrderId(includeSearchingFallback: true);
    if (orderId == null) {
      return;
    }
    setState(() => _driverAcceptInFlight = true);

    final apiClient = ref.read(apiClientProvider);
    final driverDataSource = ref.read(driverRemoteDataSourceProvider);

    try {
      await driverDataSource.setStatus(
        driverId: _demoDriverId,
        userId: _demoDriverId,
        status: 'online',
        lat: _deviceLocation?.lat ?? _defaultDriverLocation.lat,
        lng: _deviceLocation?.lng ?? _defaultDriverLocation.lng,
      );
      await apiClient.post('/api/v1/orders/$orderId/accept', {
        'driver_id': _demoDriverId,
      });
      if (!mounted) return;
      ref
          .read(appFlowProvider.notifier)
          .setDriverStage(DriverHomeStage.accepted);
      if (_driverTerminalNotice != null) {
        setState(() => _driverTerminalNotice = null);
      }
    } catch (e) {
      if (!mounted) return;
      final acceptedByCurrentDriver =
          await _isOrderAcceptedByCurrentDriver(orderId);
      if (!mounted) return;
      if (acceptedByCurrentDriver) {
        ref
            .read(appFlowProvider.notifier)
            .setDriverStage(DriverHomeStage.accepted);
        return;
      }

      if (_isDriverUnavailableConflict(e)) {
        try {
          await Future<void>.delayed(const Duration(milliseconds: 180));
          await apiClient.post('/api/v1/orders/$orderId/accept', {
            'driver_id': _demoDriverId,
          });
          if (!mounted) return;
          ref
              .read(appFlowProvider.notifier)
              .setDriverStage(DriverHomeStage.accepted);
          return;
        } catch (_) {
          // Fall through to error feedback.
        }
      }
      ref.read(appFlowProvider.notifier).setDriverStage(DriverHomeStage.online);
      _showActionError(e);
    } finally {
      if (mounted) {
        setState(() => _driverAcceptInFlight = false);
      }
    }
  }

  void _rejectDriverOrder() {
    setState(() => _driverOrderId = null);
    ref.read(appFlowProvider.notifier).setDriverStage(DriverHomeStage.online);
  }

  Future<void> _cancelDriverOrder() async {
    if (_driverCancelInFlight) return;
    final orderId = await _resolveDriverOrderId();
    if (orderId == null) {
      if (mounted) {
        setState(() => _driverOrderId = null);
      }
      ref.read(appFlowProvider.notifier).setDriverStage(DriverHomeStage.online);
      return;
    }
    setState(() => _driverCancelInFlight = true);

    try {
      await ref.read(apiClientProvider).post('/api/v1/orders/$orderId/cancel', {
        'reason': 'driver_cancelled',
      });
      if (!mounted) return;
      _setDriverTerminalState(_driverCancellationMessage('driver_cancelled'));
    } catch (e) {
      if (!mounted) return;
      final status = await _fetchOrderStatus(orderId);
      if (!mounted) return;
      if (status == 'cancelled') {
        _setDriverTerminalState(_driverCancellationMessage('client_cancelled'));
        return;
      }
      if (status == 'completed') {
        _setDriverTerminalState(_driverCompletedMessage());
        return;
      }
      _showActionError(e);
    } finally {
      if (mounted) {
        setState(() => _driverCancelInFlight = false);
      }
    }
  }

  Future<void> _completeDriverOrder() async {
    if (_driverCompleteInFlight) return;
    final orderId = await _resolveDriverOrderId();
    if (orderId == null) {
      if (mounted) {
        setState(() => _driverOrderId = null);
      }
      ref.read(appFlowProvider.notifier).setDriverStage(DriverHomeStage.online);
      return;
    }
    setState(() => _driverCompleteInFlight = true);

    try {
      final status = await _fetchOrderStatus(orderId);
      if (status == 'cancelled') {
        if (!mounted) return;
        _setDriverTerminalState(_driverCancellationMessage('client_cancelled'));
        return;
      }
      if (status == 'completed') {
        if (!mounted) return;
        _setDriverTerminalState(_driverCompletedMessage());
        return;
      }
      await _transitionOrderToCompleted(
        orderId: orderId,
        currentStatus: status,
      );
      if (!mounted) return;
      _setDriverTerminalState(_driverCompletedMessage());
    } catch (e) {
      if (!mounted) return;
      final status = await _fetchOrderStatus(orderId);
      if (!mounted) return;
      if (status == 'cancelled') {
        _setDriverTerminalState(_driverCancellationMessage('client_cancelled'));
        return;
      }
      if (status == 'completed') {
        _setDriverTerminalState(_driverCompletedMessage());
        return;
      }
      _showActionError(e);
    } finally {
      if (mounted) {
        setState(() => _driverCompleteInFlight = false);
      }
    }
  }

  void _showActionError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _pushDriverLocation(Location location) async {
    final flow = ref.read(appFlowProvider);
    if (!flow.isDriver || flow.driverStage == DriverHomeStage.offline) {
      return;
    }

    final now = DateTime.now();
    if (_lastDriverLocationPushAt != null &&
        now.difference(_lastDriverLocationPushAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastDriverLocationPushAt = now;

    try {
      await ref.read(driverRemoteDataSourceProvider).setStatus(
            driverId: _demoDriverId,
            userId: _demoDriverId,
            status: 'online',
            lat: location.lat,
            lng: location.lng,
          );
    } catch (_) {
      // Live location is best-effort and should not interrupt UI flow.
    }
  }

  Future<Coordinate> _resolvePickupCoordinate() async {
    if (_fromCoordinate != null) return _fromCoordinate!;
    if (_deviceLocation != null) {
      return Coordinate(lat: _deviceLocation!.lat, lng: _deviceLocation!.lng);
    }
    return const Coordinate(lat: 55.751244, lng: 37.618423);
  }

  Coordinate _resolveDropoffCoordinate(Coordinate pickup) {
    if (_toCoordinate != null) return _toCoordinate!;
    return Coordinate(lat: pickup.lat + 0.01, lng: pickup.lng + 0.01);
  }

  Coordinate? _coordinateForSuggestion(String value) {
    final index = _suggestions.indexOf(value);
    switch (index) {
      case 0:
        return const Coordinate(lat: 55.7972, lng: 37.5885);
      case 1:
        return const Coordinate(lat: 55.8041, lng: 37.6409);
      case 2:
        return const Coordinate(lat: 55.8157, lng: 37.4971);
      case 3:
        return const Coordinate(lat: 55.9726, lng: 37.4146);
      case 4:
        return const Coordinate(lat: 55.7313, lng: 37.6533);
      default:
        return null;
    }
  }

  Future<void> _ensureDriverEvents() async {
    if (_driverEventsSub != null || _driverEventsStarting) return;
    _driverEventsStarting = true;
    final dispatcher = ref.read(eventDispatcherProvider);

    try {
      await dispatcher.start();
      _driverEventsSub = dispatcher.events().listen((event) {
        if (!mounted) return;
        final flow = ref.read(appFlowProvider);
        if (!flow.isDriver) {
          return;
        }
        if (event.type == 'cancelled') {
          if (_driverOrderId != null && _driverOrderId == event.orderId) {
            _setDriverTerminalState(
              _driverCancellationMessage(_eventReason(event)),
            );
          }
          return;
        }
        if (event.type == 'completed') {
          if (_driverOrderId != null && _driverOrderId == event.orderId) {
            _setDriverTerminalState(_driverCompletedMessage());
          }
          return;
        }
      });
      _driverPollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        unawaited(_pollDriverOrder());
      });
      unawaited(_pollDriverOrder());
    } finally {
      _driverEventsStarting = false;
    }
  }

  Future<void> _pollDriverOrder() async {
    if (!mounted) return;
    final flow = ref.read(appFlowProvider);
    if (!flow.isDriver) {
      return;
    }

    if (flow.driverStage == DriverHomeStage.online ||
        flow.driverStage == DriverHomeStage.newOrder) {
      try {
        final json = await ref
            .read(apiClientProvider)
            .get('/api/v1/orders?status=searching&limit=20');
        final candidate = _pickFreshDriverOffer(json['orders']);
        if (candidate != null) {
          final candidateId = candidate['id']?.toString();
          if (candidateId != null && candidateId.isNotEmpty) {
            setState(() {
              _driverOrderId = candidateId;
              _driverTerminalNotice = null;
            });
            ref
                .read(appFlowProvider.notifier)
                .setDriverStage(DriverHomeStage.newOrder);
            return;
          }
        }

        if (_driverOrderId != null) {
          setState(() => _driverOrderId = null);
        }
        if (flow.driverStage == DriverHomeStage.newOrder) {
          ref
              .read(appFlowProvider.notifier)
              .setDriverStage(DriverHomeStage.online);
        }
      } catch (_) {
        // WebSocket remains the primary path; polling is only a local-test fallback.
      }
      return;
    }

    if (_isDriverOrderFlowStage(flow.driverStage)) {
      final orderId = _driverOrderId ?? await _resolveDriverOrderId();
      if (orderId == null) {
        if (mounted && _driverOrderId != null) {
          setState(() => _driverOrderId = null);
        }
        ref
            .read(appFlowProvider.notifier)
            .setDriverStage(DriverHomeStage.online);
        return;
      }

      try {
        final json =
            await ref.read(apiClientProvider).get('/api/v1/orders/$orderId');
        final order = json['order'];
        if (order is! Map<String, dynamic>) return;
        final status = order['status']?.toString();

        if (status == 'cancelled') {
          _setDriverTerminalState(
              _driverCancellationMessage('client_cancelled'));
        } else if (status == 'completed') {
          _setDriverTerminalState(_driverCompletedMessage());
        } else if (status == 'accepted' &&
            flow.driverStage != DriverHomeStage.accepted) {
          if (mounted && _driverTerminalNotice != null) {
            setState(() => _driverTerminalNotice = null);
          }
          ref
              .read(appFlowProvider.notifier)
              .setDriverStage(DriverHomeStage.accepted);
        } else if (status == 'arrived' &&
            flow.driverStage != DriverHomeStage.arrived) {
          if (mounted && _driverTerminalNotice != null) {
            setState(() => _driverTerminalNotice = null);
          }
          ref
              .read(appFlowProvider.notifier)
              .setDriverStage(DriverHomeStage.arrived);
        } else if (status == 'in_progress' &&
            flow.driverStage != DriverHomeStage.enRoute) {
          if (mounted && _driverTerminalNotice != null) {
            setState(() => _driverTerminalNotice = null);
          }
          ref
              .read(appFlowProvider.notifier)
              .setDriverStage(DriverHomeStage.enRoute);
        } else if (status == 'searching' &&
            flow.driverStage != DriverHomeStage.newOrder) {
          if (mounted && _driverTerminalNotice != null) {
            setState(() => _driverTerminalNotice = null);
          }
          ref
              .read(appFlowProvider.notifier)
              .setDriverStage(DriverHomeStage.newOrder);
        }
      } catch (_) {
        // Keep current stage if backend is temporarily unavailable.
      }
    }
  }

  Map<String, dynamic>? _pickFreshDriverOffer(Object? rawOrders) {
    if (rawOrders is! List) return null;
    final now = DateTime.now();
    final candidates = rawOrders.whereType<Map<String, dynamic>>().toList()
      ..sort((a, b) {
        final aAt = _parseBackendDateTime(a['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bAt = _parseBackendDateTime(b['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bAt.compareTo(aAt);
      });

    for (final order in candidates) {
      final createdAt = _parseBackendDateTime(order['created_at']);
      if (createdAt == null) {
        return order;
      }
      if (now.difference(createdAt) <= _driverOfferMaxAge) {
        return order;
      }
    }
    return null;
  }

  DateTime? _parseBackendDateTime(Object? raw) {
    final text = raw?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  bool _isDriverOrderFlowStage(DriverHomeStage stage) {
    return stage == DriverHomeStage.newOrder ||
        stage == DriverHomeStage.accepted ||
        stage == DriverHomeStage.enRoute ||
        stage == DriverHomeStage.arrived;
  }

  bool _isDriverUnavailableConflict(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('409') && message.contains('driver unavailable');
  }

  Future<bool> _isOrderAcceptedByCurrentDriver(String orderId) async {
    try {
      final json =
          await ref.read(apiClientProvider).get('/api/v1/orders/$orderId');
      final order = json['order'];
      if (order is! Map<String, dynamic>) return false;
      final status = order['status']?.toString();
      final driverId = order['driver_id']?.toString();
      return status == 'accepted' && driverId == _demoDriverId;
    } catch (_) {
      return false;
    }
  }

  String _driverCompletedMessage() {
    return '\u0417\u0430\u043a\u0430\u0437 \u0437\u0430\u0432\u0435\u0440\u0448\u0451\u043d. '
        '\u041c\u043e\u0436\u043d\u043e \u043f\u0435\u0440\u0435\u0439\u0442\u0438 '
        '\u043a \u0441\u043b\u0435\u0434\u0443\u044e\u0449\u0438\u043c '
        '\u0437\u0430\u043a\u0430\u0437\u0430\u043c.';
  }

  void _setDriverTerminalState(String notice) {
    if (!mounted) return;
    setState(() {
      _driverOrderId = null;
      _driverTerminalNotice = notice;
    });
    ref
        .read(appFlowProvider.notifier)
        .setDriverStage(DriverHomeStage.completed);
  }

  Future<String?> _resolveDriverOrderId({
    bool includeSearchingFallback = false,
  }) async {
    final local = _driverOrderId;
    if (local != null && local.isNotEmpty) {
      return local;
    }

    try {
      final driver = await ref
          .read(driverRemoteDataSourceProvider)
          .getDriver(_demoDriverId);
      final currentOrderId = driver.currentOrderId;
      if (currentOrderId != null && currentOrderId.isNotEmpty) {
        if (mounted && _driverOrderId != currentOrderId) {
          setState(() => _driverOrderId = currentOrderId);
        }
        return currentOrderId;
      }
    } catch (_) {
      // Ignore transient sync errors and use fallback.
    }

    if (!includeSearchingFallback) return null;

    try {
      final json = await ref
          .read(apiClientProvider)
          .get('/api/v1/orders?status=searching&limit=20');
      final candidate = _pickFreshDriverOffer(json['orders']);
      final candidateId = candidate?['id']?.toString();
      if (candidateId != null && candidateId.isNotEmpty) {
        if (mounted) {
          setState(() {
            _driverOrderId = candidateId;
            _driverTerminalNotice = null;
          });
        }
        return candidateId;
      }
    } catch (_) {
      // Polling loop retries.
    }

    return null;
  }

  Future<String?> _fetchOrderStatus(String orderId) async {
    try {
      final json =
          await ref.read(apiClientProvider).get('/api/v1/orders/$orderId');
      final order = json['order'];
      if (order is! Map<String, dynamic>) return null;
      return order['status']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _transitionOrderToCompleted({
    required String orderId,
    required String? currentStatus,
  }) async {
    final apiClient = ref.read(apiClientProvider);

    Future<void> setStatus(String status) async {
      await apiClient.post('/api/v1/orders/$orderId/status', {
        'status': status,
      });
    }

    switch (currentStatus) {
      case 'completed':
        return;
      case 'in_progress':
        await setStatus('completed');
        return;
      case 'arrived':
        await setStatus('in_progress');
        await setStatus('completed');
        return;
      case 'accepted':
        await setStatus('arrived');
        await setStatus('in_progress');
        await setStatus('completed');
        return;
      default:
        await setStatus('completed');
    }
  }

  String? _eventReason(Event event) {
    final payload = event.payload;
    if (payload is Map<String, dynamic>) {
      final reason = payload['reason']?.toString();
      if (reason != null && reason.isNotEmpty) return reason;
    } else if (payload is Map) {
      final reason = payload['reason']?.toString();
      if (reason != null && reason.isNotEmpty) return reason;
    }
    return null;
  }

  String _clientCancellationMessage(String? reason) {
    switch (reason) {
      case 'driver_cancelled':
        return 'Водитель отменил заказ.';
      case 'driver_offline':
        return 'Водитель ушёл офлайн. Заказ отменён.';
      case 'client_cancelled':
        return 'Вы отменили заказ.';
      default:
        return 'Заказ отменён.';
    }
  }

  String _driverCancellationMessage(String? reason) {
    switch (reason) {
      case 'client_cancelled':
      case 'order_cancelled':
        return 'Клиент отменил заказ.';
      case 'driver_cancelled':
        return 'Вы отменили заказ.';
      case 'driver_offline':
        return 'Заказ отменён: водитель вне сети.';
      default:
        return 'Заказ отменён.';
    }
  }

  void _acknowledgeDriverTerminalState() {
    setState(() {
      _driverOrderId = null;
      _driverTerminalNotice = null;
    });
    ref.read(appFlowProvider.notifier).setDriverStage(DriverHomeStage.online);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(appFlowProvider);
    ref.listen<OrderUiState>(orderStateNotifierProvider, (previous, next) {
      final notifier = ref.read(appFlowProvider.notifier);
      switch (next.status) {
        case OrderState.searching:
          if (_clientTerminalNotice != null && mounted) {
            setState(() => _clientTerminalNotice = null);
          }
          notifier.setClientStage(ClientHomeStage.searching);
          break;
        case OrderState.accepted:
          if (_clientTerminalNotice != null && mounted) {
            setState(() => _clientTerminalNotice = null);
          }
          notifier.setClientStage(ClientHomeStage.driverFound);
          break;
        case OrderState.arrived:
          notifier.setClientStage(ClientHomeStage.driverArrived);
          break;
        case OrderState.inProgress:
          notifier.setClientStage(ClientHomeStage.driverEnRoute);
          break;
        case OrderState.completed:
          if (_clientTerminalNotice != null && mounted) {
            setState(() => _clientTerminalNotice = null);
          }
          notifier.setClientStage(ClientHomeStage.completed);
          break;
        case OrderState.cancelled:
          final message = _clientCancellationMessage(next.cancellationReason);
          if (_clientTerminalNotice != message && mounted) {
            setState(() => _clientTerminalNotice = message);
          }
          notifier.setClientStage(ClientHomeStage.completed);
          break;
        case OrderState.noDriverFound:
          notifier.setClientStage(ClientHomeStage.noDrivers);
          break;
        case OrderState.idle:
          break;
      }
    });
    if (flow.isDriver) {
      unawaited(_ensureDriverEvents());
    }
    return Scaffold(
      backgroundColor: EvikColors.darkBackground,
      body: switch (flow.authStep) {
        AuthStep.role => const _RoleScreen(),
        AuthStep.phone => _PhoneScreen(controller: _phone),
        AuthStep.sms => _OtpScreen(controller: _otp),
        AuthStep.success => const _SuccessScreen(),
        AuthStep.app => _MainShell(
            fromAddress: _fromAddress,
            toAddress: _toAddress,
            pickFrom: _pickFrom,
            addressSearch: _addressSearch,
            comment: _comment,
            vehicleType: _vehicleType,
            lockedWheels: _lockedWheels,
            running: _running,
            selectedTariff: _tariff,
            suggestions: _suggestions,
            vehicleTypes: _vehicleTypes,
            tariffs: _tariffs,
            activeTariff: _activeTariff,
            onPickField: (value) => setState(() => _pickFrom = value),
            onPickSuggestion: (value) => setState(() {
              final coordinate = _coordinateForSuggestion(value);
              if (_pickFrom) {
                _fromAddress = value;
                _fromCoordinate = coordinate;
              } else {
                _toAddress = value;
                _toCoordinate = coordinate;
              }
            }),
            onVehicleType: (value) => setState(() => _vehicleType = value),
            onLockedWheels: (value) =>
                setState(() => _lockedWheels = value.clamp(0, 4)),
            onRunning: (value) => setState(() => _running = value),
            onTariff: (value) => setState(() => _tariff = value),
            onReset: _resetClient,
            onCancelClientOrder: () => unawaited(_cancelClientOrder()),
            onSubmitOrder: () => unawaited(_submitOrder()),
            onDriverOnlineChanged: (value) =>
                unawaited(_setDriverOnline(value)),
            onAcceptDriverOrder: () => unawaited(_acceptDriverOrder()),
            onRejectDriverOrder: _rejectDriverOrder,
            onCancelDriverOrder: () => unawaited(_cancelDriverOrder()),
            onCompleteDriverOrder: () => unawaited(_completeDriverOrder()),
            isAcceptingDriverOrder: _driverAcceptInFlight,
            isCancellingDriverOrder: _driverCancelInFlight,
            isCompletingDriverOrder: _driverCompleteInFlight,
            clientTerminalNotice: _clientTerminalNotice,
            driverTerminalNotice: _driverTerminalNotice,
            onAcknowledgeDriverTerminal: _acknowledgeDriverTerminalState,
          ),
      },
    );
  }
}

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell({
    required this.fromAddress,
    required this.toAddress,
    required this.pickFrom,
    required this.addressSearch,
    required this.comment,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.selectedTariff,
    required this.suggestions,
    required this.vehicleTypes,
    required this.tariffs,
    required this.activeTariff,
    required this.onPickField,
    required this.onPickSuggestion,
    required this.onVehicleType,
    required this.onLockedWheels,
    required this.onRunning,
    required this.onTariff,
    required this.onReset,
    required this.onCancelClientOrder,
    required this.onSubmitOrder,
    required this.onDriverOnlineChanged,
    required this.onAcceptDriverOrder,
    required this.onRejectDriverOrder,
    required this.onCancelDriverOrder,
    required this.onCompleteDriverOrder,
    required this.isAcceptingDriverOrder,
    required this.isCancellingDriverOrder,
    required this.isCompletingDriverOrder,
    required this.clientTerminalNotice,
    required this.driverTerminalNotice,
    required this.onAcknowledgeDriverTerminal,
  });

  final String fromAddress;
  final String? toAddress;
  final bool pickFrom;
  final TextEditingController addressSearch;
  final TextEditingController comment;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final String selectedTariff;
  final List<String> suggestions;
  final List<String> vehicleTypes;
  final List<_Tariff> tariffs;
  final _Tariff activeTariff;
  final ValueChanged<bool> onPickField;
  final ValueChanged<String> onPickSuggestion;
  final ValueChanged<String> onVehicleType;
  final ValueChanged<int> onLockedWheels;
  final ValueChanged<bool> onRunning;
  final ValueChanged<String> onTariff;
  final VoidCallback onReset;
  final VoidCallback onCancelClientOrder;
  final VoidCallback onSubmitOrder;
  final ValueChanged<bool> onDriverOnlineChanged;
  final VoidCallback onAcceptDriverOrder;
  final VoidCallback onRejectDriverOrder;
  final VoidCallback onCancelDriverOrder;
  final VoidCallback onCompleteDriverOrder;
  final bool isAcceptingDriverOrder;
  final bool isCancellingDriverOrder;
  final bool isCompletingDriverOrder;
  final String? clientTerminalNotice;
  final String? driverTerminalNotice;
  final VoidCallback onAcknowledgeDriverTerminal;

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  bool _menuOpen = false;
  bool _clientInfoCollapsed = false;
  bool _driverInfoCollapsed = false;

  void _toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _closeMenu() => setState(() => _menuOpen = false);

  void _goTab(AppTab tab) {
    ref.read(appFlowProvider.notifier).setTab(tab);
    _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(appFlowProvider);
    final notifier = ref.read(appFlowProvider.notifier);

    final home = flow.isDriver
        ? _DriverHome(
            stage: flow.driverStage,
            infoCollapsed: _driverInfoCollapsed,
            fromAddress: widget.fromAddress,
            toAddress: widget.toAddress,
            vehicleType: widget.vehicleType,
            lockedWheels: widget.lockedWheels,
            running: widget.running,
            selectedTariff: widget.selectedTariff,
            tariffPrice: widget.activeTariff.price,
            comment: widget.comment.text,
            onDriverOnlineChanged: widget.onDriverOnlineChanged,
            onAcceptOrder: () {
              setState(() => _driverInfoCollapsed = true);
              widget.onAcceptDriverOrder();
            },
            onRejectOrder: widget.onRejectDriverOrder,
            onCancelActiveOrder: widget.onCancelDriverOrder,
            onCompleteActiveOrder: widget.onCompleteDriverOrder,
            isAcceptingOrder: widget.isAcceptingDriverOrder,
            isCancellingOrder: widget.isCancellingDriverOrder,
            isCompletingOrder: widget.isCompletingDriverOrder,
            terminalNotice: widget.driverTerminalNotice,
            onAcknowledgeTerminal: widget.onAcknowledgeDriverTerminal,
            onToggleInfo: () =>
                setState(() => _driverInfoCollapsed = !_driverInfoCollapsed),
          )
        : _ClientHome(
            stage: flow.clientStage,
            infoCollapsed: _clientInfoCollapsed,
            fromAddress: widget.fromAddress,
            toAddress: widget.toAddress,
            pickFrom: widget.pickFrom,
            addressSearch: widget.addressSearch,
            comment: widget.comment,
            vehicleType: widget.vehicleType,
            lockedWheels: widget.lockedWheels,
            running: widget.running,
            selectedTariff: widget.selectedTariff,
            suggestions: widget.suggestions,
            vehicleTypes: widget.vehicleTypes,
            tariffs: widget.tariffs,
            activeTariff: widget.activeTariff,
            onStartAddress: notifier.showAddressSelection,
            onConfirmAddress: notifier.confirmAddress,
            onPickField: widget.onPickField,
            onPickSuggestion: widget.onPickSuggestion,
            onVehicleType: widget.onVehicleType,
            onLockedWheels: widget.onLockedWheels,
            onRunning: widget.onRunning,
            onTariff: widget.onTariff,
            onReview: () =>
                notifier.setClientStage(ClientHomeStage.orderReview),
            onSubmitOrder: widget.onSubmitOrder,
            onRetry: notifier.retrySearch,
            onCancelOrder: widget.onCancelClientOrder,
            onReset: widget.onReset,
            terminalNotice: widget.clientTerminalNotice,
            onToggleInfo: () =>
                setState(() => _clientInfoCollapsed = !_clientInfoCollapsed),
          );

    final body = switch (flow.currentTab) {
      AppTab.home => home,
      AppTab.history => const _HistoryScreen(),
      AppTab.profile => _ProfileScreen(isDriver: flow.isDriver),
    };

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 8,
            left: 8,
            child: _GlassSurface(
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(12),
              blurSigma: 12,
              tint: Colors.white.withValues(alpha: 0.56),
              child: IconButton(
                onPressed: _toggleMenu,
                icon: const Icon(Icons.menu, color: EvikColors.textPrimaryDark),
                tooltip: '\u041c\u0435\u043d\u044e',
              ),
            ),
          ),
          if (_menuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeMenu,
                child: Container(color: Colors.black.withValues(alpha: 0.38)),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _GlassSurface(
                width: MediaQuery.of(context).size.width * 0.5,
                height: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 28, 12, 16),
                blurSigma: 16,
                tint: Colors.white.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(0),
                border: const Border(
                  right: BorderSide(color: EvikColors.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (flow.isDriver) ...[
                          const CircleAvatar(
                            radius: 22,
                            backgroundColor: EvikColors.surfaceLight,
                            child: Icon(Icons.person,
                                color: EvikColors.textPrimaryLight),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  flow.isDriver
                                      ? '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u0432\u043e\u0434\u0438\u0442\u0435\u043b\u044f'
                                      : '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u043a\u043b\u0438\u0435\u043d\u0442\u0430',
                                  style: _UiText.body
                                      .copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              const Text(
                                  '\u0424\u043e\u0442\u043e \u0431\u0443\u0434\u0435\u0442 \u0438\u0437 \u0434\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u043e\u0432',
                                  style: _UiText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DrawerItem(
                        label: '\u0413\u043b\u0430\u0432\u043d\u0430\u044f',
                        icon: Icons.home_outlined,
                        onTap: () => _goTab(AppTab.home)),
                    const SizedBox(height: 8),
                    _DrawerItem(
                        label: '\u041f\u0440\u043e\u0444\u0438\u043b\u044c',
                        icon: Icons.person_outline,
                        onTap: () => _goTab(AppTab.profile)),
                    const SizedBox(height: 8),
                    _DrawerItem(
                        label: '\u0418\u0441\u0442\u043e\u0440\u0438\u044f',
                        icon: Icons.history,
                        onTap: () => _goTab(AppTab.history)),
                    const SizedBox(height: 8),
                    _DrawerItem(
                      label:
                          '\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438',
                      icon: Icons.settings_outlined,
                      onTap: () {
                        _closeMenu();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                '\u0420\u0430\u0437\u0434\u0435\u043b \u00ab\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438\u00bb \u0432 \u0440\u0430\u0437\u0440\u0430\u0431\u043e\u0442\u043a\u0435')));
                      },
                    ),
                    const SizedBox(height: 8),
                    _DrawerItem(
                      label:
                          '\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430',
                      icon: Icons.support_agent_outlined,
                      onTap: () {
                        _closeMenu();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                '\u0420\u0430\u0437\u0434\u0435\u043b \u00ab\u041f\u043e\u0434\u0434\u0435\u0440\u0436\u043a\u0430\u00bb \u0432 \u0440\u0430\u0437\u0440\u0430\u0431\u043e\u0442\u043a\u0435')));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem(
      {required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: EvikColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EvikColors.borderDark),
        ),
        child: Row(
          children: [
            Icon(icon, color: EvikColors.textPrimaryDark, size: 20),
            const SizedBox(width: 10),
            Text(label, style: _UiText.body),
          ],
        ),
      ),
    );
  }
}

class _RoleScreen extends ConsumerWidget {
  const _RoleScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(appFlowProvider);
    final notifier = ref.read(appFlowProvider.notifier);

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              SizedBox(
                height: 330,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: -240,
                      left: -28,
                      right: -28,
                      child: Container(
                        height: 520,
                        decoration: BoxDecoration(
                          color: EvikColors.accent.withValues(alpha: 0.98),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 34,
                      child: Image.asset(
                        'assets/img/roleevik.png',
                        width: 320,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                  '\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0440\u043e\u043b\u044c',
                  textAlign: TextAlign.center,
                  style: _UiText.h1),
              const SizedBox(height: 8),
              const Text(
                '\u041c\u044b \u043d\u0430\u0441\u0442\u0440\u043e\u0438\u043c \u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441 \u043f\u043e\u0434 \u0432\u0430\u0448 \u0441\u0446\u0435\u043d\u0430\u0440\u0438\u0439.',
                textAlign: TextAlign.center,
                style: _UiText.caption,
              ),
              const SizedBox(height: 16),
              _RoleCard(
                title: '\u041a\u043b\u0438\u0435\u043d\u0442',
                subtitle:
                    '\u0412\u044b\u0437\u0432\u0430\u0442\u044c \u044d\u0432\u0430\u043a\u0443\u0430\u0442\u043e\u0440',
                selected: flow.role == UserRole.client,
                onTap: () => notifier.selectRole(UserRole.client),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                title: '\u0412\u043e\u0434\u0438\u0442\u0435\u043b\u044c',
                subtitle:
                    '\u041f\u0440\u0438\u043d\u0438\u043c\u0430\u0442\u044c \u0437\u0430\u043a\u0430\u0437\u044b',
                selected: flow.role == UserRole.driver,
                onTap: () => notifier.selectRole(UserRole.driver),
              ),
              const SizedBox(height: 24),
              _ActionButton.primary(
                text:
                    '\u041f\u0440\u043e\u0434\u043e\u043b\u0436\u0438\u0442\u044c',
                enabled: flow.role != null,
                onTap: notifier.continueFromRole,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneScreen extends ConsumerWidget {
  const _PhoneScreen({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => ref.read(appFlowProvider.notifier).logout(),
            icon:
                const Icon(Icons.arrow_back, color: EvikColors.textPrimaryDark),
          ),
          const Spacer(flex: 2),
          const Text(
              '\u0412\u0445\u043e\u0434 \u043f\u043e \u043d\u043e\u043c\u0435\u0440\u0443 \u0442\u0435\u043b\u0435\u0444\u043e\u043d\u0430',
              style: _UiText.h1),
          const SizedBox(height: 8),
          const Text(
              '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043d\u043e\u043c\u0435\u0440, \u043c\u044b \u043e\u0442\u043f\u0440\u0430\u0432\u0438\u043c \u043a\u043e\u0434 \u043f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434\u0435\u043d\u0438\u044f.',
              style: _UiText.caption),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            style: _UiText.body,
            decoration: const InputDecoration(hintText: '+7 (___) ___-__-__'),
          ),
          const Spacer(flex: 3),
          _ActionButton.primary(
            text:
                '\u041f\u043e\u043b\u0443\u0447\u0438\u0442\u044c \u043a\u043e\u0434',
            onTap: () =>
                ref.read(appFlowProvider.notifier).submitPhone(controller.text),
          ),
        ],
      ),
    );
  }
}

class _OtpScreen extends ConsumerStatefulWidget {
  const _OtpScreen({required this.controller});
  final TextEditingController controller;

  @override
  ConsumerState<_OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<_OtpScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(4, (_) => TextEditingController());
    _focusNodes = List.generate(4, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      final chars = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < 4; i++) {
        _controllers[i].text = i < chars.length ? chars[i] : '';
      }
      if (chars.length >= 4) {
        _focusNodes[3].unfocus();
      } else {
        _focusNodes[chars.length].requestFocus();
      }
      setState(() {});
      return;
    }

    if (value.isNotEmpty && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  void _onBackspace(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return;
    }
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      setState(() {});
    }
  }

  String get _code => _controllers.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(appFlowProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => ref.read(appFlowProvider.notifier).logout(),
            icon:
                const Icon(Icons.arrow_back, color: EvikColors.textPrimaryDark),
          ),
          const Spacer(flex: 2),
          const Text(
              '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043a\u043e\u0434 \u0438\u0437 SMS',
              style: _UiText.h1),
          const SizedBox(height: 8),
          Text(
            '\u041a\u043e\u0434 \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d \u043d\u0430 ${flow.phone.isEmpty ? '+7 (999) 123-45-67' : flow.phone}',
            style: _UiText.caption,
          ),
          const SizedBox(height: 24),
          Row(
            children: List.generate(4, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 3 ? 0 : 12),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      _onBackspace(index, event);
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: _UiText.h2,
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: EvikColors.surfaceDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: _focusNodes[index].hasFocus
                                  ? EvikColors.borderLight
                                  : EvikColors.borderDark),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: _focusNodes[index].hasFocus
                                  ? EvikColors.borderLight
                                  : EvikColors.borderDark),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: EvikColors.borderLight),
                        ),
                      ),
                      onChanged: (value) => _onChanged(index, value),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () =>
                  ref.read(appFlowProvider.notifier).backToPhoneEntry(),
              child: const Text(
                '\u0418\u0437\u043c\u0435\u043d\u0438\u0442\u044c \u043d\u043e\u043c\u0435\u0440 \u0442\u0435\u043b\u0435\u0444\u043e\u043d\u0430',
                style: TextStyle(color: EvikColors.textPrimaryDark),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                ref.read(appFlowProvider.notifier).submitPhone(
                      flow.phone.isEmpty ? '+7 (999) 123-45-67' : flow.phone,
                    );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '\u041a\u043e\u0434 \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d \u043f\u043e\u0432\u0442\u043e\u0440\u043d\u043e',
                    ),
                  ),
                );
              },
              child: const Text(
                '\u041d\u0435 \u043f\u0440\u0438\u0448\u0451\u043b \u043a\u043e\u0434? \u041e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c \u0441\u043d\u043e\u0432\u0430',
                style: TextStyle(color: EvikColors.textPrimaryDark),
              ),
            ),
          ),
          const Spacer(flex: 3),
          _ActionButton.primary(
            text:
                '\u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u044c',
            enabled: _code.length == 4,
            onTap: () => ref.read(appFlowProvider.notifier).submitSms(_code),
          ),
        ],
      ),
    );
  }
}

class _SuccessScreen extends ConsumerWidget {
  const _SuccessScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 50, 24, 20),
      child: Column(
        children: [
          const Spacer(),
          const Icon(Icons.check_circle_outline,
              color: EvikColors.textPrimaryDark, size: 88),
          const SizedBox(height: 12),
          const Text('Вход выполнен',
              style: TextStyle(
                color: EvikColors.textPrimaryDark,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              )),
          const Spacer(),
          _ActionButton.primary(
            text: 'Перейти к карте',
            onTap: () => ref.read(appFlowProvider.notifier).finishAuth(),
          ),
        ],
      ),
    );
  }
}

class _ClientHome extends StatelessWidget {
  const _ClientHome({
    required this.stage,
    required this.infoCollapsed,
    required this.fromAddress,
    required this.toAddress,
    required this.pickFrom,
    required this.addressSearch,
    required this.comment,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.selectedTariff,
    required this.suggestions,
    required this.vehicleTypes,
    required this.tariffs,
    required this.activeTariff,
    required this.onStartAddress,
    required this.onConfirmAddress,
    required this.onPickField,
    required this.onPickSuggestion,
    required this.onVehicleType,
    required this.onLockedWheels,
    required this.onRunning,
    required this.onTariff,
    required this.onReview,
    required this.onSubmitOrder,
    required this.onRetry,
    required this.onCancelOrder,
    required this.onReset,
    required this.terminalNotice,
    required this.onToggleInfo,
  });

  final ClientHomeStage stage;
  final bool infoCollapsed;
  final String fromAddress;
  final String? toAddress;
  final bool pickFrom;
  final TextEditingController addressSearch;
  final TextEditingController comment;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final String selectedTariff;
  final List<String> suggestions;
  final List<String> vehicleTypes;
  final List<_Tariff> tariffs;
  final _Tariff activeTariff;
  final VoidCallback onStartAddress;
  final VoidCallback onConfirmAddress;
  final ValueChanged<bool> onPickField;
  final ValueChanged<String> onPickSuggestion;
  final ValueChanged<String> onVehicleType;
  final ValueChanged<int> onLockedWheels;
  final ValueChanged<bool> onRunning;
  final ValueChanged<String> onTariff;
  final VoidCallback onReview;
  final VoidCallback onSubmitOrder;
  final VoidCallback onRetry;
  final VoidCallback onCancelOrder;
  final VoidCallback onReset;
  final String? terminalNotice;
  final VoidCallback onToggleInfo;

  @override
  Widget build(BuildContext context) {
    final compactOverlay = infoCollapsed &&
        (stage == ClientHomeStage.driverFound ||
            stage == ClientHomeStage.driverEnRoute ||
            stage == ClientHomeStage.driverArrived);
    final maxHeightFactor = switch (stage) {
      ClientHomeStage.idle => 0.36,
      ClientHomeStage.searching => 0.42,
      ClientHomeStage.noDrivers => 0.46,
      ClientHomeStage.addressSelection => 0.88,
      ClientHomeStage.orderParameters => 0.86,
      ClientHomeStage.orderReview => 0.84,
      ClientHomeStage.driverFound ||
      ClientHomeStage.driverEnRoute ||
      ClientHomeStage.driverArrived =>
        compactOverlay ? 0.24 : 0.72,
      ClientHomeStage.completed => 0.44,
    };
    final overlay = switch (stage) {
      ClientHomeStage.idle => _Panel(
          child: _ActionButton.primary(
              text: 'Вызвать эвакуатор', onTap: onStartAddress),
        ),
      ClientHomeStage.addressSelection => _AddressPanel(
          fromAddress: fromAddress,
          toAddress: toAddress,
          pickFrom: pickFrom,
          addressSearch: addressSearch,
          suggestions: suggestions,
          onPickField: onPickField,
          onPickSuggestion: onPickSuggestion,
          onConfirmAddress: onConfirmAddress,
        ),
      ClientHomeStage.orderParameters => _OrderParamsPanel(
          vehicleType: vehicleType,
          lockedWheels: lockedWheels,
          running: running,
          comment: comment,
          selectedTariff: selectedTariff,
          vehicleTypes: vehicleTypes,
          tariffs: tariffs,
          onVehicleType: onVehicleType,
          onLockedWheels: onLockedWheels,
          onRunning: onRunning,
          onTariff: onTariff,
          onReview: onReview,
        ),
      ClientHomeStage.orderReview => _ReviewPanel(
          fromAddress: fromAddress,
          toAddress: toAddress ?? 'Не выбран адрес',
          vehicleType: vehicleType,
          lockedWheels: lockedWheels,
          running: running,
          tariff: activeTariff,
          onSubmit: onSubmitOrder,
        ),
      ClientHomeStage.searching => _SearchingPanel(onCancel: onCancelOrder),
      ClientHomeStage.noDrivers => _Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Нет доступных водителей',
                  style: TextStyle(
                      color: EvikColors.textPrimaryDark,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _ActionButton.primary(text: 'Повторить поиск', onTap: onRetry),
              const SizedBox(height: 8),
              _ActionButton.cancel(text: 'Отмена', onTap: onCancelOrder),
            ],
          ),
        ),
      ClientHomeStage.driverFound ||
      ClientHomeStage.driverEnRoute ||
      ClientHomeStage.driverArrived =>
        infoCollapsed
            ? _MapInfoButton(
                text: 'Показать водителя',
                icon: Icons.keyboard_arrow_up_rounded,
                onTap: onToggleInfo,
              )
            : _DriverFoundPanel(
                onCancel: onCancelOrder,
                onCollapse: onToggleInfo,
              ),
      ClientHomeStage.completed => _StatusPanel(
          title: terminalNotice == null ? 'Заказ завершён' : 'Заказ отменён',
          subtitle: terminalNotice ?? 'Спасибо, что выбрали EVIK.',
          primaryText: 'Новый заказ',
          onPrimary: onReset,
        ),
    };

    return Stack(
      children: [
        const Positioned.fill(child: _MapLayer()),
        Positioned.fill(
          child: _BottomOverlaySlot(
            compact: compactOverlay,
            maxHeightFactor: maxHeightFactor,
            child: overlay,
          ),
        ),
      ],
    );
  }
}

class _AddressPanel extends StatelessWidget {
  const _AddressPanel({
    required this.fromAddress,
    required this.toAddress,
    required this.pickFrom,
    required this.addressSearch,
    required this.suggestions,
    required this.onPickField,
    required this.onPickSuggestion,
    required this.onConfirmAddress,
  });

  final String fromAddress;
  final String? toAddress;
  final bool pickFrom;
  final TextEditingController addressSearch;
  final List<String> suggestions;
  final ValueChanged<bool> onPickField;
  final ValueChanged<String> onPickSuggestion;
  final VoidCallback onConfirmAddress;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Выбор адреса',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
              controller: addressSearch,
              style: const TextStyle(color: EvikColors.textPrimaryDark),
              decoration: const InputDecoration(hintText: 'Поиск адреса')),
          const SizedBox(height: 12),
          _AddressItem(
              title: 'Откуда',
              value: fromAddress,
              selected: pickFrom,
              priority: false,
              onTap: () => onPickField(true)),
          const SizedBox(height: 8),
          _AddressItem(
              title: 'Куда',
              value: toAddress ?? 'Укажите адрес назначения',
              selected: !pickFrom,
              priority: true,
              onTap: () => onPickField(false)),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: ListView.separated(
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => InkWell(
                onTap: () => onPickSuggestion(suggestions[i]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                      color: EvikColors.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: EvikColors.borderDark)),
                  child: Text(suggestions[i],
                      style:
                          const TextStyle(color: EvikColors.textPrimaryDark)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _ActionButton.primary(
            text: 'Подтвердить адрес',
            enabled: toAddress != null && toAddress!.trim().isNotEmpty,
            onTap: onConfirmAddress,
          ),
        ],
      ),
    );
  }
}

class _OrderParamsPanel extends StatelessWidget {
  const _OrderParamsPanel({
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.comment,
    required this.selectedTariff,
    required this.vehicleTypes,
    required this.tariffs,
    required this.onVehicleType,
    required this.onLockedWheels,
    required this.onRunning,
    required this.onTariff,
    required this.onReview,
  });

  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final TextEditingController comment;
  final String selectedTariff;
  final List<String> vehicleTypes;
  final List<_Tariff> tariffs;
  final ValueChanged<String> onVehicleType;
  final ValueChanged<int> onLockedWheels;
  final ValueChanged<bool> onRunning;
  final ValueChanged<String> onTariff;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Параметры заказа',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: vehicleTypes
                .map(
                  (t) => _VehicleTypeChip(
                    label: t,
                    selected: t == vehicleType,
                    onTap: () => onVehicleType(t),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: EvikColors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EvikColors.borderDark)),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('Заблокированные колёса',
                            style:
                                TextStyle(color: EvikColors.textPrimaryDark))),
                    IconButton(
                        onPressed: () => onLockedWheels(lockedWheels - 1),
                        icon: const Icon(Icons.remove,
                            color: EvikColors.textPrimaryDark)),
                    Text('$lockedWheels',
                        style: const TextStyle(
                            color: EvikColors.textPrimaryDark,
                            fontWeight: FontWeight.w700)),
                    IconButton(
                        onPressed: () => onLockedWheels(lockedWheels + 1),
                        icon: const Icon(Icons.add,
                            color: EvikColors.textPrimaryDark)),
                  ],
                ),
                Row(
                  children: [
                    const Expanded(
                        child: Text('Автомобиль на ходу',
                            style:
                                TextStyle(color: EvikColors.textPrimaryDark))),
                    Switch(value: running, onChanged: onRunning),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
              controller: comment,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(color: EvikColors.textPrimaryDark),
              decoration: const InputDecoration(
                  hintText: 'Комментарий к заказу (необязательно)')),
          const SizedBox(height: 10),
          ...tariffs.map((t) => GestureDetector(
                onTap: () => onTariff(t.name),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedTariff == t.name
                        ? EvikColors.accent
                        : EvikColors.surfaceDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selectedTariff == t.name
                            ? EvikColors.borderLight
                            : EvikColors.borderDark),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(t.name,
                              style: TextStyle(
                                  color: selectedTariff == t.name
                                      ? EvikColors.textPrimaryLight
                                      : EvikColors.textPrimaryDark,
                                  fontWeight: FontWeight.w700))),
                      Text('${t.price} ₽ • ${t.eta}',
                          style: TextStyle(
                              color: selectedTariff == t.name
                                  ? EvikColors.textPrimaryLight
                                  : EvikColors.textSecondaryDark)),
                    ],
                  ),
                ),
              )),
          _ActionButton.primary(text: 'Продолжить', onTap: onReview),
        ],
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.fromAddress,
    required this.toAddress,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.tariff,
    required this.onSubmit,
  });

  final String fromAddress;
  final String toAddress;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final _Tariff tariff;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final estimate = _estimateOrderPrice(
      tariffName: tariff.name,
      basePrice: tariff.price,
      vehicleType: vehicleType,
      lockedWheels: lockedWheels,
      running: running,
    );

    Widget pair(String left, String right) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(
                width: 110,
                child: Text(left,
                    style:
                        const TextStyle(color: EvikColors.textSecondaryDark))),
            Expanded(
                child: Text(right,
                    style: const TextStyle(
                        color: EvikColors.textPrimaryDark,
                        fontWeight: FontWeight.w600))),
          ]),
        );

    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Подтверждение заказа',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          pair('Откуда', fromAddress),
          pair('Куда', toAddress),
          pair('Авто', vehicleType),
          pair('Колёса', '$lockedWheels'),
          pair('На ходу', running ? 'Да' : 'Нет'),
          pair('\u0422\u0430\u0440\u0438\u0444',
              '${tariff.name}, ${tariff.price} \u20bd'),
          pair('\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c',
              '${estimate.totalPrice} \u20bd'),
          const SizedBox(height: 4),
          Text(
            '\u041f\u0440\u0435\u0434\u0432\u0430\u0440\u0438\u0442\u0435\u043b\u044c\u043d\u0430\u044f \u0441\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c: ${estimate.summary}',
            style: const TextStyle(
              color: EvikColors.textSecondaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          _ActionButton.primary(text: 'Вызвать эвакуатор', onTap: onSubmit),
        ],
      ),
    );
  }
}

class _SearchingPanel extends StatelessWidget {
  const _SearchingPanel({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                      EvikColors.textPrimaryDark))),
          const SizedBox(height: 12),
          const Text('Ищем эвакуатор...',
              style: TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          SizedBox(
            width: 220,
            child: _ActionButton.cancel(
              text: 'Отменить заказ',
              onTap: onCancel,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverFoundPanel extends StatelessWidget {
  const _DriverFoundPanel({required this.onCancel, required this.onCollapse});
  final VoidCallback onCancel;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Водитель найден',
            style: TextStyle(
              color: EvikColors.textPrimaryDark,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
            ),
            child: Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFF4F4F4F), Color(0xFF1C1C1C)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.72),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Алексей Смирнов',
                        style: TextStyle(
                          color: EvikColors.textPrimaryDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Эвакуатор Hyundai HD78',
                        style: TextStyle(
                          color: EvikColors.textSecondaryDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _MiniInfo(
                            icon: Icons.star_rounded,
                            text: '4.9 рейтинг',
                          ),
                          _MiniInfo(
                            icon: Icons.route_rounded,
                            text: '3.4 км до вас',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                child: _KeyInfoCard(
                  label: 'Приедет через',
                  value: '12 мин',
                  accent: Color(0xFF19E5E5),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _KeyInfoCard(
                  label: 'Номер машины',
                  value: 'Р336СВ 799',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Что происходит сейчас',
                  style: TextStyle(
                    color: EvikColors.textPrimaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Водитель уже едет к вам. Следите за временем прибытия и номером машины, дополнительных действий от клиента сейчас не требуется.',
                  style: TextStyle(
                    color: EvikColors.textSecondaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ActionButton.secondary(
            text: 'Скрыть карточку',
            onTap: onCollapse,
          ),
          const SizedBox(height: 8),
          _ActionButton.cancel(
            text: 'Отменить заказ',
            onTap: () => _showCancelWarning(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showCancelWarning(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
          title: const Text(
            'Отменить заказ?',
            style: TextStyle(
              color: EvikColors.textPrimaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'Если водитель уже проехал больше половины пути к вам, отмена может понизить рейтинг клиента.',
            style: TextStyle(
              color: EvikColors.textSecondaryDark,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Остаться'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: EvikColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Да, отменить'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      onCancel();
    }
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: EvikColors.textSecondaryDark),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: EvikColors.textSecondaryDark,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _KeyInfoCard extends StatelessWidget {
  const _KeyInfoCard({
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final background = accent != null
        ? accent!.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.72);
    final borderColor = accent != null
        ? accent!.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.52);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: EvikColors.textSecondaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: EvikColors.textPrimaryDark,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.title,
    required this.subtitle,
    required this.primaryText,
    required this.onPrimary,
  });

  final String title;
  final String subtitle;
  final String primaryText;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: EvikColors.textSecondaryDark)),
          const SizedBox(height: 12),
          _ActionButton.primary(text: primaryText, onTap: onPrimary),
        ],
      ),
    );
  }
}

class _DriverHome extends ConsumerWidget {
  static const MethodChannel _systemChannel = MethodChannel('evik/system');

  const _DriverHome({
    required this.stage,
    required this.infoCollapsed,
    required this.fromAddress,
    required this.toAddress,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.selectedTariff,
    required this.tariffPrice,
    required this.comment,
    required this.onDriverOnlineChanged,
    required this.onAcceptOrder,
    required this.onRejectOrder,
    required this.onCancelActiveOrder,
    required this.onCompleteActiveOrder,
    required this.isAcceptingOrder,
    required this.isCancellingOrder,
    required this.isCompletingOrder,
    required this.terminalNotice,
    required this.onAcknowledgeTerminal,
    required this.onToggleInfo,
  });

  final DriverHomeStage stage;
  final bool infoCollapsed;
  final String fromAddress;
  final String? toAddress;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final String selectedTariff;
  final int tariffPrice;
  final String comment;
  final ValueChanged<bool> onDriverOnlineChanged;
  final VoidCallback onAcceptOrder;
  final VoidCallback onRejectOrder;
  final VoidCallback onCancelActiveOrder;
  final VoidCallback onCompleteActiveOrder;
  final bool isAcceptingOrder;
  final bool isCancellingOrder;
  final bool isCompletingOrder;
  final String? terminalNotice;
  final VoidCallback onAcknowledgeTerminal;
  final VoidCallback onToggleInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeSnapshot = ref.watch(driverRouteSnapshotProvider);
    final online = stage != DriverHomeStage.offline;
    final hasActiveOrder = stage == DriverHomeStage.accepted ||
        stage == DriverHomeStage.enRoute ||
        stage == DriverHomeStage.arrived;
    final compactOverlay = hasActiveOrder && infoCollapsed;
    final maxHeightFactor = switch (stage) {
      DriverHomeStage.offline => 0.42,
      DriverHomeStage.online => 0.56,
      DriverHomeStage.newOrder => 0.86,
      DriverHomeStage.accepted ||
      DriverHomeStage.enRoute ||
      DriverHomeStage.arrived =>
        compactOverlay ? 0.26 : 0.84,
      DriverHomeStage.completed => 0.5,
    };

    return Stack(
      children: [
        const Positioned.fill(child: _MapLayer()),
        Positioned.fill(
          child: _BottomOverlaySlot(
            compact: compactOverlay,
            maxHeightFactor: maxHeightFactor,
            child: compactOverlay
                ? _DriverCompactOrderBar(
                    text: 'Показать заказ',
                    routeSnapshot: routeSnapshot,
                    onExpand: onToggleInfo,
                    onCall: () =>
                        unawaited(_callClient(context, _demoClientPhone)),
                  )
                : _Panel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.46),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: online
                                  ? const Color(0xFF11D8CC)
                                      .withValues(alpha: 0.38)
                                  : Colors.white.withValues(alpha: 0.58),
                            ),
                          ),
                          child: Row(children: [
                            const Expanded(
                                child: Text('Статус водителя',
                                    style: TextStyle(
                                        color: EvikColors.textPrimaryDark,
                                        fontWeight: FontWeight.w700))),
                            _DriverShiftInlineToggle(
                              online: online,
                              onChanged: onDriverOnlineChanged,
                            ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _DriverShiftBadge(online: online),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          online
                              ? 'Вы принимаете новые заказы и видны клиентам поблизости.'
                              : 'Включите смену, чтобы начать получать новые заказы.',
                          style: const TextStyle(
                            color: EvikColors.textSecondaryDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (stage == DriverHomeStage.newOrder) ...[
                          _DriverOrderCard(
                            title: 'Новый заказ',
                            subtitle:
                                'Проверьте маршрут и все параметры, которые указал клиент.',
                            fromAddress: fromAddress,
                            toAddress: toAddress,
                            vehicleType: vehicleType,
                            lockedWheels: lockedWheels,
                            running: running,
                            selectedTariff: selectedTariff,
                            tariffPrice: tariffPrice,
                            comment: comment,
                          ),
                          const SizedBox(height: 12),
                          _ActionButton.primary(
                            text: isAcceptingOrder
                                ? 'Принимаем...'
                                : 'Принять заказ',
                            onTap: onAcceptOrder,
                            enabled: !(isAcceptingOrder ||
                                isCancellingOrder ||
                                isCompletingOrder),
                          ),
                          const SizedBox(height: 8),
                          _ActionButton.cancel(
                            text: 'Отклонить',
                            onTap: onRejectOrder,
                            enabled: !(isAcceptingOrder ||
                                isCancellingOrder ||
                                isCompletingOrder),
                          ),
                        ],
                        if (stage == DriverHomeStage.accepted ||
                            stage == DriverHomeStage.enRoute ||
                            stage == DriverHomeStage.arrived) ...[
                          _DriverOrderCard(
                            title: 'Активный заказ',
                            subtitle:
                                'Маршрут уже построен. Следуйте по карте до клиента.',
                            onCollapse: onToggleInfo,
                            fromAddress: fromAddress,
                            toAddress: toAddress,
                            vehicleType: vehicleType,
                            lockedWheels: lockedWheels,
                            running: running,
                            selectedTariff: selectedTariff,
                            tariffPrice: tariffPrice,
                            comment: comment,
                          ),
                          const SizedBox(height: 12),
                          _ActionButton.cancel(
                            text: isCancellingOrder
                                ? 'Отменяем...'
                                : 'Отменить заказ',
                            onTap: onCancelActiveOrder,
                            enabled: !(isAcceptingOrder ||
                                isCancellingOrder ||
                                isCompletingOrder),
                          ),
                          const SizedBox(height: 8),
                          _ActionButton.primary(
                            text: isCompletingOrder
                                ? 'Завершаем...'
                                : 'Завершить заказ',
                            onTap: onCompleteActiveOrder,
                            enabled: !(isAcceptingOrder ||
                                isCancellingOrder ||
                                isCompletingOrder),
                          ),
                        ],
                        if (stage == DriverHomeStage.completed) ...[
                          _DriverDoneCard(
                            title: terminalNotice == null
                                ? 'Заказ завершён'
                                : 'Заказ отменён',
                            subtitle: terminalNotice ??
                                'Поездка завершена. Можно вернуться в онлайн и ждать следующий заказ.',
                          ),
                          const SizedBox(height: 12),
                          _ActionButton.primary(
                            text: 'К новым заказам',
                            onTap: onAcknowledgeTerminal,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _callClient(BuildContext context, String phone) async {
    try {
      await _systemChannel.invokeMethod<void>(
        'dial',
        <String, dynamic>{'phone': phone},
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть звонок')),
      );
    }
  }
}

class _DriverOrderCard extends StatelessWidget {
  const _DriverOrderCard({
    required this.title,
    required this.subtitle,
    this.onCollapse,
    required this.fromAddress,
    required this.toAddress,
    required this.vehicleType,
    required this.lockedWheels,
    required this.running,
    required this.selectedTariff,
    required this.tariffPrice,
    required this.comment,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onCollapse;
  final String fromAddress;
  final String? toAddress;
  final String vehicleType;
  final int lockedWheels;
  final bool running;
  final String selectedTariff;
  final int tariffPrice;
  final String comment;

  @override
  Widget build(BuildContext context) {
    final destination = (toAddress == null || toAddress!.isEmpty)
        ? 'Адрес клиента уточняется'
        : toAddress!;
    final note = comment.trim().isEmpty ? 'Без комментария' : comment.trim();
    final estimate = _estimateOrderPrice(
      tariffName: selectedTariff,
      basePrice: tariffPrice,
      vehicleType: vehicleType,
      lockedWheels: lockedWheels,
      running: running,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: EvikColors.textPrimaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onCollapse != null)
                _IconGlassButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  tooltip: 'Скрыть',
                  onTap: onCollapse!,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: EvikColors.textSecondaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _DriverRouteRow(
            icon: Icons.trip_origin_rounded,
            label: 'Откуда',
            value: fromAddress,
          ),
          const SizedBox(height: 10),
          _DriverRouteRow(
            icon: Icons.flag_rounded,
            label: 'Куда',
            value: destination,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DriverInfoChip(label: 'Авто', value: vehicleType),
              _DriverInfoChip(
                label: 'Колёса',
                value: lockedWheels == 0 ? 'Нет блокировки' : '$lockedWheels',
              ),
              _DriverInfoChip(
                label: 'Состояние',
                value: running ? 'На ходу' : 'Не на ходу',
              ),
              _DriverInfoChip(label: 'Тариф', value: selectedTariff),
              _DriverInfoChip(
                label: '\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c',
                value: '${estimate.totalPrice} \u20bd',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Комментарий клиента',
                  style: TextStyle(
                    color: EvikColors.textSecondaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  note,
                  style: const TextStyle(
                    color: EvikColors.textPrimaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
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

class _DriverRouteRow extends StatelessWidget {
  const _DriverRouteRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: EvikColors.textPrimaryDark),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: EvikColors.textSecondaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: EvikColors.textPrimaryDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverInfoChip extends StatelessWidget {
  const _DriverInfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: EvikColors.textPrimaryDark,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: EvikColors.textSecondaryDark),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _DriverDoneCard extends StatelessWidget {
  const _DriverDoneCard({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: EvikColors.textPrimaryDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: EvikColors.textSecondaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverShiftInlineToggle extends StatelessWidget {
  const _DriverShiftInlineToggle({
    required this.online,
    required this.onChanged,
  });

  final bool online;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent =
        online ? const Color(0xFF11D8CC) : EvikColors.textSecondaryDark;

    return GestureDetector(
      onTap: () => onChanged(!online),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 62,
        height: 34,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: online ? accent : Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: online
                ? accent.withValues(alpha: 0.24)
                : Colors.black.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: online ? 0.12 : 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: online ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  online ? Icons.check_rounded : Icons.close_rounded,
                  size: 16,
                  color: online
                      ? const Color(0xFF11D8CC)
                      : EvikColors.textSecondaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverShiftBadge extends StatelessWidget {
  const _DriverShiftBadge({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final accent =
        online ? const Color(0xFF11D8CC) : EvikColors.textSecondaryDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            online ? 'На смене' : 'Оффлайн',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryScreen extends StatelessWidget {
  const _HistoryScreen();
  @override
  Widget build(BuildContext context) => const Center(
      child: Text('История заказов',
          style: TextStyle(color: EvikColors.textPrimaryDark)));
}

class _ProfileScreen extends ConsumerWidget {
  const _ProfileScreen({required this.isDriver});
  final bool isDriver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(appFlowProvider);
    final notifier = ref.read(appFlowProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 56),
          const Text(
            '\u041f\u0440\u043e\u0444\u0438\u043b\u044c',
            textAlign: TextAlign.center,
            style: _UiText.h1,
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EvikColors.surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: EvikColors.borderDark),
            ),
            child: isDriver
                ? const Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: EvikColors.surfaceLight,
                        child: Icon(Icons.person,
                            color: EvikColors.textPrimaryLight),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '\u0418\u0432\u0430\u043d \u0418\u0432\u0430\u043d\u043e\u0432',
                                style: _UiText.h2),
                            SizedBox(height: 4),
                            Text(
                                '\u0420\u0435\u0439\u0442\u0438\u043d\u0433: 4.9',
                                style: _UiText.caption),
                          ],
                        ),
                      ),
                    ],
                  )
                : const Text(
                    '\u0418\u0432\u0430\u043d \u0418\u0432\u0430\u043d\u043e\u0432',
                    style: _UiText.h2),
          ),
          if (isDriver) ...[
            const SizedBox(height: 16),
            ...flow.documents.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DocRow(
                    name: e.key,
                    status: e.value,
                    onTap: () {
                      final next = switch (e.value) {
                        DocumentStatus.missing => DocumentStatus.pending,
                        DocumentStatus.pending => DocumentStatus.approved,
                        DocumentStatus.approved => DocumentStatus.rejected,
                        DocumentStatus.rejected => DocumentStatus.missing,
                      };
                      notifier.updateDocumentStatus(e.key, next);
                    },
                  ),
                )),
          ],
          const Spacer(),
          _ActionButton.danger(
              text:
                  '\u0412\u044b\u0439\u0442\u0438 \u0438\u0437 \u0430\u043a\u043a\u0430\u0443\u043d\u0442\u0430',
              onTap: notifier.logout),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow(
      {required this.name, required this.status, required this.onTap});
  final String name;
  final DocumentStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      DocumentStatus.missing => 'Не загружено',
      DocumentStatus.pending => 'На проверке',
      DocumentStatus.approved => 'Подтверждено',
      DocumentStatus.rejected => 'Отклонено',
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
            color: EvikColors.surfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EvikColors.borderDark)),
        child: Row(children: [
          Expanded(
              child: Text(name,
                  style: const TextStyle(color: EvikColors.textPrimaryDark))),
          Text(text,
              style: const TextStyle(color: EvikColors.textSecondaryDark)),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 20),
      blurSigma: 16,
      tint: Colors.white.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(16),
      child: child,
    );
  }
}

class _BottomOverlaySlot extends StatelessWidget {
  const _BottomOverlaySlot({
    required this.child,
    required this.maxHeightFactor,
    this.compact = false,
  });

  final Widget child;
  final double maxHeightFactor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, compact ? 12 : 8),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: double.infinity,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: compact
                  ? child
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _BottomSheetGrabber(),
                        Flexible(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: child,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomSheetGrabber extends StatelessWidget {
  const _BottomSheetGrabber();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Center(
          child: Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.borderRadius,
    this.tint,
    this.border,
    this.blurSigma = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color? tint;
  final BoxBorder? border;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(18);

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tint ?? Colors.white.withValues(alpha: 0.62),
              borderRadius: radius,
              border: border ??
                  Border.all(color: Colors.white.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AddressItem extends StatelessWidget {
  const _AddressItem(
      {required this.title,
      required this.value,
      required this.selected,
      required this.priority,
      required this.onTap});
  final String title;
  final String value;
  final bool selected;
  final bool priority;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            EdgeInsets.symmetric(horizontal: 12, vertical: priority ? 14 : 10),
        decoration: BoxDecoration(
          color: priority ? EvikColors.surfaceLight : EvikColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? EvikColors.borderLight : EvikColors.borderDark),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: priority
                      ? EvikColors.textSecondaryLight
                      : EvikColors.textSecondaryDark,
                  fontSize: 12)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: priority
                      ? EvikColors.textPrimaryLight
                      : EvikColors.textPrimaryDark,
                  fontWeight: priority ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard(
      {required this.title,
      required this.subtitle,
      required this.selected,
      required this.onTap});
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      scale: selected ? 1.02 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: 96,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? EvikColors.surfaceLight.withValues(alpha: 0.98)
                : EvikColors.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? EvikColors.borderLight : EvikColors.borderDark,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title,
                  style: _UiText.h2.copyWith(
                      fontSize: 30 / 1.6,
                      color: selected
                          ? EvikColors.textPrimaryLight
                          : EvikColors.textPrimaryDark)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: _UiText.caption.copyWith(
                      color: selected
                          ? EvikColors.textSecondaryLight
                          : EvikColors.textSecondaryDark)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleTypeChip extends StatelessWidget {
  const _VehicleTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF19E5E5)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF10C9C9)
                  : Colors.white.withValues(alpha: 0.52),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF19E5E5).withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: EvikColors.textPrimaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton._({
    required this.text,
    required this.onTap,
    required this.bg,
    required this.fg,
    required this.border,
    this.enabled = true,
  });

  factory _ActionButton.primary(
          {required String text, VoidCallback? onTap, bool enabled = true}) =>
      _ActionButton._(
        text: text,
        onTap: onTap,
        enabled: enabled,
        bg: Colors.white,
        fg: EvikColors.textPrimaryDark,
        border: EvikColors.borderDark,
      );

  factory _ActionButton.secondary(
          {required String text, VoidCallback? onTap, bool enabled = true}) =>
      _ActionButton._(
        text: text,
        onTap: onTap,
        enabled: enabled,
        bg: EvikColors.surfaceDark,
        fg: EvikColors.textSecondaryDark,
        border: EvikColors.borderDark,
      );

  factory _ActionButton.cancel(
          {required String text, VoidCallback? onTap, bool enabled = true}) =>
      _ActionButton._(
        text: text,
        onTap: onTap,
        enabled: enabled,
        bg: EvikColors.danger.withValues(alpha: 0.16),
        fg: EvikColors.danger,
        border: EvikColors.danger.withValues(alpha: 0.45),
      );

  factory _ActionButton.danger(
          {required String text, VoidCallback? onTap, bool enabled = true}) =>
      _ActionButton.cancel(text: text, onTap: onTap, enabled: enabled);

  final String text;
  final VoidCallback? onTap;
  final bool enabled;
  final Color bg;
  final Color fg;
  final Color border;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: _pressed ? 0.97 : 1,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: widget.enabled ? widget.onTap : null,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: widget.bg,
              foregroundColor: widget.fg,
              disabledBackgroundColor: Colors.white,
              disabledForegroundColor: EvikColors.textPrimaryDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: widget.enabled ? widget.border : EvikColors.borderDark,
                ),
              ),
            ),
            child: Text(widget.text,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _IconGlassButton extends StatelessWidget {
  const _IconGlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 44,
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(icon, color: EvikColors.textPrimaryDark),
            onPressed: onTap,
          ),
        ),
      ),
    );
  }
}

class _MapInfoButton extends StatelessWidget {
  const _MapInfoButton({
    required this.text,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 22),
          label: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.white.withValues(alpha: 0.86),
            foregroundColor: EvikColors.textPrimaryDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.82)),
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverCompactOrderBar extends StatelessWidget {
  const _DriverCompactOrderBar({
    required this.text,
    required this.routeSnapshot,
    required this.onExpand,
    required this.onCall,
  });

  final String text;
  final DriverRouteSnapshot? routeSnapshot;
  final VoidCallback onExpand;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final routeText = routeSnapshot == null
        ? text
        : '${routeSnapshot!.distanceKm.toStringAsFixed(1)} км · ~${routeSnapshot!.etaMinutes} мин до клиента';

    return _GlassSurface(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      borderRadius: BorderRadius.circular(16),
      blurSigma: 12,
      tint: Colors.white.withValues(alpha: 0.72),
      border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  _demoClientPhone,
                  style: TextStyle(
                    color: EvikColors.textPrimaryDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  routeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: EvikColors.textSecondaryDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _IconGlassButton(
            icon: Icons.call_rounded,
            tooltip: 'Позвонить клиенту',
            onTap: onCall,
          ),
          const SizedBox(width: 6),
          _IconGlassButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: 'Развернуть заказ',
            onTap: onExpand,
          ),
        ],
      ),
    );
  }
}

class _MapLayer extends ConsumerStatefulWidget {
  const _MapLayer();
  @override
  ConsumerState<_MapLayer> createState() => _MapLayerState();
}

class _MapLayerState extends ConsumerState<_MapLayer> {
  bool _initialized = false;
  String _lastOverlaySignature = '';
  int _overlayRequestId = 0;
  StreamSubscription<Location>? _deviceLocationSub;
  StreamSubscription<RouteSummary?>? _routeSummarySub;
  Timer? _driverLocationPollTimer;
  Location? _deviceLocation;
  Location? _remoteDriverLocation;
  Coordinate? _driverOrderPickup;
  RouteSummary? _sdkRouteSummary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    Future.microtask(() async {
      final mapProvider = ref.read(mapProviderProvider);
      await mapProvider.init();
      _deviceLocationSub = mapProvider.onLocationChanged().listen((location) {
        _deviceLocation = location;
        if (mounted) {
          setState(() {});
        }
      });
      _routeSummarySub = mapProvider.onRouteSummaryChanged().listen((summary) {
        _sdkRouteSummary = summary;
        if (!mounted) return;
        final provider = ref.read(mapProviderProvider);
        final flow = ref.read(appFlowProvider);
        final orderUi = ref.read(orderStateNotifierProvider);
        unawaited(_syncMapOverlay(provider, flow, orderUi));
      });
      _driverLocationPollTimer =
          Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_refreshMapData());
      });
      await _refreshMapData();
    });
  }

  @override
  void dispose() {
    _deviceLocationSub?.cancel();
    _routeSummarySub?.cancel();
    _driverLocationPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(mapProviderProvider);
    final flow = ref.watch(appFlowProvider);
    final orderUi = ref.watch(orderStateNotifierProvider);
    unawaited(_syncMapOverlay(provider, flow, orderUi));

    final map = provider is YandexMapProvider && provider.isAvailable
        ? YandexMapView(
            initialLat: 55.751244,
            initialLng: 37.618423,
            initialZoom: 13,
            onMapCreated: (mapId) {
              provider.attachMap(mapId);
              final currentFlow = ref.read(appFlowProvider);
              final currentOrderUi = ref.read(orderStateNotifierProvider);
              unawaited(_syncMapOverlay(provider, currentFlow, currentOrderUi));
            })
        : const YandexMapView(
            initialLat: 55.751244, initialLng: 37.618423, initialZoom: 13);

    return map;
  }

  Future<void> _refreshMapData() async {
    if (!mounted) return;

    final flow = ref.read(appFlowProvider);
    final orderUi = ref.read(orderStateNotifierProvider);
    final clientHasActiveDriver = !flow.isDriver &&
        _isClientRouteStage(flow.clientStage) &&
        orderUi.order?.driverId != null &&
        !_isTerminalOrderState(orderUi.status);
    final driverShouldTrack =
        flow.isDriver && flow.driverStage != DriverHomeStage.offline;

    if (!clientHasActiveDriver && !driverShouldTrack) {
      if (_remoteDriverLocation != null || _driverOrderPickup != null) {
        _remoteDriverLocation = null;
        _driverOrderPickup = null;
        _sdkRouteSummary = null;
        ref.read(driverRouteSnapshotProvider.notifier).state = null;
        if (mounted) {
          setState(() {});
        }
      }
      return;
    }

    final driverDataSource = ref.read(driverRemoteDataSourceProvider);
    String? driverId;
    if (flow.isDriver) {
      driverId = _demoDriverId;
      try {
        final driver = await driverDataSource.getDriver(_demoDriverId);
        final orderId = driver.currentOrderId;
        if (orderId != null && orderId.isNotEmpty) {
          final json =
              await ref.read(apiClientProvider).get('/api/v1/orders/$orderId');
          final order = json['order'];
          if (order is Map<String, dynamic>) {
            _driverOrderPickup = Coordinate(
              lat: (order['pickup_lat'] as num).toDouble(),
              lng: (order['pickup_lng'] as num).toDouble(),
            );
          }
        } else {
          _driverOrderPickup = null;
        }
      } catch (_) {
        // Keep previous value as fallback when backend is temporarily unavailable.
      }
    } else {
      driverId = orderUi.order?.driverId;
    }

    if (driverId != null && driverId.isNotEmpty) {
      try {
        final location = await driverDataSource.getLocation(driverId);
        _remoteDriverLocation = Location(lat: location.lat, lng: location.lng);
      } catch (_) {
        // Keep previous value to avoid flickering on transient failures.
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncMapOverlay(
    MapProvider provider,
    AppFlowState flow,
    OrderUiState orderUi,
  ) async {
    final showClientRoute = !flow.isDriver &&
        _isClientRouteStage(flow.clientStage) &&
        orderUi.order?.driverId != null &&
        !_isTerminalOrderState(orderUi.status);
    final showDriverRoute =
        flow.isDriver && _driverOrderPickup != null && _driverIsActive(flow);

    final driverPoint = flow.isDriver
        ? (_deviceLocation ?? _remoteDriverLocation)
        : _remoteDriverLocation;
    final clientPickup =
        flow.isDriver ? _driverOrderPickup : orderUi.order?.pickup;
    final clientPoint = clientPickup == null
        ? null
        : Location(lat: clientPickup.lat, lng: clientPickup.lng);
    final hasRoute = (showClientRoute || showDriverRoute) &&
        driverPoint != null &&
        clientPoint != null;
    final markers = hasRoute
        ? <MapMarker>[
            MapMarker(id: 'driver', location: driverPoint, title: 'Водитель'),
            MapMarker(id: 'client', location: clientPoint, title: 'Клиент'),
          ]
        : const <MapMarker>[];
    final route = hasRoute
        ? <Location>[
            driverPoint,
            clientPoint,
          ]
        : const <Location>[];

    final signature = _buildOverlaySignature(flow, markers, route);
    if (!hasRoute) {
      _sdkRouteSummary = null;
    } else if (signature != _lastOverlaySignature) {
      _sdkRouteSummary = null;
    }
    final routeSnapshot = hasRoute
        ? _buildPreferredRouteSnapshot(driverPoint, clientPoint)
        : null;
    ref.read(driverRouteSnapshotProvider.notifier).state = routeSnapshot;
    if (signature == _lastOverlaySignature) return;
    _lastOverlaySignature = signature;
    final requestId = ++_overlayRequestId;

    if (markers.isEmpty) {
      await provider.clearMarkers();
    } else {
      await provider.setMarkers(markers);
    }
    if (!mounted || requestId != _overlayRequestId) return;
    if (route.isEmpty) {
      await provider.clearRoute();
    } else {
      await provider.setRoute(route);
    }
  }

  String _buildOverlaySignature(
      AppFlowState flow, List<MapMarker> markers, List<Location> route) {
    final markerSignature = markers
        .map((m) => '${m.id}:${m.location.lat},${m.location.lng}')
        .join('|');
    final routeSignature = route.map((p) => '${p.lat},${p.lng}').join('|');
    return '${flow.isDriver}:${flow.clientStage.name}:${flow.driverStage.name}:$markerSignature:$routeSignature';
  }

  bool _isTerminalOrderState(OrderState state) {
    return state == OrderState.completed ||
        state == OrderState.cancelled ||
        state == OrderState.noDriverFound;
  }

  bool _driverIsActive(AppFlowState flow) {
    return flow.driverStage == DriverHomeStage.accepted ||
        flow.driverStage == DriverHomeStage.enRoute ||
        flow.driverStage == DriverHomeStage.arrived;
  }

  bool _isClientRouteStage(ClientHomeStage stage) {
    return stage == ClientHomeStage.driverFound ||
        stage == ClientHomeStage.driverEnRoute ||
        stage == ClientHomeStage.driverArrived;
  }

  DriverRouteSnapshot _buildRouteSnapshot(Location from, Location to) {
    final distanceKm = _haversineDistanceKm(from, to);
    const averageCitySpeedKmh = 32.0;
    final etaMinutes = math.max(
      1,
      (distanceKm / averageCitySpeedKmh * 60).round(),
    );
    return DriverRouteSnapshot(
      distanceKm: distanceKm,
      etaMinutes: etaMinutes,
    );
  }

  double _haversineDistanceKm(Location from, Location to) {
    const earthRadiusKm = 6371.0;
    final lat1 = _toRadians(from.lat);
    final lat2 = _toRadians(to.lat);
    final dLat = _toRadians(to.lat - from.lat);
    final dLng = _toRadians(to.lng - from.lng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180.0;

  DriverRouteSnapshot? _tryBuildRouteSnapshot(Location? from, Location? to) {
    if (from == null || to == null) return null;
    return _buildRouteSnapshot(from, to);
  }

  DriverRouteSnapshot? _buildPreferredRouteSnapshot(
      Location? from, Location? to) {
    if (_sdkRouteSummary != null) {
      return DriverRouteSnapshot(
        distanceKm: _sdkRouteSummary!.distanceKm,
        etaMinutes: _sdkRouteSummary!.etaMinutes,
      );
    }
    return _tryBuildRouteSnapshot(from, to);
  }
}

class _OrderPriceEstimate {
  const _OrderPriceEstimate({
    required this.totalPrice,
    required this.summary,
  });

  final int totalPrice;
  final String summary;
}

_OrderPriceEstimate _estimateOrderPrice({
  required String tariffName,
  required int basePrice,
  required String vehicleType,
  required int lockedWheels,
  required bool running,
}) {
  final vehicleSurcharge = switch (vehicleType) {
    '\u041a\u0440\u043e\u0441\u0441\u043e\u0432\u0435\u0440' => 600,
    '\u041c\u0438\u043d\u0438\u0432\u044d\u043d' => 900,
    '\u0424\u0443\u0440\u0433\u043e\u043d' => 1200,
    _ => 0,
  };
  final wheelsSurcharge = lockedWheels * 350;
  final runningSurcharge = running ? 0 : 800;
  final total =
      basePrice + vehicleSurcharge + wheelsSurcharge + runningSurcharge;
  final parts = <String>[
    '$basePrice \u20bd \u0431\u0430\u0437\u043e\u0432\u044b\u0439 \u0442\u0430\u0440\u0438\u0444 $tariffName',
    if (vehicleSurcharge > 0)
      '$vehicleSurcharge \u20bd \u0437\u0430 \u0442\u0438\u043f \u0430\u0432\u0442\u043e',
    if (wheelsSurcharge > 0)
      '$wheelsSurcharge \u20bd \u0437\u0430 \u0437\u0430\u0431\u043b\u043e\u043a\u0438\u0440\u043e\u0432\u0430\u043d\u043d\u044b\u0435 \u043a\u043e\u043b\u0451\u0441\u0430',
    if (runningSurcharge > 0)
      '$runningSurcharge \u20bd \u0435\u0441\u043b\u0438 \u0430\u0432\u0442\u043e \u043d\u0435 \u043d\u0430 \u0445\u043e\u0434\u0443',
  ];
  return _OrderPriceEstimate(
    totalPrice: total,
    summary: parts.join(' + '),
  );
}

class _Tariff {
  const _Tariff(this.name, this.price, this.eta);
  final String name;
  final int price;
  final String eta;
}
