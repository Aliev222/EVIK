import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tow_truck_frontend/features/driver/domain/entities/driver_onboarding.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_verification_repository.dart';

class DriverOnboardingState {
  const DriverOnboardingState({
    this.documents = const {},
    this.fullName = '',
    this.vehicleModel = '',
    this.vehicleNumber = '',
    this.vehicleType = VehicleType.light,
    this.selfie,
    this.isLoading = false,
    this.uploadProgress = 0,
    this.uploadStatusMessage,
    this.errorMessage,
    this.submission,
  });

  final Map<DriverDocumentType, DriverDocumentDraft> documents;
  final String fullName;
  final String vehicleModel;
  final String vehicleNumber;
  final VehicleType vehicleType;
  final DriverImageDraft? selfie;
  final bool isLoading;
  final double uploadProgress;
  final String? uploadStatusMessage;
  final String? errorMessage;
  final DriverOnboardingSubmission? submission;

  bool get isDocumentsStepComplete =>
      DriverDocumentType.values.every(documents.containsKey);

  bool get isProfileStepComplete =>
      fullName.trim().length >= 2 &&
      vehicleModel.trim().length >= 2 &&
      _normalizePlate(vehicleNumber).length == 8 &&
      selfie != null;

  bool get isReadyForSubmission =>
      isDocumentsStepComplete && isProfileStepComplete;

  bool get hasSubmittedForModeration => submission != null;

  DriverOnboardingState copyWith({
    Map<DriverDocumentType, DriverDocumentDraft>? documents,
    String? fullName,
    String? vehicleModel,
    String? vehicleNumber,
    VehicleType? vehicleType,
    DriverImageDraft? selfie,
    bool clearSelfie = false,
    bool? isLoading,
    double? uploadProgress,
    String? uploadStatusMessage,
    bool clearUploadStatusMessage = false,
    String? errorMessage,
    bool clearError = false,
    DriverOnboardingSubmission? submission,
    bool clearSubmission = false,
  }) {
    return DriverOnboardingState(
      documents: documents ?? this.documents,
      fullName: fullName ?? this.fullName,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      selfie: clearSelfie ? null : selfie ?? this.selfie,
      isLoading: isLoading ?? this.isLoading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadStatusMessage: clearUploadStatusMessage
          ? null
          : uploadStatusMessage ?? this.uploadStatusMessage,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      submission: clearSubmission ? null : submission ?? this.submission,
    );
  }
}

final driverOnboardingProvider =
    StateNotifierProvider<DriverOnboardingNotifier, DriverOnboardingState>(
        (ref) {
  return DriverOnboardingNotifier(
    picker: ImagePicker(),
    verificationRepository: ref.watch(driverVerificationRepositoryProvider),
  );
});

class DriverOnboardingNotifier extends StateNotifier<DriverOnboardingState> {
  DriverOnboardingNotifier({
    required ImagePicker picker,
    required DriverVerificationRepository verificationRepository,
  })  : _picker = picker,
        _verificationRepository = verificationRepository,
        super(const DriverOnboardingState());

  final ImagePicker _picker;
  final DriverVerificationRepository _verificationRepository;

  void updateProfileDraft({
    String? fullName,
    String? vehicleModel,
    String? vehicleNumber,
    VehicleType? vehicleType,
  }) {
    state = state.copyWith(
      fullName: fullName,
      vehicleModel: vehicleModel,
      vehicleNumber: vehicleNumber,
      vehicleType: vehicleType,
      clearError: true,
    );
  }

