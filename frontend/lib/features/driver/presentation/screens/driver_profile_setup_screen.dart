import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_onboarding.dart';
import 'package:tow_truck_frontend/features/order/domain/entities/order.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_onboarding_provider.dart';

class DriverProfileSetupScreen extends ConsumerStatefulWidget {
  const DriverProfileSetupScreen({super.key});

  @override
  ConsumerState<DriverProfileSetupScreen> createState() =>
      _DriverProfileSetupScreenState();
}

class _DriverProfileSetupScreenState
    extends ConsumerState<DriverProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _vehicleModelController;
  late final TextEditingController _vehicleNumberController;
  bool _didHydrate = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController();
    _vehicleModelController = TextEditingController();
    _vehicleNumberController = TextEditingController();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _vehicleModelController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(currentUserProvider);
    final onboardingState = ref.watch(driverOnboardingProvider);

    _hydrateInitialValues(authUser?.fullName ?? '', onboardingState);

    return Scaffold(
      backgroundColor: AvroDriverColors.documentBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AvroDriverColors.darkBlue,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: 2 / 3,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: AvroDriverColors.documentCard,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AvroDriverColors.accent),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Шаг 2 из 3',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AvroDriverColors.border,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Профиль водителя',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AvroDriverColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Заполните данные машины и добавьте селфи. Эти материалы увидит модератор, а фото профиля будет показано клиентам после одобрения.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: AvroDriverColors.border,
                  ),
                ),
                if (onboardingState.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _ProfileErrorBanner(message: onboardingState.errorMessage!),
                ],
                if (onboardingState.isLoading &&
                    onboardingState.uploadStatusMessage != null) ...[
                  const SizedBox(height: 16),
                  _UploadProgressCard(
                    progress: onboardingState.uploadProgress,
                    message: onboardingState.uploadStatusMessage!,
                  ),
                ],
                const SizedBox(height: 18),
                Expanded(
                  child: ListView(
                    children: [
                      TextFormField(
                        controller: _fullNameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'ФИО',
                          hintText: 'Иванов Иван Иванович',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().length < 2) {
                            return 'Введите ФИО водителя';
                          }
                          return null;
                        },
                        onChanged: (value) => ref
                            .read(driverOnboardingProvider.notifier)
                            .updateProfileDraft(fullName: value),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _vehicleModelController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Модель машины',
                          hintText: 'Hyundai HD78',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.local_shipping_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().length < 2) {
                            return 'Введите модель машины';
                          }
                          return null;
                        },
                        onChanged: (value) => ref
                            .read(driverOnboardingProvider.notifier)
                            .updateProfileDraft(vehicleModel: value),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _vehicleNumberController,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-zА-Яа-я0-9]'),
                          ),
                          _VehicleNumberFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Номер машины',
                          hintText: 'А000АА00',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                        validator: (value) {
                          final plate = _normalizedPlate(value ?? '');
                          if (plate.length != 8) {
                            return 'Введите номер в формате А000АА00';
                          }
                          return null;
                        },
                        onChanged: (value) => ref
                            .read(driverOnboardingProvider.notifier)
                            .updateProfileDraft(vehicleNumber: value),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<VehicleType>(
                        initialValue: onboardingState.vehicleType,
                        decoration: const InputDecoration(
                          labelText: 'Тип эвакуатора',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.tune_rounded),
                        ),
                        items: VehicleType.values
                            .map(
                              (type) => DropdownMenuItem<VehicleType>(
                                value: type,
                                child: Text(type.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          ref
                              .read(driverOnboardingProvider.notifier)
                              .updateProfileDraft(vehicleType: value);
                        },
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Селфи водителя',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AvroDriverColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Сделайте селфи с лицом по центру. На экране ниже фото отображается в круглом crop-preview.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: AvroDriverColors.border,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SelfieCard(
                        selfie: onboardingState.selfie,
                        isLoading: onboardingState.isLoading,
                        onPick: () => ref
                            .read(driverOnboardingProvider.notifier)
                            .pickSelfie(),
                        onClear: onboardingState.selfie == null
                            ? null
                            : () => ref
                                .read(driverOnboardingProvider.notifier)
                                .clearSelfie(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: onboardingState.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AvroDriverColors.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AvroDriverColors.documentDisabled,
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
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Отправить на проверку',
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
      ),
    );
  }

  void _hydrateInitialValues(
    String authFullName,
    DriverOnboardingState onboardingState,
  ) {
    if (_didHydrate) {
      return;
    }

    final initialFullName = onboardingState.fullName.isNotEmpty
        ? onboardingState.fullName
        : authFullName;

    _fullNameController.text = initialFullName;
    _vehicleModelController.text = onboardingState.vehicleModel;
    _vehicleNumberController.text = onboardingState.vehicleNumber;
    _didHydrate = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(driverOnboardingProvider.notifier).updateProfileDraft(
            fullName: initialFullName,
            vehicleModel: onboardingState.vehicleModel,
            vehicleNumber: onboardingState.vehicleNumber,
            vehicleType: onboardingState.vehicleType,
          );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }

    final success = await ref
        .read(driverOnboardingProvider.notifier)
        .submitForModeration(user.id);
    if (!success || !mounted) {
      return;
    }

    Navigator.of(context).popUntil(
      (route) => route.isFirst,
    );
  }

  String _normalizedPlate(String value) {
    return value.replaceAll(RegExp(r'[^A-ZА-Я0-9]'), '').toUpperCase();
  }
}

