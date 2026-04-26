import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../order/domain/entities/order.dart';
import '../../domain/entities/driver_onboarding.dart';

final driverVerificationRepositoryProvider =
    Provider<DriverVerificationRepository>((ref) {
  return const LocalDriverVerificationRepository();
});

class DriverVerificationPayload {
  const DriverVerificationPayload({
    required this.userId,
    required this.fullName,
    required this.vehicleModel,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.documents,
    required this.selfie,
  });

  final String userId;
  final String fullName;
  final String vehicleModel;
  final String vehicleNumber;
  final VehicleType vehicleType;
  final Map<DriverDocumentType, DriverDocumentDraft> documents;
  final DriverImageDraft selfie;
}

class DriverVerificationResult {
  const DriverVerificationResult({
    required this.documentUrls,
    required this.submittedAt,
  });

  final Map<String, String> documentUrls;
  final DateTime submittedAt;
}

abstract class DriverVerificationRepository {
  Future<DriverVerificationResult> submitVerification({
    required DriverVerificationPayload payload,
    void Function(double progress, String message)? onProgress,
  });
}

class LocalDriverVerificationRepository implements DriverVerificationRepository {
  const LocalDriverVerificationRepository();

  @override
  Future<DriverVerificationResult> submitVerification({
    required DriverVerificationPayload payload,
    void Function(double progress, String message)? onProgress,
  }) async {
    final totalItems = payload.documents.length + 1;
    var completed = 0;
    final documentUrls = <String, String>{};

    for (final entry in payload.documents.entries) {
      onProgress?.call(
        completed / (totalItems + 1),
        'Uploading ${entry.key.name}...',
      );
      documentUrls[_fieldKeyFor(entry.key)] = entry.value.file.path;
      completed += 1;
      onProgress?.call(
        completed / (totalItems + 1),
        'Uploaded $completed of $totalItems files',
      );
    }

    onProgress?.call(
      completed / (totalItems + 1),
      'Uploading selfie...',
    );
    documentUrls['selfie'] = payload.selfie.file.path;
    completed += 1;

    onProgress?.call(1, 'Verification request submitted');
    return DriverVerificationResult(
      documentUrls: documentUrls,
      submittedAt: DateTime.now(),
    );
  }

  String _fieldKeyFor(DriverDocumentType type) {
    return switch (type) {
      DriverDocumentType.passport => 'passport',
      DriverDocumentType.license => 'license',
      DriverDocumentType.vehicleCertificate => 'vehicleDocs',
      DriverDocumentType.vehiclePhoto => 'vehiclePhoto',
    };
  }
}
