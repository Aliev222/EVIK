import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors, AvroDriverColors;
import 'package:tow_truck_frontend/core/config/build_flags.dart';
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

final bool _kTestLogin = developmentFeatureEnabled(
  requested: const bool.fromEnvironment('EVIK_TEST_LOGIN'),
  releaseMode: kReleaseMode,
);

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  UserRole? _role;
  bool _testPasswordMode = false;
  bool _phoneWasTouched = false;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _phoneFocusNode.addListener(() {
      if (!_phoneFocusNode.hasFocus) setState(() => _phoneWasTouched = true);
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final role = _role ?? ref.watch(selectedOnboardingRoleProvider);
    final isDriver = role == UserRole.driver;
    final background =
        isDriver ? AvroDriverColors.background : AvroClientColors.background;
    final primary =
        isDriver ? AvroDriverColors.textPrimary : AvroClientColors.textPrimary;
    final secondary = isDriver
        ? AvroDriverColors.textSecondary
        : AvroClientColors.textSecondary;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () {
                    ref.read(selectedOnboardingRoleProvider.notifier).state =
                        null;
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: primary),
                  tooltip: 'Назад',
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 42),
                      Text(
                        'Ваш номер телефона',
                        style: EvikTypography.h1.copyWith(
                          color: primary,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Отправим SMS с кодом для входа или регистрации.',
                        style: EvikTypography.bodyLarge.copyWith(
                          color: secondary,
                          fontSize: 17,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _PhoneInput(
                        controller: _phoneController,
                        focusNode: _phoneFocusNode,
                        onChanged: (_) => setState(() {}),
                        isValid: _isPhoneValid(),
                        isFocused: _phoneFocusNode.hasFocus,
                        isDark: isDriver,
                        onSubmit: (_) => _submitIfPossible(authState),
                      ),
                      if (_phoneWasTouched && !_isPhoneValid()) ...[
                        const SizedBox(height: 8),
                        _buildPhoneValidationHint(
                          _phoneController.text,
                          color: secondary,
                        ),
                      ],
                      if (_kTestLogin && _testPasswordMode) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Пароль',
                            hintText: 'Минимум 8 символов',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (_kTestLogin) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(
                            () => _testPasswordMode = !_testPasswordMode,
                          ),
                          child: Text(
                            _testPasswordMode
                                ? 'Вернуться к входу по SMS'
                                : 'Тестовый вход по паролю',
                          ),
                        ),
                      ],
                      if (authState.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _AuthError(message: authState.errorMessage!),
                      ],
                    ],
                  ),
                ),
              ),
              _ThemedAuthButton(
                isDark: isDriver,
                child: EvikButton(
                  text: _testPasswordMode ? 'Войти по паролю' : 'Получить код',
                  onPressed: _isPhoneValid() &&
                          !authState.isLoading &&
                          _actionEnabled()
                      ? () => _submitIfPossible(authState)
                      : null,
                  isLoading: authState.isLoading,
                  width: double.infinity,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isPhoneValid() {
    final digitsOnly = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    return digitsOnly.length == 10;
  }

  String _normalizedPhone() =>
      '+7${_phoneController.text.replaceAll(RegExp(r'[^\d]'), '')}';

  Widget _buildPhoneValidationHint(String phone, {required Color color}) {
    return Text(
      phone.trim().isEmpty
          ? 'Введите номер телефона.'
          : 'Введите номер полностью.',
      style: EvikTypography.bodySmall.copyWith(color: color),
    );
  }

  void _submitIfPossible(AuthState authState) {
    if (!_isPhoneValid() || authState.isLoading || !_actionEnabled()) return;
    _testPasswordMode ? _signInWithPassword() : _sendSmsCode();
  }

  void _sendSmsCode() {
    final role =
        _role ?? ref.read(selectedOnboardingRoleProvider) ?? UserRole.client;
    ref.read(authProvider.notifier).signInWithPhone(
          _normalizedPhone(),
          role: role,
        );
  }

  bool _actionEnabled() {
    if (!_testPasswordMode) return true;
    return _passwordController.text.trim().length >= 8;
  }

  void _signInWithPassword() {
    final role =
        _role ?? ref.read(selectedOnboardingRoleProvider) ?? UserRole.client;
    ref.read(authProvider.notifier).signInWithPassword(
          _normalizedPhone(),
          _passwordController.text,
          role: role,
        );
  }
}

class _AuthError extends StatelessWidget {
  const _AuthError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AvroClientColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message),
      );
}

class _ThemedAuthButton extends StatelessWidget {
  const _ThemedAuthButton({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          disabledColor: isDark ? AvroDriverColors.border : null,
        ),
        child: child,
      );
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
    if (digits.length == 11 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) digits = digits.substring(0, 10);

    final buffer = StringBuffer();
    if (digits.isNotEmpty) {
      buffer.write(' (');
      buffer.write(digits.substring(0, _limit(digits.length, 3)));
    }
    if (digits.length >= 3) buffer.write(')');
    if (digits.length > 3) {
      buffer.write(' ');
      buffer.write(digits.substring(3, _limit(digits.length, 6)));
    }
    if (digits.length > 6) {
      buffer.write('-');
      buffer.write(digits.substring(6, _limit(digits.length, 8)));
    }
    if (digits.length > 8) {
      buffer.write('-');
      buffer.write(digits.substring(8, _limit(digits.length, 10)));
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
    required this.focusNode,
    required this.onChanged,
    required this.isValid,
    required this.isFocused,
    required this.isDark,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool isValid;
  final bool isFocused;
  final bool isDark;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      height: 64,
      decoration: BoxDecoration(
        color: isDark ? AvroDriverColors.surface : AvroClientColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFocused || isValid
              ? AvroClientColors.accent
              : isDark
                  ? AvroDriverColors.border
                  : AvroClientColors.surface,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Text(
            '+7',
            style: EvikTypography.bodyMedium.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AvroDriverColors.textPrimary
                  : AvroClientColors.textPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 1,
            height: 28,
            color: isDark ? AvroDriverColors.border : AvroClientColors.surface,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.phone,
              onChanged: onChanged,
              onFieldSubmitted: onSubmit,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [_PhoneFormatter()],
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '(999) 000-00-00',
                hintStyle: EvikTypography.bodyLarge.copyWith(
                  color: isDark
                      ? AvroDriverColors.textSecondary
                      : AvroClientColors.textMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
              style: EvikTypography.bodyLarge.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AvroDriverColors.textPrimary
                    : AvroClientColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
