import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'desktop_focus_manager.dart';

/// Navigation controller coordinating desktop keyboard and back behaviors across views.
class DesktopNavigationController {
  DesktopNavigationController._();
  static final DesktopNavigationController instance =
      DesktopNavigationController._();

  /// Checks if the currently focused widget is an editable text field
  /// or text input to prevent Backspace keys from accidentally navigating back.
  static bool isTextInputActive() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final context = focus.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.widget is TextField ||
        context.findAncestorWidgetOfExactType<EditableText>() != null ||
        context.findAncestorWidgetOfExactType<TextField>() != null;
  }

  /// Evaluates whether a given key event should be interpreted as a Back action.
  static bool isDesktopBackKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.gameButtonB) {
      return true;
    }

    if (key == LogicalKeyboardKey.backspace) {
      return !isTextInputActive();
    }

    return false;
  }

  /// Opens a desktop modal dialog with automatic focus capture and restoration.
  static Future<T?> showDesktopDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
  }) async {
    DesktopFocusManager.instance.savePreDialogFocus();
    try {
      final result = await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.85),
        builder: builder,
      );
      return result;
    } finally {
      DesktopFocusManager.instance.restorePreDialogFocus();
    }
  }
}

// ── Backwards Compatibility Alias ──────────────────────────────────────────
