import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── True AMOLED Dark Surfaces: Pure black (#000000) with layered depth ──
  static const Color primaryBg = Color(0xFF000000);
  static const Color secondaryBg = Color(0xFF0D0E12);
  static const Color surface = Color(0xFF181B22);
  static const Color elevatedSurface = Color(0xFF13151B);
  static const Color surfaceElevated = elevatedSurface;
  static const Color cardSurface = surface;
  static const Color cardSurfaceElevated = elevatedSurface;
  static const Color hoverState = Color(0xFF222630);
  static const Color activeState = Color(0xFF292E3A);
  static const Color authBg = primaryBg;

  // ── Brand Accents: Confident AniWings red and refined accents ──
  static const Color brandRed = Color(0xFFFF2A54);
  static const Color primaryBrandRed = brandRed;
  static const Color secondaryRed = Color(0xFFFF4D71);
  static const Color brandRedHover = secondaryRed;
  static const Color darkRed = Color(0xFF2A0C11);
  static const Color accentPrimary = brandRed;
  static const Color accentPrimaryHover = secondaryRed;
  static const Color accentSecondary = Color(0xFF4F8CFF);
  static const Color accentWarm = Color(0xFFFFB020);
  static const Color studioGold = accentWarm;

  // ── Desktop Typography Contrast Hierarchy ──
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textDisabled = Color(0xFF52525B);

  // ── Borders: Subtle, ultra-clean dividers ──
  static const Color border = Color(0xFF1E1E1E);
  static const Color borderSubtle = Color(0x0FFFFFFF);
  static const Color borderStrong = Color(0x1FFFFFFF);
  static const Color borderFocus = Color(0xFFFF2A54);

  // ── Semantic Status Indicators ──
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // ── Desktop Shadows: Restrained, content-supporting depth ──
  static const BoxShadow shadowSoft = BoxShadow(
    color: Color(0x4D000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  static const BoxShadow shadowPoster = BoxShadow(
    color: Color(0x66000000),
    blurRadius: 18,
    offset: Offset(0, 8),
  );

  static const BoxShadow shadowPanel = BoxShadow(
    color: Color(0x80000000),
    blurRadius: 24,
    offset: Offset(0, 10),
  );

  static const BoxShadow shadowFocus = BoxShadow(
    color: Color(0x80000000),
    blurRadius: 16,
    offset: Offset(0, 6),
  );

  static const BoxShadow shadowAccentGlow = BoxShadow(
    color: Color(0x28FF2A54),
    blurRadius: 16,
    offset: Offset(0, 4),
  );

  static const List<BoxShadow> desktopFocusShadow = [shadowFocus];
}

/// Refined modern scales for desktop components without harsh boxiness.
class AppRadii {
  AppRadii._();

  static const BorderRadius control = BorderRadius.all(Radius.circular(8));
  static const BorderRadius card = BorderRadius.all(Radius.circular(12));
  static const BorderRadius panel = BorderRadius.all(Radius.circular(14));
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(16));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// Standardized desktop spacing scale.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 40.0;
}

/// Coherent motion system constants for desktop interactions.
class AppDurations {
  AppDurations._();

  /// Fast micro-interaction hover and press response (120-180ms).
  static const Duration hover = Duration(milliseconds: 140);

  /// Quick UI state changes like tab switching, expanding/collapsing (180-240ms).
  static const Duration quick = Duration(milliseconds: 200);

  /// Page and modal transitions (260-320ms).
  static const Duration page = Duration(milliseconds: 280);
}

/// Natural motion easing curves for desktop fluidity.
class AppCurves {
  AppCurves._();

  static const Curve standard = Curves.easeOutCubic;
  static const Curve smooth = Curves.easeInOutCubic;
}

