import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.height = 80,
    this.margin,
  });

  final double height;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EvikColors.primaryWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Shimmer.fromColors(
          baseColor: EvikColors.gray100,
          highlightColor: EvikColors.primaryWhite,
          period: const Duration(milliseconds: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Row(
                children: [
                  _SkeletonBlock(width: 44, height: 44, radius: 999),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBlock(width: double.infinity, height: 14),
                        SizedBox(height: 8),
                        _SkeletonBlock(width: 150, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
              if (height >= 110) ...const [
                SizedBox(height: 16),
                _SkeletonBlock(width: double.infinity, height: 12),
                SizedBox(height: 8),
                _SkeletonBlock(width: 220, height: 12),
              ],
              if (height >= 130) ...const [
                SizedBox(height: 16),
                Row(
                  children: [
                    _SkeletonBlock(width: 96, height: 28, radius: 999),
                    SizedBox(width: 10),
                    _SkeletonBlock(width: 74, height: 28, radius: 999),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EvikColors.gray200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
