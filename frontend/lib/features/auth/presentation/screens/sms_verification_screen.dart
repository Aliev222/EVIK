import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart'
    show AvroClientColors;
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
  int _timerKey = 0;
  bool _hasCodeError = false;
  bool _distributingCode = false;

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
      // Pressing backspace on an empty digit box returns focus to the previous
      // box (standard OTP UX).
      _focusNodes[i].onKeyEvent = (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            i > 0 &&
            _controllers[i].text.isEmpty) {
          _focusNodes[i - 1].requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
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
      if (!mounted) return;
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        _showCodeError();
      }
    });

    final authState = ref.watch(authProvider);
    final phoneNumber = authState.phoneNumber ?? '+7 (999) 000-00-00';
    final hasError = _hasCodeError || authState.errorMessage != null;

    return Scaffold(
      backgroundColor: AvroClientColors.background,
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
            color: AvroClientColors.textPrimary,
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
                    .copyWith(color: AvroClientColors.textSecondary),
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
                  style: EvikTypography.bodyMedium.copyWith(
                    color: AvroClientColors.errorDeep,
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

  void _onCodeChanged(int index) {
    if (_hasCodeError) {
      setState(() => _hasCodeError = false);
    }
    if (_distributingCode) return;

    final text = _controllers[index].text;

    // A pasted / autofilled code arrives as several digits in a single box.
    // Fan it out across the digit boxes (count capped at the boxes left).
    if (text.length > 1) {
      _distributingCode = true;
      final count = text.length <= _codeLength - index
          ? text.length
          : _codeLength - index;
      for (int i = 0; i < count; i++) {
        _controllers[index + i].text = text[i];
      }
      _distributingCode = false;
      final lastIndex = index + count - 1;
      _focusNodes[lastIndex].requestFocus();
    } else if (text.isNotEmpty && index < _codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }

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
    });
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
  int? _focusedIndex;
  late List<bool> _filledStates;
  late List<VoidCallback> _textListeners;
  late List<VoidCallback> _focusListeners;

  @override
  void initState() {
    super.initState();
    _filledStates = widget.controllers.map((c) => c.text.isNotEmpty).toList();
    _textListeners =
        List.generate(widget.controllers.length, _createTextListener);
    _focusListeners =
        List.generate(widget.controllers.length, _createFocusListener);
    for (int i = 0; i < widget.controllers.length; i++) {
      widget.controllers[i].addListener(_textListeners[i]);
      widget.focusNodes[i].addListener(_focusListeners[i]);
    }
  }

  VoidCallback _createTextListener(int index) {
    return () {
      if (mounted) {
        setState(() =>
            _filledStates[index] = widget.controllers[index].text.isNotEmpty);
      }
    };
  }

  VoidCallback _createFocusListener(int index) {
    return () {
      if (!mounted) return;
      setState(() {
        if (widget.focusNodes[index].hasFocus) {
          _focusedIndex = index;
        } else if (_focusedIndex == index) {
          _focusedIndex = null;
        }
      });
    };
  }

  @override
  void dispose() {
    for (int i = 0; i < widget.controllers.length; i++) {
      widget.controllers[i].removeListener(_textListeners[i]);
      widget.focusNodes[i].removeListener(_focusListeners[i]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (index) {
          final filled = _filledStates[index];
          final focused = _focusedIndex == index;
          final borderColor = widget.hasError
              ? AvroClientColors.error
              : focused || filled
                  ? AvroClientColors.accent
                  : AvroClientColors.surface;
          final fillColor = widget.hasError
              ? AvroClientColors.error.withValues(alpha: 0.08)
              : filled || focused
                  ? AvroClientColors.accent.withValues(alpha: 0.08)
                  : AvroClientColors.background;

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
                        color: AvroClientColors.accent.withValues(alpha: 0.16),
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
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction:
                  index == 5 ? TextInputAction.done : TextInputAction.next,
              // No length limit here: a pasted/autofilled full code arrives in a
              // single box and is fanned out by the parent.
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (value) {
                if (value.isNotEmpty) widget.onChanged(index);
              },
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
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