class _UploadProgressCard extends StatelessWidget {
  const _UploadProgressCard({
    required this.progress,
    required this.message,
  });

  final double progress;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroDriverColors.documentBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AvroDriverColors.darkBlue,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress <= 0 ? null : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: AvroDriverColors.documentCard,
            valueColor: const AlwaysStoppedAnimation<Color>(AvroDriverColors.accent),
          ),
        ],
      ),
    );
  }
}

class _SelfieCard extends StatelessWidget {
  const _SelfieCard({
    required this.selfie,
    required this.isLoading,
    required this.onPick,
    required this.onClear,
  });

  final DriverImageDraft? selfie;
  final bool isLoading;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AvroDriverColors.documentBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AvroDriverColors.documentBorder,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: selfie == null
                  ? const ColoredBox(
                      color: AvroDriverColors.documentDivider,
                      child: Icon(
                        Icons.face_rounded,
                        size: 60,
                        color: AvroDriverColors.border,
                      ),
                    )
                  : _SelfiePreview(selfie: selfie!),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            selfie == null
                ? 'Селфи еще не добавлено'
                : 'Селфи готово • ${selfie!.width}x${selfie!.height}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AvroDriverColors.darkBlue,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onPick,
              style: ElevatedButton.styleFrom(
                backgroundColor: AvroDriverColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.photo_camera_front_rounded),
              label: Text(
                selfie == null ? 'Сделать селфи' : 'Переснять селфи',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: isLoading ? null : onClear,
              child: const Text('Удалить фото'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelfiePreview extends StatelessWidget {
  const _SelfiePreview({required this.selfie});

  final DriverImageDraft selfie;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(selfie.file.path, fit: BoxFit.cover);
    }

    return Image.file(File(selfie.file.path), fit: BoxFit.cover);
  }
}

class _ProfileErrorBanner extends StatelessWidget {
  const _ProfileErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AvroDriverColors.errorBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AvroDriverColors.errorBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 14,
          height: 1.4,
          color: AvroDriverColors.errorText,
        ),
      ),
    );
  }
}

class _VehicleNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text
        .replaceAll(RegExp(r'[^A-Za-zА-Яа-я0-9]'), '')
        .toUpperCase();

    final chars = raw.characters.take(8).toList();
    final buffer = StringBuffer();

    for (var index = 0; index < chars.length; index++) {
      buffer.write(chars[index]);
      if (index == 0 || index == 3 || index == 5) {
        buffer.write(' ');
      }
    }

    final formatted = buffer.toString().trimRight();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
