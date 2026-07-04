import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_onboarding.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_onboarding_provider.dart';
import 'document_camera_screen.dart';
import 'driver_profile_setup_screen.dart';

class DriverDocumentsScreen extends ConsumerWidget {
  const DriverDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingState = ref.watch(driverOnboardingProvider);

    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AvroDriverColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: 1 / 3,
                minHeight: 8,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: AvroDriverColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AvroDriverColors.accent),
              ),
              const SizedBox(height: 18),
              const Text(
                'Шаг 1 из 3',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AvroDriverColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Документы водителя',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AvroDriverColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Загрузите обязательные документы для проверки. Все изображения должны быть четкими и читаемыми.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: AvroDriverColors.textSecondary,
                ),
              ),
              if (onboardingState.errorMessage != null) ...[
                const SizedBox(height: 16),
                _ErrorBanner(message: onboardingState.errorMessage!),
              ],
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: DriverDocumentType.values
                      .map(
                        (type) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DocumentCard(
                            type: type,
                            document: onboardingState.documents[type],
                            isLoading: onboardingState.isLoading,
                            onTap: () => _openDocumentPicker(
                              context,
                              ref,
                              type,
                              onboardingState.documents[type],
                            ),
                            onClear: onboardingState.documents[type] == null
                                ? null
                                : () => ref
                                    .read(driverOnboardingProvider.notifier)
                                    .clearDocument(type),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: onboardingState.isDocumentsStepComplete
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const DriverProfileSetupScreen(),
                            ),
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AvroDriverColors.accent,
                    foregroundColor: AvroDriverColors.textPrimary,
                    disabledBackgroundColor: AvroDriverColors.tabInactive,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: onboardingState.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AvroDriverColors.textPrimary),
                          ),
                        )
                      : const Text(
                          'Далее',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDocumentPicker(
    BuildContext context,
    WidgetRef ref,
    DriverDocumentType type,
    DriverDocumentDraft? preview,
  ) async {
    final source = await Navigator.of(context).push<ImageSource>(
      MaterialPageRoute<ImageSource>(
        builder: (_) => DocumentCameraScreen(
          type: type,
          preview: preview,
        ),
      ),
    );

    if (source == null || !context.mounted) {
      return;
    }

    await ref
        .read(driverOnboardingProvider.notifier)
        .pickDocument(type, source: source);
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.type,
    required this.document,
    required this.isLoading,
    required this.onTap,
    required this.onClear,
  });

  final DriverDocumentType type;
  final DriverDocumentDraft? document;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final isUploaded = document != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AvroDriverColors.background,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isUploaded
                  ? AvroDriverColors.success
                  : AvroDriverColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _StatusBadge(isUploaded: isUploaded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AvroDriverColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isUploaded
                          ? 'Загружено • ${document!.width}x${document!.height}'
                          : type.ctaLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isUploaded
                            ? AvroDriverColors.success
                            : AvroDriverColors.textSecondary,
                      ),
                    ),
                    if (isUploaded) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 96,
                          width: double.infinity,
                          child: _DocumentPreviewThumb(document: document!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AvroDriverColors.textSecondary,
                  ),
                  if (onClear != null)
                    IconButton(
                      onPressed: isLoading ? null : onClear,
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: AvroDriverColors.textSecondary,
                      tooltip: 'Удалить',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isUploaded});

  final bool isUploaded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: isUploaded ? AvroDriverColors.success : AvroDriverColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        isUploaded ? Icons.check_circle_rounded : Icons.description_rounded,
        color:
            isUploaded ? AvroDriverColors.success : AvroDriverColors.textSecondary,
      ),
    );
  }
}

class _DocumentPreviewThumb extends StatelessWidget {
  const _DocumentPreviewThumb({required this.document});

  final DriverDocumentDraft document;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(document.file.path, fit: BoxFit.cover);
    }

    return Image.file(File(document.file.path), fit: BoxFit.cover);
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AvroDriverColors.error,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroDriverColors.error),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 14,
          height: 1.4,
          color: AvroDriverColors.textPrimary,
        ),
      ),
    );
  }
}
