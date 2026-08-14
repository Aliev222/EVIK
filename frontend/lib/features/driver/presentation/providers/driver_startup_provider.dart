import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'driver_verification_provider.dart';
import 'driver_tax_profile_provider.dart';

enum DriverStartupState {
  loading,
  needsDocuments,
  documentsUnderReview,
  needsTaxProfile,
  taxProfileUnderReview,
  canWork,
  blocked,
  error,
}

class DriverStartupInfo {
  const DriverStartupInfo({
    required this.state,
    this.message,
    this.nextRoute,
  });

  final DriverStartupState state;
  final String? message;
  final String? nextRoute;

  DriverStartupInfo copyWith({
    DriverStartupState? state,
    String? message,
    String? nextRoute,
  }) {
    return DriverStartupInfo(
      state: state ?? this.state,
      message: message ?? this.message,
      nextRoute: nextRoute ?? this.nextRoute,
    );
  }
}

final driverStartupProvider = FutureProvider<DriverStartupInfo>((ref) async {
  final user = ref.watch(authProvider).user;

  if (user == null) {
    return const DriverStartupInfo(
      state: DriverStartupState.error,
      message: 'Пользователь не авторизован',
    );
  }

  try {
    // Get verification status
    final verificationStatus = await ref.watch(
      driverVerificationStatusProvider(user.id).future
    );

    // Get tax profile status
    final taxProfile = await ref.watch(
      driverTaxProfileProvider(user.id).future
    );

    return determineStartupState(verificationStatus, taxProfile);
  } catch (e) {
    return DriverStartupInfo(
      state: DriverStartupState.error,
      message: 'Ошибка загрузки данных: $e',
    );
  }
});

/// Pure status→route mapping. Public so it can be unit-tested directly without
/// a ProviderContainer: verification status (and optional tax profile) in,
/// the routing decision out.
DriverStartupInfo determineStartupState(
  DriverVerificationStatus verificationStatus,
  DriverTaxProfile? taxProfile,
) {
  // Check document verification status first
  switch (verificationStatus.status) {
    case 'not_submitted':
      return const DriverStartupInfo(
        state: DriverStartupState.needsDocuments,
        message: 'Необходимо загрузить документы для верификации',
        nextRoute: '/driver/documents',
      );

    case 'pending':
      return const DriverStartupInfo(
        state: DriverStartupState.documentsUnderReview,
        message: 'Документы на проверке. Ожидайте результатов модерации.',
        nextRoute: '/driver/moderation',
      );

    case 'changes_requested':
      return DriverStartupInfo(
        state: DriverStartupState.needsDocuments,
        message: _statusMessageWithReason(
          prefix: 'Модератор запросил изменения',
          fallback: 'Требуются изменения в документах. Загрузите исправленные документы, чтобы продолжить проверку.',
          reason: verificationStatus.adminComments,
          hint: 'Загрузите исправленные документы, чтобы продолжить проверку.',
        ),
        nextRoute: '/driver/documents',
      );

    case 'rejected':
      // Отказ — это не блокировка: водитель может исправить документы и
      // переподать (маршрут переподачи, как у changes_requested).
      return DriverStartupInfo(
        state: DriverStartupState.needsDocuments,
        message: _statusMessageWithReason(
          prefix: 'Заявка отклонена',
          fallback: 'Заявка отклонена. Исправьте документы и отправьте повторно.',
          reason: verificationStatus.adminComments,
          hint: 'Исправьте документы и отправьте повторно.',
        ),
        nextRoute: '/driver/documents',
      );

    case 'blocked':
      // Блокировка «липкая»: переподача запрещена backend-гардом, водителю
      // доступен только контакт поддержки.
      return const DriverStartupInfo(
        state: DriverStartupState.blocked,
        message: 'Аккаунт заблокирован. Переподача документов недоступна — обратитесь в поддержку.',
        nextRoute: '/driver/blocked',
      );

    case 'approved':
      // Documents are approved, now check tax profile
      break;

    default:
      return const DriverStartupInfo(
        state: DriverStartupState.error,
        message: 'Неизвестный статус верификации',
      );
  }

  // Documents are approved, check tax profile
  if (taxProfile == null) {
    return const DriverStartupInfo(
      state: DriverStartupState.needsTaxProfile,
      message: 'Необходимо заполнить налоговый профиль',
      nextRoute: '/driver/tax-profile',
    );
  }

  switch (taxProfile.verificationStatus) {
    case 'pending':
      return const DriverStartupInfo(
        state: DriverStartupState.taxProfileUnderReview,
        message: 'Налоговый профиль на проверке',
        nextRoute: '/driver/tax-profile',
      );

    case 'changes_requested':
      return const DriverStartupInfo(
        state: DriverStartupState.needsTaxProfile,
        message: 'Требуются изменения в налоговом профиле',
        nextRoute: '/driver/tax-profile',
      );

    case 'rejected':
      return const DriverStartupInfo(
        state: DriverStartupState.needsTaxProfile,
        message: 'Налоговый профиль отклонен. Проверьте данные и отправьте повторно.',
        nextRoute: '/driver/tax-profile',
      );

    case 'verified':
      // All good, can work
      return const DriverStartupInfo(
        state: DriverStartupState.canWork,
        message: 'Все проверки пройдены. Можно работать!',
        nextRoute: '/driver/home',
      );

    default:
      return const DriverStartupInfo(
        state: DriverStartupState.needsTaxProfile,
        message: 'Неизвестный статус налогового профиля',
        nextRoute: '/driver/tax-profile',
      );
  }
}

String _statusMessageWithReason({
  required String prefix,
  required String fallback,
  required String reason,
  required String hint,
}) {
  final trimmed = reason.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }
  return '$prefix: $trimmed. $hint';
}

// Provider to get user-friendly status message
final driverStatusMessageProvider = Provider<String>((ref) {
  return ref.watch(driverStartupProvider).when(
    loading: () => 'Загрузка...',
    error: (error, stack) => 'Ошибка: $error',
    data: (info) => info.message ?? 'Проверка статуса...',
  );
});

// Provider to check if driver can work (for gate checks)
final canDriverWorkProvider = Provider<bool>((ref) {
  return ref.watch(driverStartupProvider).when(
    loading: () => false,
    error: (error, stack) => false,
    data: (info) => info.state == DriverStartupState.canWork,
  );
});

// Provider for next recommended route
final driverRecommendedRouteProvider = Provider<String?>((ref) {
  return ref.watch(driverStartupProvider).when(
    loading: () => null,
    error: (error, stack) => null,
    data: (info) => info.nextRoute,
  );
});
