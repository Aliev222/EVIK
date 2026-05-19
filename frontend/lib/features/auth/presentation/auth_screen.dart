import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/onboarding/presentation/screens/role_selection_screen.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({
    super.key,
    this.initialRole,
  });

  final UserRole? initialRole;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phoneController = TextEditingController();
  UserRole? _role;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        title: Text(
          'Вход в Tow Truck',
          style: EvikTypography.h2.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: IconButton(
          onPressed: () {
            ref.read(selectedOnboardingRoleProvider.notifier).state = null;
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_ios,
            color: EvikColors.primaryBlack,
            size: 20,
          ),
          splashRadius: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Вход в приложение', style: EvikTypography.h2),
              const SizedBox(height: 10),
              Text(
                'Введите номер телефона для входа или регистрации',
                style: EvikTypography.bodyLarge.copyWith(
                  color: EvikColors.gray600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 30),
              _PhoneInput(
                controller: _phoneController,
                onChanged: (_) => setState(() {}),
                isValid: _isPhoneValid(),
              ),
              const SizedBox(height: 8),
              _buildPhoneValidationHint(_phoneController.text),
              const SizedBox(height: 14),
              Expanded(
                child: Text(
                  'Мы отправим SMS с кодом подтверждения на этот номер',
                  style: EvikTypography.bodyLarge.copyWith(
                    color: EvikColors.gray600,
                    height: 1.35,
                  ),
                ),
              ),
              if (authState.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: EvikColors.errorRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: EvikColors.errorRed.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    authState.errorMessage!,
                    style: EvikTypography.bodySmall.copyWith(
                      color: EvikColors.errorRed,
                    ),
                  ),
                ),
              ],
              EvikButton(
                text: 'Получить код',
                onPressed: _isPhoneValid() && !authState.isLoading
                    ? _sendSmsCode
                    : null,
                isLoading: authState.isLoading,
                width: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isPhoneValid() {
    final digitsOnly = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    return digitsOnly.length == 11 && digitsOnly.startsWith('7');
  }

  Widget _buildPhoneValidationHint(String phone) {
    final isEmpty = phone.trim().isEmpty;
    final isValid = _isPhoneValid();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: isValid
          ? Row(
              key: const ValueKey('valid-phone'),
              children: [
                const Icon(
                  Icons.check_circle,
                  color: EvikColors.successGreen,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  'Номер корректный',
                  style: EvikTypography.bodySmall.copyWith(
                    color: EvikColors.successGreen,
                  ),
                ),
              ],
            )
          : Text(
              isEmpty
                  ? 'Введите номер в формате +7 (999) 123-45-67'
                  : 'Проверьте формат номера: +7 (999) 123-45-67',
              key: const ValueKey('invalid-phone'),
              style: EvikTypography.bodySmall.copyWith(
                color: EvikColors.gray700,
              ),
            ),
    );
  }

  void _sendSmsCode() {
    final role =
        _role ?? ref.read(selectedOnboardingRoleProvider) ?? UserRole.client;
    ref.read(authProvider.notifier).signInWithPhone(
          _phoneController.text.trim(),
          'User Name',
          role: role,
        );
  }
}

class _PhoneFormatter extends TextInputFormatter {
  int _limit(int value, int max) => value < max ? value : max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    if (digits.startsWith('8')) digits = '7${digits.substring(1)}';
    if (!digits.startsWith('7')) digits = '7$digits';
    if (digits.length > 11) digits = digits.substring(0, 11);

    final local = digits.length > 1 ? digits.substring(1) : '';
    final buffer = StringBuffer('+7');
    if (local.isNotEmpty) {
      buffer.write(' (');
      buffer.write(local.substring(0, _limit(local.length, 3)));
    }
    if (local.length >= 3) buffer.write(')');
    if (local.length > 3) {
      buffer.write(' ');
      buffer.write(local.substring(3, _limit(local.length, 6)));
    }
    if (local.length > 6) {
      buffer.write('-');
      buffer.write(local.substring(6, _limit(local.length, 8)));
    }
    if (local.length > 8) {
      buffer.write('-');
      buffer.write(local.substring(8, _limit(local.length, 10)));
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _PhoneInput extends StatelessWidget {
  const _PhoneInput({
    required this.controller,
    required this.onChanged,
    required this.isValid,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool isValid;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      height: 56,
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isValid ? EvikColors.accentOrange : EvikColors.gray200,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Text(
            'RU',
            style: EvikTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: EvikColors.primaryBlack,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 26, color: EvikColors.gray200),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.phone,
              onChanged: onChanged,
              inputFormatters: [_PhoneFormatter()],
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '+7 (999) 000-00-00',
                hintStyle: EvikTypography.bodyLarge.copyWith(
                  color: EvikColors.gray400,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              style: EvikTypography.bodyLarge.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
