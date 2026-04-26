import 'package:flutter/material.dart';
import '../../core/theme/evik_colors.dart';

class EvikAvatar extends StatelessWidget {
  final String? name;
  final String? imageUrl;
  final double size;
  final Color backgroundColor;
  final Color textColor;

  const EvikAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.size = 44,
    this.backgroundColor = EvikColors.accentOrange,
    this.textColor = EvikColors.primaryWhite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildInitials(),
      );
    }
    return _buildInitials();
  }

  Widget _buildInitials() {
    final initial = name?.isNotEmpty == true ? name![0].toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.35,
            fontWeight: FontWeight.w700,
            color: textColor,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }

  // Фабричные методы для стандартных размеров
  factory EvikAvatar.small(String? name, {String? imageUrl}) => EvikAvatar(
    name: name,
    imageUrl: imageUrl,
    size: 32,
  );

  factory EvikAvatar.medium(String? name, {String? imageUrl}) => EvikAvatar(
    name: name,
    imageUrl: imageUrl,
    size: 44,
  );

  factory EvikAvatar.large(String? name, {String? imageUrl}) => EvikAvatar(
    name: name,
    imageUrl: imageUrl,
    size: 64,
  );

  // Цветные варианты
  factory EvikAvatar.black(String? name, {String? imageUrl, double? size}) => EvikAvatar(
    name: name,
    imageUrl: imageUrl,
    size: size ?? 44,
    backgroundColor: EvikColors.primaryBlack,
    textColor: EvikColors.primaryWhite,
  );

  factory EvikAvatar.gray(String? name, {String? imageUrl, double? size}) => EvikAvatar(
    name: name,
    imageUrl: imageUrl,
    size: size ?? 44,
    backgroundColor: EvikColors.gray300,
    textColor: EvikColors.primaryBlack,
  );
}