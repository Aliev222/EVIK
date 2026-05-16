import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';

/// Провайдер для создания заказов через real-time сервис
class RealTimeOrderNotifier extends StateNotifier<AsyncValue<String?>> {
  RealTimeOrderNotifier(this._realTimeService)
      : super(const AsyncValue.data(null));

  final RealTimeLocationService _realTimeService;

  /// Создание заказа через WebSocket
  Future<void> createRealTimeOrder({
    required String clientId,
    required LocationModel pickupLocation,
    required LocationModel dropoffLocation,
    required VehicleType vehicleType,
    String? notes,
  }) async {
    state = const AsyncValue.loading();

    try {
      // Подключаемся как клиент
      final connected = await _realTimeService.connect(
        userId: clientId,
        userType: 'client',
      );

      if (!connected) {
        state = AsyncValue.error(
          'Не удалось подключиться к серверу заказов',
          StackTrace.current,
        );
        return;
      }

      // Отправляем заказ на сервер
      await _realTimeService.createOrder(
        pickupLat: pickupLocation.lat,
        pickupLng: pickupLocation.lng,
        dropoffLat: dropoffLocation.lat,
        dropoffLng: dropoffLocation.lng,
        vehicleType: vehicleType,
        notes: notes,
      );

      // Генерируем ID заказа (в реальном приложении сервер вернет его)
      final orderId =
          'order_${DateTime.now().millisecondsSinceEpoch}_$clientId';

      state = AsyncValue.data(orderId);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Отмена текущего заказа
  Future<void> cancelOrder() async {
    // Отключаемся от WebSocket
    await _realTimeService.disconnect();
    state = const AsyncValue.data(null);
  }
}

/// Provider для real-time заказов
final realTimeOrderProvider =
    StateNotifierProvider<RealTimeOrderNotifier, AsyncValue<String?>>((ref) {
  final realTimeService = ref.read(realTimeLocationServiceProvider);
  return RealTimeOrderNotifier(realTimeService);
});

/// Провайдер для получения ID текущего пользователя
final currentUserIdProvider = Provider<String?>((ref) {
  final user = ref.watch(currentUserProvider);
  return user?.id;
});
