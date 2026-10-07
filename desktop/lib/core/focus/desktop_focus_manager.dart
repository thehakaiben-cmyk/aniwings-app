import 'package:flutter/material.dart';
import 'desktop_focus_node_registry.dart';

/// Central focus management system for AniWings Desktop.
///
/// Handles:
/// 1. Screen focus persistence & restoration (Home -> Details -> Back restores exact card).
/// 2. Row-to-row horizontal index preservation (Trending card 7 -> Down -> Recently Updated card 7).
/// 3. Sidebar <-> Content transition memory.
/// 4. Modal dialog focus trapping & restoration.
/// 5. Focus-aware auto-scrolling without parent/child scroll conflicts.
class DesktopFocusManager {
  DesktopFocusManager._();
  static final DesktopFocusManager instance = DesktopFocusManager._();

  final DesktopFocusNodeRegistry registry = DesktopFocusNodeRegistry.instance;

  // Screen route -> last focused element identifier or node key
  final Map<String, String> _screenFocusMemory = {};

  // Row ID -> last focused horizontal index
  final Map<String, int> _rowFocusMemory = {};

  // Active row ID on the current screen
  String? _activeRowId;
  int _navigationGeneration = 0;

  // Node that had focus before a dialog / modal opened
  FocusNode? _preDialogFocusNode;

  // Last focused content node before sidebar took focus
  FocusNode? _preSidebarFocusNode;
  String? _preSidebarElementKey;

  // --- Screen Focus Restoration ---

  /// Saves the active element key for a given screen route (e.g. '/home', '/watchlist').
  void saveScreenFocus(String route, String elementKey) {
    _screenFocusMemory[route] = elementKey;
  }

  /// Retrieves the saved element key for a route.
  String? getSavedScreenFocus(String route) {
    return _screenFocusMemory[route];
  }

  /// Attempts to restore focus to the saved element on [route].
  ///
  /// Returns `true` if focus was successfully requested.
  bool restoreScreenFocus(String route) {
    final key = _screenFocusMemory[route];
    if (key == null) return false;

    final node = registry.getNode(key);
    if (node != null && node.context != null && node.canRequestFocus) {
      node.requestFocus();
      return true;
    }
    return false;
  }

  /// Clears saved focus memory for [route].
  void clearScreenFocus(String route) {
    _screenFocusMemory.remove(route);
  }

  // --- Row-to-Row Carousel Navigation (Preserves Horizontal Index) ---

  /// Records that the card at [index] is currently focused in [rowId].
  void recordRowFocus(String rowId, int index) {
    _rowFocusMemory[rowId] = index;
    _activeRowId = rowId;
  }

  /// Gets the last focused index in [rowId], defaulting to 0.
  int getRowFocusedIndex(String rowId) {
    return _rowFocusMemory[rowId] ?? 0;
  }

