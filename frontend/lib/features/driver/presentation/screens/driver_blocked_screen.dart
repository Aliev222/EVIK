import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_verification_provider.dart';

/// Экран `/driver/blocked`: показывается ТОЛЬКО водителю с заблокированной
/// верификацией. Блокировка «липкая» — backend отказывает в переподаче
/// (403), поэтому здесь есть только контакт поддержки и нет пути
/// «Исправить и переотправить документы».
class DriverBlockedScreen extends ConsumerWidget {
  const DriverBlockedScreen({super.key, this.reason});

  /// Причина блокировки, переданная извне. Если не задана, экран подтянет её
  /// из статуса верификации (admin_comments).
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? resolvedReason = reason;
    if (resolvedReason == null) {
      final userId = ref.watch(currentUserProvider)?.id;
      if (userId != null) {
        final statusAsync =
            ref.watch(autoRefreshingVerificationStatusProvider(userId));
        resolvedReason = statusAsync.valueOrNull?.adminComments;
      }
    }

    final reasonText = resolvedReason?.trim();
    final showReason = reasonText != null && reasonText.isNotEmpty;

    return Scaffold(
      backgroundColor: AvroDriverColors.documentBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AvroDriverColors.documentDivider,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.block_rounded,
                        size: 38,
                        color: AvroDriverColors.error,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Аккаунт заблокирован',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AvroDriverColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Переподача документов недоступна. Чтобы разобраться '
                      'в ситуации, обратитесь в поддержку — мы подскажем, '
                      'как восстановить доступ.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: AvroDriverColors.border,
                      ),
                    ),
                    if (showReason) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AvroDriverColors.documentCard,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          reasonText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: AvroDriverColors.darkBlue,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => _contactSupport(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AvroDriverColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.mail_outline_rounded, size: 20),
                        label: const Text(
                          'Обратиться в поддержку',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _contactSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      queryParameters: {
        'subject': 'Заблокирован аккаунт водителя',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось открыть поддержку на этом устройстве.'),
      ),
    );
  }
}
