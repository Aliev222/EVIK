import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/realtime/event_dispatcher.dart';
import '../../../../core/realtime/websocket_client.dart';
import '../../data/repository_impl/order_repository_impl.dart';
import '../../domain/entities/order.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/usecases/create_order_usecase.dart';

class OrderUiState {
  const OrderUiState({
    required this.status,
    this.order,
    this.error,
  });

  final OrderState status;
  final Order? order;
  final String? error;

  factory OrderUiState.initial() => const OrderUiState(status: OrderState.idle);

  OrderUiState copyWith({
    OrderState? status,
    Order? order,
    String? error,
  }) {
    return OrderUiState(
      status: status ?? this.status,
      order: order ?? this.order,
      error: error,
    );
  }
}

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  // TODO: Override in composition root with production implementation.
  const dataSource = HttpOrderRemoteDataSource(apiClient: NoOpApiClient());
  return OrderRepositoryImpl(remote: dataSource);
});

final createOrderUseCaseProvider = Provider<CreateOrderUseCase>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return CreateOrderUseCase(repository);
});

final eventDispatcherProvider = Provider<EventDispatcher>((ref) {
  // TODO: Override in composition root with production WebSocket transport.
  return WsEventDispatcher(
    client: InMemoryWebSocketClient(),
    wsUrl: 'ws://localhost:8080/ws/orders',
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

  Future<void> submitOrder(CreateOrderCommand command) async {
    state = state.copyWith(status: OrderState.searching, error: null);
    try {
      final order = await _createOrderUseCase.execute(command);
      state = state.copyWith(status: order.state, order: order);
      await _bindBackendState(order.id);
    } catch (e) {
      // Keep optimistic searching state as safe fallback when backend is unavailable.
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> cancelCurrentOrder() async {
    final orderId = state.order?.id;
    if (orderId == null) return;

    try {
      final order = await _repository.cancelOrder(orderId);
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
          state = state.copyWith(status: next);
          if (_isTerminal(next)) {
            _orderStatusPollTimer?.cancel();
          }
        }
      },
      onError: (Object e, StackTrace _) {
        state = state.copyWith(error: e.toString());
      },
    );

    _orderStatusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollOrderStatus(orderId));
    });
    unawaited(_pollOrderStatus(orderId));
  }

  Future<void> _pollOrderStatus(String orderId) async {
    if (!mounted) return;

    try {
      final order = await _repository.getOrder(orderId);
      if (!mounted) return;
      state = state.copyWith(status: order.state, order: order);
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
