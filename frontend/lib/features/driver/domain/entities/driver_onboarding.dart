import '../../../order/domain/entities/order.dart';
import 'package:image_picker/image_picker.dart';

enum DriverDocumentType {
  passport,
  license,
  vehicleCertificate,
  vehiclePhoto,
}

extension DriverDocumentTypeX on DriverDocumentType {
  String get title {
    switch (this) {
      case DriverDocumentType.passport:
        return 'Паспорт';
      case DriverDocumentType.license:
        return 'Права';
      case DriverDocumentType.vehicleCertificate:
        return 'ПТС машины';
      case DriverDocumentType.vehiclePhoto:
        return 'Фото машины';
    }
  }

  String get ctaLabel {
    switch (this) {
      case DriverDocumentType.passport:
        return 'Сфотографировать паспорт';
      case DriverDocumentType.license:
        return 'Сфотографировать права';
      case DriverDocumentType.vehicleCertificate:
        return 'Сфотографировать ПТС';
      case DriverDocumentType.vehiclePhoto:
        return 'Сфотографировать машину';
    }
  }
}

extension DriverVehicleTypeX on VehicleType {
  String get displayName {
    switch (this) {
      case VehicleType.light:
        return 'Легковой';
      case VehicleType.suv:
        return 'Внедорожник';
      case VehicleType.minibus:
        return 'Микроавтобус';
      case VehicleType.truck:
        return 'Грузовой';
    }
  }
}

class DriverImageDraft {
  const DriverImageDraft({
    required this.file,
    required this.fileSizeBytes,
    required this.width,
    required this.height,
  });

  final XFile file;
  final int fileSizeBytes;
  final int width;
  final int height;
}

class DriverDocumentDraft extends DriverImageDraft {
  const DriverDocumentDraft({
    required this.type,
    required super.file,
    required super.fileSizeBytes,
    required super.width,
    required super.height,
  });

  final DriverDocumentType type;
}

class DriverOnboardingSubmission {
  const DriverOnboardingSubmission({
    required this.fullName,
    required this.vehicleModel,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.documents,
    required this.selfie,
    required this.documentUrls,
    required this.submittedAt,
  });

  final String fullName;
  final String vehicleModel;
  final String vehicleNumber;
  final VehicleType vehicleType;
  final Map<DriverDocumentType, DriverDocumentDraft> documents;
  final DriverImageDraft selfie;
  final Map<String, String> documentUrls;
  final DateTime submittedAt;
}
