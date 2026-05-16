import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

class DriverTaxProfile {
  const DriverTaxProfile({
    required this.driverId,
    required this.inn,
    required this.taxpayerType,
    required this.verificationStatus,
  });

  final String driverId;
  final String inn;
  final String taxpayerType;
  final String verificationStatus;

  bool get isVerified => verificationStatus == 'verified';

  factory DriverTaxProfile.fromJson(Map<String, dynamic> json) {
    return DriverTaxProfile(
      driverId: json['driver_id']?.toString() ?? '',
      inn: json['inn']?.toString() ?? '',
      taxpayerType: json['taxpayer_type']?.toString() ?? '',
      verificationStatus: json['verification_status']?.toString() ?? 'pending',
    );
  }
}

final driverTaxProfileProvider =
    FutureProvider.family<DriverTaxProfile?, String>((ref, driverId) async {
  final token = ref.watch(authProvider.select((state) => state.accessToken));
  if (token == null || token.isEmpty) return null;
  try {
    final json = await platform_api.createPlatformApiClient().get(
      '/drivers/$driverId/tax-profile',
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    final profile = json['tax_profile'];
    return profile is Map<String, dynamic>
        ? DriverTaxProfile.fromJson(profile)
        : null;
  } catch (_) {
    return null;
  }
});

final driverTaxProfileRepositoryProvider =
    Provider<DriverTaxProfileRepository>((ref) {
  final token = ref.watch(authProvider.select((state) => state.accessToken));
  return DriverTaxProfileRepository(token);
});

class DriverTaxProfileRepository {
  DriverTaxProfileRepository(this._token);

  final String? _token;

  Future<DriverTaxProfile> upsert({
    required String driverId,
    required String inn,
    required String taxpayerType,
  }) async {
    final token = _token;
    final json = await platform_api.createPlatformApiClient().put(
          '/drivers/$driverId/tax-profile',
          <String, dynamic>{'inn': inn, 'taxpayer_type': taxpayerType},
          headers: token == null || token.isEmpty
              ? null
              : <String, String>{'Authorization': 'Bearer $token'},
        );
    return DriverTaxProfile.fromJson(
      (json['tax_profile'] as Map).cast<String, dynamic>(),
    );
  }
}
