import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The AniWings Desktop wordmark used on navigation and authentication surfaces.
class AppBrand extends StatelessWidget {
  final double logoSize;
  final double fontSize;
  final Color textColor;
  final bool showDesktopBadge;

  const AppBrand({
    super.key,
    this.logoSize = 38,
    this.fontSize = 25,
    this.textColor = AppColors.textPrimary,
    this.showDesktopBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'AniWings Desktop',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Icon(
              Icons.auto_awesome_rounded,
              size: logoSize,
              color: AppColors.accentPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'AniWings',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      height: 1,
                    ),
                  ),
                ),
                if (showDesktopBadge) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.0,
                      vertical: 2.0,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentPrimary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.accentPrimary.withValues(alpha: 0.45),
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      'DESKTOP',
                      style: TextStyle(
                        color: AppColors.accentPrimary,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
