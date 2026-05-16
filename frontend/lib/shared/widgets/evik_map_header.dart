import 'package:flutter/material.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'evik_avatar.dart';

class EvikMapHeader extends StatelessWidget {
  final String locationText;
  final String? userName;
  final String? userAvatarUrl;
  final VoidCallback? onProfileTap;
  final VoidCallback? onLocationTap;

  const EvikMapHeader({
    super.key,
    required this.locationText,
    this.userName,
    this.userAvatarUrl,
    this.onProfileTap,
    this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 14,
      right: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Location pill (точно как в дизайне)
          GestureDetector(
            onTap: onLocationTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: EvikColors.primaryWhite,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: EvikColors.accentOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    locationText,
                    style: EvikTypography.bodyMedium.copyWith(
                      color: EvikColors.primaryBlack,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Avatar (черный как в дизайне)
          GestureDetector(
            onTap: onProfileTap,
            child: EvikAvatar.black(
              userName,
              imageUrl: userAvatarUrl,
              size: 38,
            ),
          ),
        ],
      ),
    );
  }
}
