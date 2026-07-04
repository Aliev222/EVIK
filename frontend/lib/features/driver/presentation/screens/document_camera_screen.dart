import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_onboarding.dart';

class DocumentCameraScreen extends StatelessWidget {
  const DocumentCameraScreen({
    super.key,
    required this.type,
    this.preview,
  });

  final DriverDocumentType type;
  final DriverDocumentDraft? preview;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AvroDriverColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AvroDriverColors.textPrimary,
        elevation: 0,
        title: Text(type.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AvroDriverColors.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Как загрузить документ',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AvroDriverColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Сделайте четкий снимок документа целиком без бликов и обрезанных углов. Можно открыть камеру или выбрать фото из галереи.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AvroDriverColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AvroDriverColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AvroDriverColors.border),
                  ),
                  child: preview == null
                      ? const _EmptyPreview()
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: _DocumentPreviewImage(preview: preview!),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(ImageSource.camera),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AvroDriverColors.accent,
                    foregroundColor: AvroDriverColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: const Text(
                    'Открыть камеру',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(ImageSource.gallery),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AvroDriverColors.textPrimary,
                    side: const BorderSide(color: AvroDriverColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text(
                    'Выбрать из галереи',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_rounded,
              size: 60,
              color: AvroDriverColors.textSecondary,
            ),
            SizedBox(height: 12),
            Text(
              'Превью появится после выбора фото',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AvroDriverColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentPreviewImage extends StatelessWidget {
  const _DocumentPreviewImage({required this.preview});

  final DriverDocumentDraft preview;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(preview.file.path, fit: BoxFit.cover);
    }

    return Image.file(File(preview.file.path), fit: BoxFit.cover);
  }
}
