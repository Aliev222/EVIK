import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/core/realtime/event_dispatcher.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client.dart';
import 'package:tow_truck_frontend/core/realtime/websocket_client_channel.dart'
    if (dart.library.io) '../../../../core/realtime/websocket_client_io.dart'
    as platform_ws;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/order/data/repository_impl/http_order_repository.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/domain/repositories/order_repository.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final accessToken =
      ref.watch(authProvider.select((state) => state.accessToken));
  return HttpOrderRepository(
    apiClient: platform_api.createPlatformApiClient(),
    accessToken: accessToken,
    accessTokenProvider: () => ref.read(authProvider).accessToken,
  );
});

final webSocketClientProvider = Provider<WebSocketClient>((ref) {
  final client = platform_ws.createPlatformWebSocketClient();
  ref.onDispose(() {
    unawaited(client.disconnect());
  });
  return client;
});

final eventDispatcherProvider = Provider<EventDispatcher?>((ref) {
  final accessToken =
      ref.watch(authProvider.select((state) => state.accessToken));
  if (accessToken == null || accessToken.isEmpty) {
    return null;
  }

  final wsUrl = Uri.parse(defaultWsUrl).replace(
      queryParameters: <String, String>{
        'access_token': accessToken
      }).toString();
  final dispatcher = WsEventDispatcher(
    client: ref.watch(webSocketClientProvider),
    wsUrl: wsUrl,
  );
  ref.onDispose(() {
    unawaited(dispatcher.stop());
  });
  return dispatcher;
});

final orderUpdatesProvider = StreamProvider<Order>((ref) {
  final dispatcher = ref.watch(eventDispatcherProvider);
  if (dispatcher == null) {
    return const Stream<Order>.empty();
  }

  final repository = ref.watch(orderRepositoryProvider);
  final client = ref.watch(webSocketClientProvider);
  final controller = StreamController<Order>.broadcast();
  StreamSubscription<Event>? subscription;
  StreamSubscription<void>? reconnectionSub;

  Future<void> start() async {
    try {
      // Subscribe BEFORE connect to avoid losing events
      subscription = dispatcher.events().listen(
        (event) async {
          try {
            final order = await repository.getOrder(event.orderId);
            if (order != null && !controller.isClosed) {
              controller.add(order);
            }
          } catch (error, stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          }
        },
        onError: controller.addError,
      );

      reconnectionSub = client.onReconnected.listen((_) async {
        debugPrint('WS reconnected, fetching active order for catch-up');
        try {
          final activeOrder = await repository.getActiveOrder();
          if (activeOrder != null && !controller.isClosed) {
            controller.add(activeOrder);
            debugPrint(
              'Catch-up: active order ${activeOrder.id} status=${activeOrder.state}',
            );
          }
        } catch (e) {
          debugPrint('Catch-up fetch failed: $e');
        }
      });

      await dispatcher.start();
    } catch (error, stackTrace) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }

  unawaited(start());
  ref.onDispose(() async {
    await reconnectionSub?.cancel();
    await subscription?.cancel();
    await controller.close();
  });
  return controller.stream;
});

final webSocketStatusProvider = StreamProvider<WebSocketConnectionStatus>((ref) {
  final client = ref.watch(webSocketClientProvider);
  return client.connectionStatus;
});

class OrderProviderState {
  const OrderProviderState({
    this.currentOrder,
    this.orders = const <Order>[],
    this.isLoading = false,
    this.errorMessage,
  });

  final Order? currentOrder;
  final List<Order> orders;
  final bool isLoading;
  final String? errorMessage;

