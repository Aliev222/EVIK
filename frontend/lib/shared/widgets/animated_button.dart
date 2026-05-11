import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnimatedButton extends StatefulWidget {
  const AnimatedButton({
    super.key,
    required this.child,
    this.onPressed,
    this.duration = const Duration(milliseconds: 200),
    this.scaleValue = 0.96,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Duration duration;
  final double scaleValue;

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Listener(
        onPointerDown: (_) {
          HapticFeedback.lightImpact();
          _setPressed(true);
        },
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _isPressed ? widget.scaleValue : 1,
          duration: widget.duration,
          curve: _isPressed ? Curves.easeInOut : Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );
  }
}
