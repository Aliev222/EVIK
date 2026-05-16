import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';

class SmsVerificationScreen extends ConsumerStatefulWidget {
  const SmsVerificationScreen({super.key});

  @override
  ConsumerState<SmsVerificationScreen> createState() =>
      _SmsVerificationScreenState();
}

class _SmsVerificationScreenState extends ConsumerState<SmsVerificationScreen> {
  static const _codeLength = 6;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  Timer? _resendTimer;
  int _secondsLeft = 75;
  bool _hasCodeError = false;

  String get _smsCode =>
      _controllers.map((controller) => controller.text).join();
  bool get _isComplete => _smsCode.length == _codeLength;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_codeLength, (_) => TextEditingController());
    _focusNodes = List.generate(_codeLength, (_) => FocusNode());

    for (int i = 0; i < _codeLength; i++) {
      _controllers[i].addListener(() => _onCodeChanged(i));
    }

    _startResendTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        _showCodeError();
      }
    });

    final authState = ref.watch(authProvider);
    final phoneNumber = authState.phoneNumber ?? '+7 (999) 000-00-00';
    final hasError = _hasCodeError || authState.errorMessage != null;

    return Scaffold(
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        title: Text(
          'Подтверждение',
          style: EvikTypography.h2.copyWith(fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: IconButton(
          onPressed: () {
            ref.read(authProvider.notifier).resetAuth();
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
              Text('Введите код из SMS', style: EvikTypography.h2),
              const SizedBox(height: 10),
              Text(
                'Отправлен на $phoneNumber',
                style: EvikTypography.bodyLarge
                    .copyWith(color: EvikColors.gray600),
              ),
              const SizedBox(height: 26),
              _CodeInput(
                controllers: _controllers,
                focusNodes: _focusNodes,
                onChanged: _onCodeChanged,
                hasError: hasError,
              ),
              if (hasError) ...[
                const SizedBox(height: 10),
                Text(
                  authState.errorMessage ??
                      'Неверный код. Проверьте SMS и попробуйте снова.',
                  textAlign: TextAlign.center,
                  style: EvikTypography.bodySmall.copyWith(
                    color: EvikColors.errorRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Center(child: _buildTimerOrResend()),
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

  Widget _buildTimerOrResend() {
    if (_secondsLeft > 0) {
      final minutes = (_secondsLeft / 60).floor();
      final seconds = _secondsLeft % 60;
      final timeText =
          '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

      return RichText(
        text: TextSpan(
          style: EvikTypography.bodyLarge.copyWith(color: EvikColors.gray600),
          children: [
            const TextSpan(text: 'Повторить через '),
            TextSpan(
              text: timeText,
              style: EvikTypography.bodyLarge.copyWith(
                color: EvikColors.primaryBlack,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _resendCode,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Отправить повторно',
          style: EvikTypography.bodyLarge.copyWith(
            color: EvikColors.accentOrange,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _onCodeChanged(int index) {
    if (_hasCodeError) _hasCodeError = false;
    final text = _controllers[index].text;
    if (text.isNotEmpty && index < _codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    if (_isComplete) {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _isComplete) _verifySmsCode();
      });
    }

    setState(() {});
  }

  void _showCodeError() {
    setState(() => _hasCodeError = true);
    Future<void>.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _hasCodeError = false);
    });
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel();
      }
    });
  }

  void _resendCode() {
    ref.read(authProvider.notifier).resendSmsCode();
    setState(() {
      _secondsLeft = 75;
      _hasCodeError = false;
    });
    _startResendTimer();
  }

  void _verifySmsCode() {
    if (_isComplete) {
      ref.read(authProvider.notifier).verifySmsCode(_smsCode);
    } else {
      _showCodeError();
    }
  }
}

class _CodeInput extends StatefulWidget {
  const _CodeInput({
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
    required this.hasError,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(int index) onChanged;
  final bool hasError;

  @override
  State<_CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<_CodeInput> {
  @override
  void initState() {
    super.initState();
    for (final focusNode in widget.focusNodes) {
      focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    for (final focusNode in widget.focusNodes) {
      focusNode.removeListener(_handleFocusChanged);
    }
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final filled = widget.controllers[index].text.isNotEmpty;
        final focused = widget.focusNodes[index].hasFocus;
        final borderColor = widget.hasError
            ? EvikColors.errorRed
            : focused || filled
                ? EvikColors.accentOrange
                : EvikColors.gray200;
        final fillColor = widget.hasError
            ? EvikColors.errorRed.withValues(alpha: 0.08)
            : filled || focused
                ? EvikColors.accentOrange.withValues(alpha: 0.08)
                : EvikColors.primaryWhite;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: 52,
          height: 60,
          margin: EdgeInsets.only(right: index < 5 ? 10 : 0),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: focused ? 2.4 : 2),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: EvikColors.accentOrange.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: TextFormField(
            controller: widget.controllers[index],
            focusNode: widget.focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(1),
            ],
            onChanged: (value) {
              if (value.isNotEmpty) widget.onChanged(index);
            },
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
            style: EvikTypography.h3.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }),
    );
  }
}