  OrderProviderState copyWith({
    Order? currentOrder,
    bool clearCurrentOrder = false,
    List<Order>? orders,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OrderProviderState(
      currentOrder:
          clearCurrentOrder ? null : currentOrder ?? this.currentOrder,
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class OrderNotifier extends StateNotifier<OrderProviderState> {
  OrderNotifier(this._repository, this._ref)
      : super(const OrderProviderState()) {
    _updatesSub = _ref.listen<AsyncValue<Order>>(
      orderUpdatesProvider,
      (_, next) {
        next.whenData(_mergeOrderUpdate);
      },
    );
  }

  final OrderRepository _repository;
  final Ref _ref;
  late final ProviderSubscription<AsyncValue<Order>> _updatesSub;

  Future<void> createOrder(CreateOrderCommand command) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final authState = _ref.read(authProvider);
    debugPrint('User role: ${authState.user?.role}');
    try {
      final order = await _repository.createOrder(command);
      _mergeOrderUpdate(order);
      state = state.copyWith(currentOrder: order, isLoading: false);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось создать заказ: $error',
      );
      rethrow;
    }
  }

  Future<bool> cancelCurrentOrder({String? reason}) async {
    final currentOrder = state.currentOrder;
    if (currentOrder == null) return true;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.cancelOrder(currentOrder.id, reason: reason);
      state = state.copyWith(clearCurrentOrder: true, isLoading: false);
      return true;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось отменить заказ: $error',
      );
      return false;
    }
  }

  Future<void> acceptOrder(String orderId, String driverId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.acceptOrder(orderId, driverId);
      final order = await _repository.getOrder(orderId);
      if (order != null) {
        _mergeOrderUpdate(order);
      }
      state = state.copyWith(currentOrder: order, isLoading: false);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось принять заказ: $error',
      );
    }
  }

  Future<void> loadOrders() async {
    final repository = _repository;
    if (repository is! HttpOrderRepository) {
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final orders = await repository.getOrders();
      state = state.copyWith(orders: orders, isLoading: false);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось загрузить заказы: $error',
      );
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void clearCurrentOrder() {
    state = state.copyWith(clearCurrentOrder: true);
  }

  void _mergeOrderUpdate(Order order) {
    final orders = <Order>[
      for (final existing in state.orders)
        if (existing.id == order.id) order else existing,
    ];
    if (!orders.any((existing) => existing.id == order.id)) {
      orders.add(order);
    }

    state = state.copyWith(
      currentOrder: state.currentOrder?.id == order.id ? order : null,
      orders: orders,
    );
  }

  @override
  void dispose() {
    _updatesSub.close();
    super.dispose();
  }
}

final orderProvider =
    StateNotifierProvider<OrderNotifier, OrderProviderState>((ref) {
  return OrderNotifier(ref.watch(orderRepositoryProvider), ref);
});

final watchOrderProvider =
    StreamProvider.family.autoDispose<Order?, String>((ref, orderId) {
  return ref.watch(orderRepositoryProvider).watchOrder(orderId);
});

final watchClientOrdersProvider =
    StreamProvider.family.autoDispose<List<Order>, String>((ref, clientId) {
  return ref.watch(orderRepositoryProvider).watchClientOrders(clientId);
});

final watchAvailableOrdersProvider = StreamProvider.family
    .autoDispose<List<Order>, ({double lat, double lng, double radius})>(
        (ref, location) {
  return ref.watch(orderRepositoryProvider).watchAvailableOrders(
        location.lat,
        location.lng,
        location.radius,
      );
});

final watchDriverOrderProvider =
    StreamProvider.family.autoDispose<Order?, String>((ref, driverId) {
  return ref.watch(orderRepositoryProvider).watchDriverCurrentOrder(driverId);
});

// One-shot bootstrap fetch of the caller's currently active (non-terminal)
// order. Used by the router at startup to decide whether to land the user
// on a tracking/active-order screen instead of the default home.
// Rebuilds when the authenticated user id changes (login / signOut),
// so a fresh fetch happens on each new session.
final activeOrderBootstrapProvider = FutureProvider<Order?>((ref) async {
  final userId =
      ref.watch(authProvider.select((state) => state.user?.id));
  if (userId == null || userId.isEmpty) {
    return null;
  }
  final repository = ref.watch(orderRepositoryProvider);
  return repository.getActiveOrder();
});