  Future<void> pickDocument(
    DriverDocumentType type, {
    required ImageSource source,
  }) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearUploadStatusMessage: true,
      uploadProgress: 0,
    );

    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 2200,
      );

      if (pickedFile == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final image = await _buildImageDraft(pickedFile);
      await _validateDocumentImage(image);

      final nextDocuments = Map<DriverDocumentType, DriverDocumentDraft>.from(
        state.documents,
      );
      nextDocuments[type] = DriverDocumentDraft(
        type: type,
        file: pickedFile,
        fileSizeBytes: image.fileSizeBytes,
        width: image.width,
        height: image.height,
      );

      state = state.copyWith(
        documents: nextDocuments,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error is DriverOnboardingException
            ? error.message
            : 'Не удалось обработать фото. Попробуйте еще раз.',
      );
    }
  }

  Future<void> pickSelfie() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearUploadStatusMessage: true,
      uploadProgress: 0,
    );

    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 90,
        maxWidth: 1600,
      );

      if (pickedFile == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final image = await _buildImageDraft(pickedFile);
      if (image.fileSizeBytes < 45 * 1024 ||
          image.width < 700 ||
          image.height < 700) {
        throw const DriverOnboardingException(
          'Селфи должно быть четким, с лицом по центру и разрешением не ниже 700x700.',
        );
      }

      state = state.copyWith(
        selfie: image,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error is DriverOnboardingException
            ? error.message
            : 'Не удалось сохранить селфи. Попробуйте еще раз.',
      );
    }
  }

  void clearDocument(DriverDocumentType type) {
    final nextDocuments = Map<DriverDocumentType, DriverDocumentDraft>.from(
      state.documents,
    )..remove(type);

    state = state.copyWith(documents: nextDocuments, clearError: true);
  }

  void clearSelfie() {
    state = state.copyWith(clearSelfie: true, clearError: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<bool> submitForModeration(String userId) async {
    final validationError = validateProfileDraft();
    if (validationError != null) {
      state = state.copyWith(errorMessage: validationError);
      return false;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      uploadProgress: 0,
      uploadStatusMessage: 'Подготавливаем загрузку...',
    );

    try {
      final result = await _verificationRepository.submitVerification(
        payload: DriverVerificationPayload(
          userId: userId,
          fullName: state.fullName.trim(),
          vehicleModel: state.vehicleModel.trim(),
          vehicleNumber: _normalizePlate(state.vehicleNumber),
          vehicleType: state.vehicleType,
          documents: Map<DriverDocumentType, DriverDocumentDraft>.from(
            state.documents,
          ),
          selfie: state.selfie!,
        ),
        onProgress: (progress, message) {
          state = state.copyWith(
            uploadProgress: progress.clamp(0, 1),
            uploadStatusMessage: message,
          );
        },
      );

      final submission = DriverOnboardingSubmission(
        fullName: state.fullName.trim(),
        vehicleModel: state.vehicleModel.trim(),
        vehicleNumber: _normalizePlate(state.vehicleNumber),
        vehicleType: state.vehicleType,
        documents: Map<DriverDocumentType, DriverDocumentDraft>.from(
          state.documents,
        ),
        selfie: state.selfie!,
        documentUrls: result.documentUrls,
        submittedAt: result.submittedAt,
      );

      state = state.copyWith(
        isLoading: false,
        uploadProgress: 1,
        uploadStatusMessage: 'Заявка успешно отправлена',
        submission: submission,
        clearError: true,
      );
      return true;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Не удалось отправить документы. Проверьте сеть и повторите попытку.',
      );
      return false;
    }
  }

  String? validateProfileDraft() {
    if (!state.isDocumentsStepComplete) {
      return 'Сначала загрузите все обязательные документы.';
    }
    if (state.fullName.trim().length < 2) {
      return 'Введите ФИО водителя.';
    }
    if (state.vehicleModel.trim().length < 2) {
      return 'Введите модель машины.';
    }
    if (_normalizePlate(state.vehicleNumber).length != 8) {
      return 'Введите номер машины в формате А000АА00.';
    }
    if (state.selfie == null) {
      return 'Добавьте селфи водителя.';
    }
    return null;
  }

  Future<void> _validateDocumentImage(DriverImageDraft image) async {
    if (image.fileSizeBytes < 60 * 1024) {
      throw const DriverOnboardingException(
        'Фото слишком маленькое. Сделайте снимок ближе и при хорошем освещении.',
      );
    }

    if (image.width < 900 || image.height < 900) {
      throw const DriverOnboardingException(
        'Качество изображения недостаточное. Нужен четкий снимок не ниже 900x900.',
      );
    }
  }

  Future<DriverImageDraft> _buildImageDraft(XFile pickedFile) async {
    final bytes = await pickedFile.readAsBytes();
    final size = await _decodeImageSize(bytes);
    return DriverImageDraft(
      file: pickedFile,
      fileSizeBytes: bytes.lengthInBytes,
      width: size.$1,
      height: size.$2,
    );
  }

  Future<(int, int)> _decodeImageSize(Uint8List bytes) async {
    final completer = Completer<(int, int)>();
    ui.decodeImageFromList(bytes, (image) {
      completer.complete((image.width, image.height));
    });
    return completer.future;
  }
}

class DriverOnboardingException implements Exception {
  const DriverOnboardingException(this.message);

  final String message;
}

String _normalizePlate(String value) {
  return value.replaceAll(RegExp(r'[^A-ZА-Я0-9]'), '').toUpperCase();
}
