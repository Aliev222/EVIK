import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

final driverOnboardingStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final auth = ref.watch(authProvider);
  final id = auth.user?.id;
  final token = auth.accessToken;
  if (id == null || token == null || token.isEmpty) {
    throw Exception('Authentication required');
  }
  final api = platform_api.createPlatformApiClient();
  return Map<String, dynamic>.from(await api.get(
      '/api/v1/drivers/$id/onboarding',
      headers: {'Authorization': 'Bearer $token'}));
});

Future<void> acceptCurrentDriverOffer(WidgetRef ref) async {
  final auth = ref.read(authProvider);
  final id = auth.user?.id;
  final token = auth.accessToken;
  if (id == null || token == null || token.isEmpty) {
    throw Exception('Authentication required');
  }
  final api = platform_api.createPlatformApiClient();
  await api.post(
      '/api/v1/drivers/$id/onboarding/offer/accept', {'method': 'button'},
      headers: {'Authorization': 'Bearer $token'});
  ref.invalidate(driverOnboardingStatusProvider);
}
