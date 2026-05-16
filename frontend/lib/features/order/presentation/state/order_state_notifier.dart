import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client.dart';
import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/core/realtime/event_dispatcher.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client_stub.dart'
    if (dart.library.io) '../../../../core/realtime/websocket_client_io.dart'
    as platform_ws;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/order/data/repository_impl/order_repository_impl.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/repositories/order_repository.dart';
import 'package:tow_truck_frontend/features/order/domain/usecases/create_order_usecase.dart';

class OrderUiState {
  const OrderUiState({
    required this.status,
    this.order,
    this.cancellationReason,
    this.error,
  });

  final OrderState status;
  final Order? order;
  final String? cancellationReason;
  final String? error;

  factory OrderUiState.initial() => const OrderUiState(status: OrderState.idle);

  OrderUiState copyWith({
    OrderState? status,
    Order? order,
    String? cancellationReason,
    bool clearCancellationReason = false,
    String? error,
  }) {
    return OrderUiState(
      status: status ?? this.status,
      order: order ?? this.order,
      cancellationReason: clearCancellationReason
          ? null
          : cancellationReason ?? this.cancellationReason,
      error: error,
    );
  }
}

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final accessToken = ref.watch(authProvider.select((state) => state.accessToken));
  final dataSource = HttpOrderRemoteDataSource(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: accessToken,
  );
  return OrderRepositoryImpl(remote: dataSource);
});

final createOrderUseCaseProvider = Provider<CreateOrderUseCase>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return CreateOrderUseCase(repository);
});

final eventDispatcherProvider = Provider<EventDispatcher>((ref) {
  final accessToken = ref.watch(authProvider.select((state) => state.accessToken));
  final wsUrl = accessToken == null || accessToken.isEmpty
      ? defaultWsUrl
      : '$defaultWsUrl?access_token=$accessToken';
  return WsEventDispatcher(
    client: platform_ws.createPlatformWebSocketClient(),
    wsUrl: wsUrl,
  );
});

final orderStateNotifierProvider =
    StateNotifierProvider<OrderStateNotifier, OrderUiState>((ref) {
  return OrderStateNotifier(
    createOrderUseCase: ref.watch(createOrderUseCaseProvider),
    repository: ref.watch(orderRepositoryProvider),
    eventDispatcher: ref.watch(eventDispatcherProvider),
  );
});

class OrderStateNotifier extends StateNotifier<OrderUiState> {
  OrderStateNotifier({
    required CreateOrderUseCase createOrderUseCase,
    required OrderRepository repository,
    required EventDispatcher eventDispatcher,
  })  : _createOrderUseCase = createOrderUseCase,
        _repository = repository,
        _eventDispatcher = eventDispatcher,
        super(OrderUiState.initial());

  final CreateOrderUseCase _createOrderUseCase;
  final OrderRepository _repository;
  final EventDispatcher _eventDispatcher;
  StreamSubscription<OrderState>? _orderStateSub;
  StreamSubscription<Event>? _orderEventsSub;
  Timer? _orderStatusPollTimer;
  bool _dispatcherStarted = false;
  int _requestVersion = 0;

