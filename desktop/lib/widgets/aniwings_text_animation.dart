import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// A stable wordmark: branding remains legible throughout startup.
class AniWingsTextAnimation extends StatelessWidget {
  final double fontSize;
  final bool showBadge;
  final bool showTagline;
  final String? customTagline;
  const AniWingsTextAnimation({
    super.key,
    this.fontSize = 38,
    this.showBadge = true,
    this.showTagline = true,
    this.customTagline,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'AniWings',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          decoration: TextDecoration.none,
        ),
      ),
      if (showBadge || showTagline) ...[
        const SizedBox(height: 8),
        Text(
          showTagline ? (customTagline ?? 'Desktop') : 'Desktop',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    ],
  );
}
