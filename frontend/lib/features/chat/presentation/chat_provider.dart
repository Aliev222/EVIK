import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/chat/data/chat_repository.dart';
import 'package:tow_truck_frontend/features/chat/presentation/chat_controller.dart';
import 'package:tow_truck_frontend/features/order/presentation/providers/order_provider.dart';

final chatControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatState, ChatControllerArgs>((ref, args) {
  final dispatcher = ref.watch(eventDispatcherProvider);
  if (dispatcher == null) {
    throw StateError('Chat requires an authenticated WebSocket');
  }
  final repository = ChatRepository(
    api: platform_api.createPlatformApiClient(),
    dispatcher: dispatcher,
    client: ref.watch(webSocketClientProvider),
    tokenProvider: () => ref.read(authProvider).accessToken,
  );
  return ChatController(args.orderId, repository, readOnly: args.readOnly);
});

class ChatControllerArgs {
  const ChatControllerArgs(this.orderId, {this.readOnly = false});
  final String orderId;
  final bool readOnly;
  @override
  bool operator ==(Object other) =>
      other is ChatControllerArgs &&
      other.orderId == orderId &&
      other.readOnly == readOnly;
  @override
  int get hashCode => Object.hash(orderId, readOnly);
}
