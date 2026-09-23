import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors, AvroDriverColors;
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/auth/domain/entities/user.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

class SmsVerificationScreen extends ConsumerStatefulWidget {
  const SmsVerificationScreen({super.key});

  @override
  ConsumerState<SmsVerificationScreen> createState() =>
      _SmsVerificationScreenState();
}

class _SmsVerificationScreenState extends ConsumerState<SmsVerificationScreen> {
  static const _codeLength = 6;

  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  int _timerKey = 0;
  bool _hasCodeError = false;
  String get _smsCode => _codeController.text;
  bool get _isComplete => _smsCode.length == _codeLength;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (!mounted) return;
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        _showCodeError();
      }
    });

    final authState = ref.watch(authProvider);
    final isDriver = authState.pendingRole == UserRole.driver;
    final background =
        isDriver ? AvroDriverColors.background : AvroClientColors.background;
    final primary =
        isDriver ? AvroDriverColors.textPrimary : AvroClientColors.textPrimary;
    final secondary = isDriver
        ? AvroDriverColors.textSecondary
        : AvroClientColors.textSecondary;
    final phoneNumber = authState.phoneNumber ?? '+7 (999) 000-00-00';
    final hasError = _hasCodeError || authState.errorMessage != null;

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
                    ref.read(authProvider.notifier).resetAuth();
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: primary),
                  tooltip: 'Назад',
                ),
              ),
              const SizedBox(height: 42),
              Text(
                'Введите код из SMS',
                style: EvikTypography.h1.copyWith(
                  color: primary,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Отправлен на $phoneNumber',
                style: EvikTypography.bodyLarge.copyWith(
                  color: secondary,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 32),
              _CodeInput(
                controller: _codeController,
                focusNode: _codeFocusNode,
                onChanged: _onCodeChanged,
                hasError: hasError,
                isDark: isDriver,
              ),
              if (hasError) ...[
                const SizedBox(height: 10),
                Text(
                  authState.errorMessage ??
                      'Неверный код. Проверьте SMS и попробуйте снова.',
                  textAlign: TextAlign.center,
                  style: EvikTypography.bodyMedium.copyWith(
                    color: isDriver
                        ? const Color(0xFFFFA4A1)
                        : AvroClientColors.errorDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Center(
                child: _CountdownTimer(
                  key: ValueKey(_timerKey),
                  totalSeconds: 75,
                  onFinished: _resendCode,
                ),
              ),
              const Spacer(),
              EvikButton(
                text: 'Войти',
                onPressed:
                    _isComplete && !authState.isLoading ? _verifySmsCode : null,
                isLoading: authState.isLoading,
                width: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCodeChanged(String value) {
    setState(() => _hasCodeError = false);

    if (_isComplete) {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _isComplete) _verifySmsCode();
      });
    }
  }

  void _showCodeError() {
    setState(() => _hasCodeError = true);
    Future<void>.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _hasCodeError = false);
    });
  }

  void _resendCode() {
    ref.read(authProvider.notifier).resendSmsCode();
    setState(() {
      _timerKey++;
      _hasCodeError = false;
      _codeController.clear();
    });
    _codeFocusNode.requestFocus();
  }

  void _verifySmsCode() {
    if (_isComplete) {
      ref.read(authProvider.notifier).verifySmsCode(_smsCode);
    } else {
      _showCodeError();
    }
  }
}

class _CodeInput extends StatelessWidget {
  const _CodeInput({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hasError,
    required this.isDark,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool hasError;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: AnimatedBuilder(
        animation: focusNode,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final boxWidth = (constraints.maxWidth - (gap * 5)) / 6;
            final code = controller.text;
            final activeIndex = code.length.clamp(0, 5);
            final textColor = isDark
                ? AvroDriverColors.textPrimary
                : AvroClientColors.textPrimary;
            final emptyBorder =
                isDark ? AvroDriverColors.border : AvroClientColors.surface;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: focusNode.requestFocus,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: List.generate(6, (index) {
                      final isActive = index == activeIndex;
                      final borderColor = hasError
                          ? AvroClientColors.error
                          : isActive && focusNode.hasFocus
                              ? AvroClientColors.accent
                              : emptyBorder;
                      return Container(
                        width: boxWidth,
                        height: 60,
                        margin: EdgeInsets.only(right: index < 5 ? gap : 0),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: borderColor,
                            width: isActive ? 2.2 : 1.5,
                          ),
                        ),
                        child: index < code.length
                            ? Text(
                                code[index],
                                style: EvikTypography.h3.copyWith(
                                  color: textColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      );
                    }),
                  ),
                  Opacity(
                    opacity: 0.01,
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: onChanged,
                      textInputAction: TextInputAction.done,
                      decoration:
                          const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CountdownTimer extends StatefulWidget {
  final int totalSeconds;
  final VoidCallback onFinished;
  const _CountdownTimer(
      {super.key, required this.totalSeconds, required this.onFinished});

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.totalSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        widget.onFinished();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft > 0) {
      final minutes = (_secondsLeft / 60).floor();
      final seconds = _secondsLeft % 60;
      final timeText =
          '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

      return RichText(
        text: TextSpan(
          style: EvikTypography.bodyLarge
              .copyWith(color: AvroClientColors.textSecondary),
          children: [
            const TextSpan(text: 'Повторить через '),
            TextSpan(
              text: timeText,
              style: EvikTypography.bodyLarge.copyWith(
                color: AvroClientColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onFinished,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Отправить повторно',
              style: EvikTypography.bodyLarge.copyWith(
                color: AvroClientColors.accentStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
