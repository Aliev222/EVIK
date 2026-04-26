import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

enum DriverModerationStatus {
  pending,
  approved,
  rejected,
}

class DriverVerificationDocument {
  const DriverVerificationDocument({
    required this.userId,
    required this.fullName,
    required this.vehicleModel,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.documentUrls,
    required this.status,
    required this.submittedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  });

  final String userId;
  final String fullName;
  final String vehicleModel;
  final String vehicleNumber;
  final String vehicleType;
  final Map<String, String> documentUrls;
  final DriverModerationStatus status;
  final DateTime submittedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;

  factory DriverVerificationDocument.fromMap(Map<String, dynamic> map) {
    return DriverVerificationDocument(
      userId: map['userId'] as String? ?? '',
      fullName: map['fullName'] as String? ?? '',
      vehicleModel: map['vehicleModel'] as String? ?? '',
      vehicleNumber: map['vehicleNumber'] as String? ?? '',
      vehicleType: map['vehicleType'] as String? ?? '',
      documentUrls: ((map['documentUrls'] as Map<String, dynamic>?) ?? const {})
          .map((key, value) => MapEntry(key, '$value')),
      status: _parseStatus(map['status'] as String?),
      submittedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['submittedAt'] as int?) ?? 0),
      reviewedBy: map['reviewedBy'] as String?,
      reviewedAt: map['reviewedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['reviewedAt'] as int)
          : null,
      rejectionReason:
          map['rejectionReason'] as String? ?? map['reviewComment'] as String?,
    );
  }

  static DriverModerationStatus _parseStatus(String? value) {
    switch (value) {
      case 'approved':
        return DriverModerationStatus.approved;
      case 'rejected':
        return DriverModerationStatus.rejected;
      default:
        return DriverModerationStatus.pending;
    }
  }
}

final watchDriverModerationProvider =
    StreamProvider.family<DriverVerificationDocument?, String>((ref, userId) {
  return Stream<DriverVerificationDocument?>.value(
    DriverVerificationDocument(
      userId: userId,
      fullName: 'EVIK Driver',
      vehicleModel: 'Эвакуатор EVIK',
      vehicleNumber: '',
      vehicleType: 'light',
      documentUrls: const <String, String>{},
      status: DriverModerationStatus.approved,
      submittedAt: DateTime.now(),
    ),
  );
});

final currentDriverModerationProvider =
    Provider<AsyncValue<DriverVerificationDocument?>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const AsyncValue.data(null);
  }

  return ref.watch(watchDriverModerationProvider(user.id));
});
