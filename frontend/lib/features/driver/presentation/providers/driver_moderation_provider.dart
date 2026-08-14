import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_verification_provider.dart';

enum DriverModerationStatus {
  pending,
  approved,
  rejected,
  changesRequested,
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
      case 'blocked':
        return DriverModerationStatus.rejected;
      case 'changes_requested':
        return DriverModerationStatus.changesRequested;
      default:
        return DriverModerationStatus.pending;
    }
  }

  factory DriverVerificationDocument.fromVerificationStatus(
      DriverVerificationStatus status) {
    final documentUrls = <String, String>{};
    status.documentsUploaded.forEach((key, doc) {
      documentUrls[key] = doc.url;
    });

    return DriverVerificationDocument(
      userId: status.driverId,
      fullName: '',
      vehicleModel: '',
      vehicleNumber: '',
      vehicleType: 'light',
      documentUrls: documentUrls,
      status: _parseStatus(status.status),
      submittedAt: status.submittedAt ?? DateTime.now(),
      reviewedAt: status.updatedAt,
      rejectionReason: status.adminComments,
    );
  }
}

final watchDriverModerationProvider =
    StreamProvider.family<DriverVerificationDocument?, String>((ref, userId) {
  final verificationStatusAsync =
      ref.watch(autoRefreshingVerificationStatusProvider(userId));

  final doc = verificationStatusAsync.when(
    data: (status) => DriverVerificationDocument.fromVerificationStatus(status),
    loading: () => null,
    error: (_, __) => DriverVerificationDocument(
      userId: userId,
      fullName: '',
      vehicleModel: '',
      vehicleNumber: '',
      vehicleType: 'light',
      documentUrls: const <String, String>{},
      status: DriverModerationStatus.pending,
      submittedAt: DateTime.now(),
    ),
  );

  return Stream<DriverVerificationDocument?>.value(doc);
});

final currentDriverModerationProvider =
    Provider<AsyncValue<DriverVerificationDocument?>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const AsyncValue.data(null);
  }

  return ref.watch(watchDriverModerationProvider(user.id));
});
