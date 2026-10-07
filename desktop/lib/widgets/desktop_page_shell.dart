import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/focus/desktop_navigation_controller.dart';

/// Desktop page shell providing standard keyboard navigation (PageUp, PageDown,
/// Escape/Back), scroll handling, and modal/route popping.
class DesktopPageShell extends StatefulWidget {
  final Widget child;
  final VoidCallback? onRootBack;

  const DesktopPageShell({super.key, required this.child, this.onRootBack});

  @override
  State<DesktopPageShell> createState() => _DesktopPageShellState();
}

class _DesktopPageShellState extends State<DesktopPageShell> {
  ScrollableState? _lastActiveScrollable;
  DateTime _lastBackTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _triggerBack() {
    final now = DateTime.now();
    if (now.difference(_lastBackTime).inMilliseconds < 400) {
      return;
    }
    _lastBackTime = now;

    // 1. Prioritize popping modal dialogs / overlays open above this page
    final currentRoute = ModalRoute.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (currentRoute != null && !currentRoute.isCurrent && rootNav.canPop()) {
      rootNav.pop();
      return;
    }

    // 2. Check if GoRouter can pop the current push route
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return;
    }

    // 3. Check if standard Navigator can pop
    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() ?? false) {
      navigator!.pop();
      return;
    }

    // 4. Trigger root back handler
    if (widget.onRootBack != null) {
      widget.onRootBack!();
      return;
    }

    // 5. Default safety fallback to Home
    router?.go('/home');
  }

  ScrollableState? _findVerticalScrollable(BuildContext startContext) {
    ScrollableState? current = Scrollable.maybeOf(startContext);
    while (current != null) {
      if (current.axisDirection == AxisDirection.down ||
          current.axisDirection == AxisDirection.up) {
        return current;
      }
      final parent = current.context.findAncestorStateOfType<ScrollableState>();
      current = parent;
    }
    return null;
  }

  bool _handlePageScroll(bool isDown) {
    final primaryContext = FocusManager.instance.primaryFocus?.context;
    final focusedContext = (primaryContext != null && primaryContext.mounted)
        ? primaryContext
        : null;

    final scrollable =
        (focusedContext != null
            ? (_findVerticalScrollable(focusedContext) ??
                  Scrollable.maybeOf(focusedContext))
            : null) ??
        (_lastActiveScrollable?.context.mounted == true
            ? _lastActiveScrollable
            : null);

    if (scrollable != null && scrollable.position.hasPixels) {
      final position = scrollable.position;
      final delta = (position.viewportDimension * 0.82).clamp(240.0, 1200.0);
      final targetPixels = isDown
          ? (position.pixels + delta).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            )
          : (position.pixels - delta).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            );

      if ((targetPixels - position.pixels).abs() > 1.0) {
        position.animateTo(
          targetPixels,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        );
        return true;
      }
    }
    return false;
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isPageDown =
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.channelDown;
    final isPageUp =
        key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp;

    if (isPageDown || isPageUp) {
      if (_handlePageScroll(isPageDown)) {
        return KeyEventResult.handled;
      }
    }

    if (!DesktopNavigationController.isDesktopBackKey(event)) {
      return KeyEventResult.ignored;
    }

    _triggerBack();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _triggerBack();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final notifContext = notification.context;
          if (notifContext != null && notifContext.mounted) {
            final scrollable =
                _findVerticalScrollable(notifContext) ??
                Scrollable.maybeOf(notifContext);
            if (scrollable != null) {
              _lastActiveScrollable = scrollable;
            }
          }
          return false;
        },
        child: FocusScope(
          onKeyEvent: (_, event) => _handleKey(event),
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Backwards Compatibility Alias ──────────────────────────────────────────
