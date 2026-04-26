import 'package:flutter/material.dart';
import '../../core/theme/evik_colors.dart';
import '../../core/theme/evik_typography.dart';
import 'animated_button.dart';

enum EvikButtonVariant {
  primary,
  secondary,
  ghost,
  danger,
  green,
  dark,
}

class EvikButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final EvikButtonVariant variant;
  final bool isLoading;
  final Widget? icon;
  final bool small;
  final double? width;

  const EvikButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = EvikButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.small = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = !isLoading && onPressed != null;

    return AnimatedButton(
      onPressed: enabled ? onPressed : null,
      child: SizedBox(
        width: width,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: _getButtonStyle(),
          child: isLoading ? _buildLoader() : _buildContent(),
        ),
      ),
    );
  }

  ButtonStyle _getButtonStyle() {
    final padding = small
        ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 24, vertical: 16);

    final textStyle =
        small ? EvikTypography.buttonTextSmall : EvikTypography.buttonText;
    final borderRadius = BorderRadius.circular(14);

    switch (variant) {
      case EvikButtonVariant.primary:
        return ElevatedButton.styleFrom(
          backgroundColor: EvikColors.accentOrange,
          foregroundColor: EvikColors.primaryWhite,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: textStyle,
        ).copyWith(
          overlayColor: WidgetStateProperty.all(Colors.black12),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return EvikColors.gray300;
            }
            return EvikColors.accentOrange;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return EvikColors.gray500;
            }
            return EvikColors.primaryWhite;
          }),
        );

      case EvikButtonVariant.secondary:
        return OutlinedButton.styleFrom(
          foregroundColor: EvikColors.accentOrange,
          backgroundColor: Colors.transparent,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          side: const BorderSide(color: EvikColors.accentOrange, width: 2),
          textStyle: textStyle,
        );

      case EvikButtonVariant.ghost:
        return ElevatedButton.styleFrom(
          backgroundColor: EvikColors.gray100,
          foregroundColor: EvikColors.primaryBlack,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: textStyle,
        );

      case EvikButtonVariant.danger:
        return ElevatedButton.styleFrom(
          backgroundColor: EvikColors.errorRed,
          foregroundColor: EvikColors.primaryWhite,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: textStyle,
        );

      case EvikButtonVariant.green:
        return ElevatedButton.styleFrom(
          backgroundColor: EvikColors.successGreen,
          foregroundColor: EvikColors.primaryWhite,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: textStyle,
        );

      case EvikButtonVariant.dark:
        return ElevatedButton.styleFrom(
          backgroundColor: EvikColors.primaryBlack,
          foregroundColor: EvikColors.primaryWhite,
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: textStyle,
        );
    }
  }

  Widget _buildContent() {
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon!,
          const SizedBox(width: 8),
          Text(text),
        ],
      );
    }
    return Text(text);
  }

  Widget _buildLoader() {
    final color = variant == EvikButtonVariant.secondary
        ? EvikColors.accentOrange
        : EvikColors.primaryWhite;
    return SizedBox(
      height: small ? 14 : 16,
      width: small ? 14 : 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