  /// Moves focus smoothly between two horizontal content rows, preserving the
  /// closest possible horizontal card position.
  bool moveFocusBetweenRows({
    required String fromRowId,
    required String toRowId,
    required int currentIndex,
    required int toRowCount,
    String nodeKeyPrefix = 'home_row_',
    ScrollController? scrollController,
    double cardWidth = 144.0,
    VoidCallback? fallback,
  }) {
    final generation = ++_navigationGeneration;
    final origin = FocusManager.instance.primaryFocus;
    if (toRowCount <= 0) {
      fallback?.call();
      return false;
    }

    // Clamp index to the bounds of the destination row
    final targetIndex = currentIndex.clamp(0, toRowCount - 1);
    final targetKey = '$nodeKeyPrefix${toRowId}_$targetIndex';
    final targetNode = registry.getOrCreateNode(
      targetKey,
      debugLabel: '$toRowId card $targetIndex',
    );

    // Save memory for both rows
    recordRowFocus(fromRowId, currentIndex);
    recordRowFocus(toRowId, targetIndex);

    // Pre-scroll the target horizontal list if controller is attached
    if (scrollController != null && scrollController.hasClients) {
      final viewportWidth = scrollController.position.viewportDimension;
      final targetOffset = (targetIndex * cardWidth) - (viewportWidth * 0.35);
      final clampedOffset = targetOffset.clamp(
        scrollController.position.minScrollExtent,
        scrollController.position.maxScrollExtent,
      );
      if ((clampedOffset - scrollController.offset).abs() > 10) {
        scrollController.jumpTo(clampedOffset);
      }
    }

    // If node is already mounted in the widget tree, focus immediately
    if (targetNode.context != null && targetNode.canRequestFocus) {
      targetNode.requestFocus();
      return true;
    }

    // Ignore stale requests after another move or a sidebar transition.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _navigationGeneration ||
          FocusManager.instance.primaryFocus != origin) {
        return;
      }
      if (targetNode.context != null && targetNode.canRequestFocus) {
        targetNode.requestFocus();
      } else {
        // Fallback: try last known focused index in that row, or 0
        final lastIdx = getRowFocusedIndex(toRowId).clamp(0, toRowCount - 1);
        final fallbackKey = '$nodeKeyPrefix${toRowId}_$lastIdx';
        final fallbackNode =
            registry.getNode(fallbackKey) ??
            registry.getNode('$nodeKeyPrefix${toRowId}_0');
        if (fallbackNode != null &&
            fallbackNode.context != null &&
            fallbackNode.canRequestFocus) {
          fallbackNode.requestFocus();
        } else {
          fallback?.call();
        }
      }
    });

    return true;
  }

  // --- Sidebar <-> Content Navigation Memory ---

  /// Records the active content node before navigation rail steals focus.
  void recordPreSidebarFocus(FocusNode? node, {String? elementKey}) {
    _preSidebarFocusNode = node;
    _preSidebarElementKey = elementKey;
  }

  /// Restores focus to the last active content element when leaving the sidebar.
  bool restorePreSidebarFocus({VoidCallback? onFallback}) {
    final hasPreSidebar =
        _preSidebarFocusNode != null || _preSidebarElementKey != null;
    if (!hasPreSidebar) return false;

    // 1. Try restoring by direct node if still mounted
    if (_preSidebarFocusNode != null) {
      final node = _preSidebarFocusNode!;
      _preSidebarFocusNode = null;
      try {
        if (node.context != null && node.canRequestFocus) {
          node.requestFocus();
          return true;
        }
      } catch (_) {}
    }

    // 2. Try restoring by element key from registry
    if (_preSidebarElementKey != null) {
      final key = _preSidebarElementKey!;
      _preSidebarElementKey = null;
      final node = registry.getNode(key);
      if (node != null && node.context != null && node.canRequestFocus) {
        node.requestFocus();
        return true;
      }
    }

    // 3. Try restoring the active row's last focused card
    if (_activeRowId != null) {
      final index = getRowFocusedIndex(_activeRowId!);
      final key = 'home_row_${_activeRowId}_$index';
      final node = registry.getNode(key);
      if (node != null && node.context != null && node.canRequestFocus) {
        node.requestFocus();
        return true;
      }
    }

    // 4. Fallback handler
    if (onFallback != null) {
      onFallback();
      return true;
    }

    return false;
  }

  /// Resets all memory and registry caches.
  void reset() {
    _navigationGeneration++;
    _preSidebarFocusNode = null;
    _preSidebarElementKey = null;
    _preDialogFocusNode = null;
    _activeRowId = null;
    _rowFocusMemory.clear();
    _screenFocusMemory.clear();
    registry.disposeAll();
  }

  // --- Dialog & Modal Focus Trapping ---

  /// Remembers the current focused control before displaying a dialog.
  void savePreDialogFocus() {
    _preDialogFocusNode = FocusManager.instance.primaryFocus;
  }

  /// Restores focus to the element that launched the dialog.
  void restorePreDialogFocus() {
    if (_preDialogFocusNode != null) {
      try {
        if (_preDialogFocusNode!.context != null &&
            _preDialogFocusNode!.canRequestFocus) {
          _preDialogFocusNode!.requestFocus();
        }
      } catch (_) {}
      _preDialogFocusNode = null;
    }
  }

  // --- Focus-Aware Auto-Scrolling Helper ---

  /// Safely ensures [context] is visible within its parent Scrollable.
  static void ensureVisible(
    BuildContext context, {
    double alignment = 0.5,
    Duration duration = const Duration(milliseconds: 140),
    Curve curve = Curves.easeOutCubic,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      final scrollable = Scrollable.maybeOf(context);
      if (scrollable == null) return;

      Scrollable.ensureVisible(
        context,
        alignment: alignment,
        duration: duration,
        curve: curve,
      );
    });
  }

  /// Ensures that the focused element associated with [context] is comfortably
  /// visible in all enclosing scrollables.
  static void ensureFocusedVisible(
    BuildContext context, {
    double? targetScrollAlignment,
    double vTopMargin = 140.0,
    double vBottomMargin = 100.0,
    double hMargin = 40.0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          !renderObject.attached) {
        return;
      }

      if (targetScrollAlignment != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          alignment: targetScrollAlignment,
        );
        return;
      }

      BuildContext currentContext = context;
      ScrollableState? scrollable = Scrollable.maybeOf(currentContext);

      while (scrollable != null) {
        if (!scrollable.context.mounted) break;
        final scrollBox = scrollable.context.findRenderObject() as RenderBox?;
        if (scrollBox != null &&
            scrollBox.hasSize &&
            scrollBox.attached &&
            scrollable.position.hasPixels) {
          final isHorizontal =
              scrollable.axisDirection == AxisDirection.right ||
              scrollable.axisDirection == AxisDirection.left;

          final offsetInViewport = renderObject.localToGlobal(
            Offset.zero,
            ancestor: scrollBox,
          );

          if (isHorizontal) {
            final itemLeft = offsetInViewport.dx;
            final itemRight = itemLeft + renderObject.size.width;
            final viewportWidth = scrollBox.size.width;

            final isHorizontallyVisible =
                itemLeft >= hMargin && itemRight <= (viewportWidth - hMargin);

            if (!isHorizontallyVisible) {
              final currentPixels = scrollable.position.pixels;
              double target;
              if (itemLeft < hMargin) {
                target = currentPixels + itemLeft - hMargin;
              } else {
                target = currentPixels + itemRight - (viewportWidth - hMargin);
              }
              final clampedTarget = target.clamp(
                scrollable.position.minScrollExtent,
                scrollable.position.maxScrollExtent,
              );
              if ((clampedTarget - currentPixels).abs() > 2.0) {
                scrollable.position.animateTo(
                  clampedTarget,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                );
              }
            }
          } else {
            // Vertical scrollable
            final itemTop = offsetInViewport.dy;
            final itemBottom = itemTop + renderObject.size.height;
            final viewportHeight = scrollBox.size.height;

            final isVerticallyVisible =
                itemTop >= vTopMargin &&
                itemBottom <= (viewportHeight - vBottomMargin);

            if (!isVerticallyVisible) {
              final currentPixels = scrollable.position.pixels;
              double target;
              if (itemTop < vTopMargin) {
                target = currentPixels + itemTop - vTopMargin;
              } else {
                target =
                    currentPixels +
                    itemBottom -
                    (viewportHeight - vBottomMargin);
              }
              final clampedTarget = target.clamp(
                scrollable.position.minScrollExtent,
                scrollable.position.maxScrollExtent,
              );
              if ((clampedTarget - currentPixels).abs() > 2.0) {
                scrollable.position.animateTo(
                  clampedTarget,
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOutCubic,
                );
              }
            }
          }
        }

        currentContext = scrollable.context;
        scrollable = Scrollable.maybeOf(currentContext);
      }
    });
  }
}

// ── Backwards Compatibility Alias ──────────────────────────────────────────