  Future<void> submitOrder(CreateOrderCommand command) async {
    final requestVersion = ++_requestVersion;
    state = state.copyWith(
      status: OrderState.searching,
      clearCancellationReason: true,
      error: null,
    );
    try {
      final order = await _createOrderUseCase.execute(command);
      if (requestVersion != _requestVersion) return;
      state = state.copyWith(
        status: order.state,
        order: order,
        clearCancellationReason: true,
      );
      await _bindBackendState(order.id);
    } catch (e) {
      if (requestVersion != _requestVersion) return;
      // Keep optimistic searching state as safe fallback when backend is unavailable.
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> cancelCurrentOrder({String reason = 'client_cancelled'}) async {
    _requestVersion++;
    await _orderStateSub?.cancel();
    _orderStateSub = null;
    await _orderEventsSub?.cancel();
    _orderEventsSub = null;
    _orderStatusPollTimer?.cancel();
    _orderStatusPollTimer = null;

    final orderId = state.order?.id;
    final currentOrder = state.order;
    if (orderId == null) {
      state = state.copyWith(
        status: OrderState.cancelled,
        cancellationReason: reason,
        error: null,
      );
      return;
    }

    if (currentOrder != null) {
      state = state.copyWith(
        status: OrderState.cancelled,
        order: currentOrder.copyWith(state: OrderState.cancelled),
        cancellationReason: reason,
        error: null,
      );
    } else {
      state = state.copyWith(
        status: OrderState.cancelled,
        cancellationReason: reason,
        error: null,
      );
    }

    try {
      final order = await _repository.cancelOrder(orderId, reason: reason);
      state = state.copyWith(status: order.state, order: order);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> _bindBackendState(String orderId) async {
    if (!_dispatcherStarted) {
      await _eventDispatcher.start();
      _dispatcherStarted = true;
    }

    await _orderStateSub?.cancel();
    await _orderEventsSub?.cancel();
    _orderStatusPollTimer?.cancel();

    _orderStateSub = _repository.watchOrderState(orderId).listen(
      (nextState) => state = state.copyWith(status: nextState),
      onError: (Object e, StackTrace _) {
        state = state.copyWith(error: e.toString());
      },
    );

    _orderEventsSub = _eventDispatcher.orderEvents(orderId).listen(
      (event) {
        final next = _fromBackendEvent(event.type);
        if (next != null) {
          if (next == OrderState.cancelled) {
            state = state.copyWith(
              status: next,
              cancellationReason:
                  _extractCancellationReason(event) ?? state.cancellationReason,
            );
          } else {
            state = state.copyWith(status: next, clearCancellationReason: true);
          }
          if (_isTerminal(next)) {
            _orderStatusPollTimer?.cancel();
          }
        }
      },
      onError: (Object e, StackTrace _) {
        state = state.copyWith(error: e.toString());
      },
    );

    _orderStatusPollTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(_pollOrderStatus(orderId));
    });
    unawaited(_pollOrderStatus(orderId));
  }

  Future<void> _pollOrderStatus(String orderId) async {
    if (!mounted) return;

    try {
      final order = await _repository.getOrder(orderId);
      if (!mounted) return;
      state = state.copyWith(
        status: order.state,
        order: order,
        clearCancellationReason: order.state != OrderState.cancelled,
      );
      if (_isTerminal(order.state)) {
        _orderStatusPollTimer?.cancel();
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: e.toString());
      }
    }
  }

  OrderState? _fromBackendEvent(String type) {
    return switch (type) {
      'order_created' => null,
      'searching' => OrderState.searching,
      'order_accepted' => OrderState.accepted,
      'order_arrived' => OrderState.arrived,
      'in_progress' => OrderState.inProgress,
      'completed' => OrderState.completed,
      'cancelled' => OrderState.cancelled,
      'no_driver_found' => OrderState.noDriverFound,
      _ => null,
    };
  }

  String? _extractCancellationReason(Event event) {
    if (event.type != 'cancelled') return null;
    final payload = event.payload;
    if (payload is Map<String, dynamic>) {
      final reason = payload['reason']?.toString();
      if (reason != null && reason.isNotEmpty) {
        return reason;
      }
    }
    return null;
  }

  bool _isTerminal(OrderState status) {
    return switch (status) {
      OrderState.completed ||
      OrderState.cancelled ||
      OrderState.noDriverFound =>
        true,
      _ => false,
    };
  }

  @override
  void dispose() {
    _orderStateSub?.cancel();
    _orderEventsSub?.cancel();
    _orderStatusPollTimer?.cancel();
    if (_dispatcherStarted) {
      _eventDispatcher.stop();
    }
    super.dispose();
  }
}
