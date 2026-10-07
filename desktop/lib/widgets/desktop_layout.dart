import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import 'desktop_focus_wrapper.dart';

/// Desktop-native layout calculations, responsive grids, and spacing.
class DesktopLayout {
  DesktopLayout._();

  static double landscapeCardWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1920) return 240;
    if (width >= 1440) return 220;
    return 200;
  }

  static double landscapeCardHeight(BuildContext context) {
    return landscapeCardWidth(context) * 9 / 16;
  }

  static double landscapeCardRowHeight(BuildContext context) {
    return landscapeCardHeight(context) + 16;
  }

  static double posterCardWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1920) return 195;
    if (width >= 1440) return 180;
    return 170;
  }

  static double posterCardHeight(BuildContext context) {
    return posterCardWidth(context) * 1.48;
  }

  static double posterCardRowHeight(BuildContext context) {
    return posterCardHeight(context) + 16;
  }

  static double landscapeGridMaxExtent(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1920) return 280;
    if (width >= 1440) return 260;
    return 240;
  }

  static double pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1920) return 40;
    if (width >= 1440) return 32;
    return 28;
  }

  static double pageLeftPadding(BuildContext context) {
    return pagePadding(context);
  }

  static double sectionGap(BuildContext context) {
    return 32;
  }

  static double cardGap(BuildContext context) {
    return 16;
  }

  static int responsiveCardCount(
    BuildContext context, {
    double cardWidth = 175,
  }) {
    final availableWidth =
        MediaQuery.sizeOf(context).width - 260; // account for sidebar
    final count = (availableWidth / (cardWidth + 16)).floor();
    return count.clamp(4, 12);
  }

  static SliverGridDelegate responsiveGridDelegate(
    BuildContext context, {
    double maxExtent = 210,
    double childAspectRatio = 0.67,
  }) {
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxExtent,
      mainAxisSpacing: 20,
      crossAxisSpacing: 16,
      childAspectRatio: childAspectRatio,
    );
  }
}

/// Pure AMOLED black desktop background.
class DesktopBackground extends StatelessWidget {
  const DesktopBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.primaryBg,
      child: SizedBox.expand(),
    );
  }
}

/// Paints the shared desktop backdrop behind a full-page child.
class DesktopPageBackdrop extends StatelessWidget {
  final Widget child;

  const DesktopPageBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [const DesktopBackground(), child],
    );
  }
}

class DesktopPageHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final EdgeInsets? padding;

  const DesktopPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final pagePadding = DesktopLayout.pagePadding(context);
    final pageLeftPadding = DesktopLayout.pageLeftPadding(context);
    return Padding(
      padding:
          padding ?? EdgeInsets.fromLTRB(pageLeftPadding, 20, pagePadding, 16),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.accentPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 16),
            ..._withSpacing(actions),
          ],
        ],
      ),
    );
  }

  static List<Widget> _withSpacing(List<Widget> items) {
    return [
      for (var index = 0; index < items.length; index++) ...[
        if (index > 0) const SizedBox(width: 10),
        items[index],
      ],
    ];
  }
}

class DesktopSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const DesktopSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.accentPrimary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class DesktopSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final Color? color;

  const DesktopSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = AppRadii.panel,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.borderSubtle, width: 1.0),
        boxShadow: const [AppColors.shadowSoft],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class DesktopBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final Map<LogicalKeyboardKey, VoidCallback> directionalKeyHandlers;

  const DesktopBackButton({
    super.key,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.directionalKeyHandlers = const {},
  });

  @override
  Widget build(BuildContext context) {
    return DesktopFocusWrapper(
      focusNode: focusNode,
      directionalKeyHandlers: directionalKeyHandlers,
      autofocus: autofocus,
      onTap: onPressed,
      borderRadius: AppRadii.control,
      focusedScale: 1.02,
      child: Semantics(
        label: 'Back',
        button: true,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.control,
            border: Border.all(color: AppColors.borderStrong, width: 1.0),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class DesktopIconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  const DesktopIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return DesktopFocusWrapper(
      autofocus: autofocus,
      onTap: onPressed,
      borderRadius: AppRadii.control,
      focusedScale: 1.02,
      child: Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.control,
              border: Border.all(color: AppColors.borderStrong, width: 1.0),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 18),
          ),
        ),
      ),
    );
  }
}

class DesktopEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const DesktopEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: DesktopSurface(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.accentPrimary, size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Backwards Compatibility Aliases ──────────────────────────────────────────
