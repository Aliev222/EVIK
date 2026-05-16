import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:tow_truck_frontend/core/network/api_client_stub.dart'
    if (dart.library.io) '../../../../core/network/api_client_io.dart'
    as platform_api;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_onboarding.dart';

final driverVerificationRepositoryProvider =
    Provider<DriverVerificationRepository>((ref) {
  final token = ref.watch(authProvider.select((state) => state.accessToken));
  return HttpDriverVerificationRepository(token);
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

class HttpDriverVerificationRepository implements DriverVerificationRepository {
  const HttpDriverVerificationRepository(this._token);

  final String? _token;

  @override
  Future<DriverVerificationResult> submitVerification({
    required DriverVerificationPayload payload,
    void Function(double progress, String message)? onProgress,
  }) async {
    if (_token == null || _token.isEmpty) {
      throw Exception('Authentication required');
    }

    final apiClient = platform_api.createPlatformApiClient();
    final totalItems = payload.documents.length + 1;
    var completed = 0;
    final documentUrls = <String, String>{};

    try {
      // Upload each document
      for (final entry in payload.documents.entries) {
        final documentType = _fieldKeyFor(entry.key);
        onProgress?.call(
          completed / totalItems,
          'Uploading ${entry.key.name}...',
        );

        final uploadedDoc = await _uploadDocument(
          apiClient,
          File(entry.value.file.path),
          documentType,
        );
        documentUrls[documentType] = uploadedDoc['document']['public_url'];
        completed++;

        onProgress?.call(
          completed / totalItems,
          'Uploaded $completed of $totalItems files',
        );
      }

      // Upload selfie
      onProgress?.call(
        completed / totalItems,
        'Uploading selfie...',
      );

      final selfieDoc = await _uploadDocument(
        apiClient,
        File(payload.selfie.file.path),
        'selfie',
      );
      documentUrls['selfie'] = selfieDoc['document']['public_url'];
      completed++;

      onProgress?.call(1.0, 'Verification request submitted');

      return DriverVerificationResult(
        documentUrls: documentUrls,
        submittedAt: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to upload documents: $e');
    }
  }

  Future<Map<String, dynamic>> _uploadDocument(
    dynamic apiClient,
    File file,
    String documentType,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${apiClient.baseUrl}/driver-documents/uploads'),
    );

    // Add headers
    request.headers['Authorization'] = 'Bearer $_token';

    // Add form fields
    request.fields['document_type'] = documentType;

    // Add file
    final mimeType = _getMimeType(file.path);
    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: MediaType.parse(mimeType),
    );
    request.files.add(multipartFile);

    // Send request
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(
        json.decode(responseBody),
      );
    } else {
      throw Exception(
        'Upload failed (${response.statusCode}): $responseBody',
      );
    }
  }

  String _getMimeType(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
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
