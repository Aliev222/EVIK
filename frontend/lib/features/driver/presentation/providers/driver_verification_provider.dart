import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

class DriverVerificationStatus {
  const DriverVerificationStatus({
    required this.driverId,
    required this.status,
    required this.documentsUploaded,
    this.submittedAt,
    this.updatedAt,
    this.adminComments = '',
  });

  final String driverId;
  final String status; // 'not_submitted', 'pending', 'approved', 'rejected', 'changes_requested', 'blocked'
  final Map<String, DocumentInfo> documentsUploaded;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
  final String adminComments;

  factory DriverVerificationStatus.fromJson(Map<String, dynamic> json) {
    final docsMap = <String, DocumentInfo>{};
    if (json['documents_uploaded'] is Map) {
      final docs = json['documents_uploaded'] as Map<String, dynamic>;
      for (final entry in docs.entries) {
        docsMap[entry.key] = DocumentInfo.fromJson(entry.value);
      }
    }

    return DriverVerificationStatus(
      driverId: json['driver_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'not_submitted',
      documentsUploaded: docsMap,
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      adminComments: json['admin_comments']?.toString() ?? '',
    );
  }
}

class DocumentInfo {
  const DocumentInfo({
    required this.url,
    required this.uploadedAt,
    required this.contentType,
  });

  final String url;
  final DateTime uploadedAt;
  final String contentType;

  factory DocumentInfo.fromJson(Map<String, dynamic> json) {
    return DocumentInfo(
      url: json['url']?.toString() ?? '',
      uploadedAt: DateTime.tryParse(json['uploaded_at']?.toString() ?? '') ?? DateTime.now(),
      contentType: json['content_type']?.toString() ?? '',
    );
  }
}

final driverVerificationStatusProvider = FutureProvider.family<DriverVerificationStatus, String>((ref, driverId) async {
  final token = ref.watch(authProvider.select((state) => state.accessToken));
  if (token == null || token.isEmpty) {
    throw Exception('Authentication required');
  }

  try {
    final apiClient = platform_api.createPlatformApiClient();
    final response = await apiClient.get(
      '/drivers/$driverId/verification-status',
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );

    return DriverVerificationStatus.fromJson(response);
  } catch (e) {
    throw Exception('Failed to get verification status: $e');
  }
});

// Provider to refresh verification status
final refreshVerificationStatusProvider = StateProvider<int>((ref) => 0);

// Auto-refreshing provider that updates when refreshVerificationStatusProvider changes
final autoRefreshingVerificationStatusProvider = FutureProvider.family<DriverVerificationStatus, String>((ref, driverId) async {
  // Watch the refresh counter to trigger rebuilds
  ref.watch(refreshVerificationStatusProvider);

  // Use the same logic as the base provider
  return ref.watch(driverVerificationStatusProvider(driverId).future);
});
