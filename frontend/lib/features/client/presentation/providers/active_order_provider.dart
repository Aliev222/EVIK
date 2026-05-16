import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';

final activeOrderStreamProvider = StreamProvider.autoDispose<Order?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<Order?>.value(null);
  }

  final repository = ref.watch(orderRepositoryProvider);
  return repository.watchActiveOrderForClient(user.id);
});

final activeOrderProvider = Provider<Order?>((ref) {
  return ref.watch(activeOrderStreamProvider).valueOrNull;
});

final hasActiveOrderProvider = Provider<bool>((ref) {
  return ref.watch(activeOrderProvider) != null;
});

final activeOrderStatusProvider = Provider<OrderStatus?>((ref) {
  return ref.watch(activeOrderProvider)?.status;
});

final assignedDriverIdProvider = Provider<String?>((ref) {
  return ref.watch(activeOrderProvider)?.driverId;
});
