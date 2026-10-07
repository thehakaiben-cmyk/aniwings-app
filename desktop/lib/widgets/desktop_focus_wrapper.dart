import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/focus/desktop_focus_node_registry.dart';
import '../core/focus/desktop_focus_manager.dart';

typedef DesktopFocusBuilder =
    Widget Function(BuildContext context, bool isFocused, bool isHovered);

/// Desktop focus and hover wrapper providing mouse cursor tracking,
/// hover elevations, keyboard shortcuts, and directional keys.
class DesktopFocusWrapper extends StatefulWidget {
  final Widget? child;
  final DesktopFocusBuilder? builder;
  final bool showDefaultFocusBorder;
  final VoidCallback? onTap;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final Map<LogicalKeyboardKey, VoidCallback> directionalKeyHandlers;

  /// An optional node for callers that need to move focus to a specific control.
  final FocusNode? focusNode;
  final String? registryKey;
  final ValueChanged<bool>? onFocusChange;
  final String? debugLabel;
  final BorderRadius? borderRadius;
  final bool autofocus;
  final bool canRequestFocus;
  final bool ensureVisibleOnFocus;
  final double? targetScrollAlignment;
  final EdgeInsets? padding;
  final double focusedScale;

  const DesktopFocusWrapper({
    super.key,
    this.child,
    this.builder,
    this.showDefaultFocusBorder = true,
    this.onTap,
    this.onKeyEvent,
    this.directionalKeyHandlers = const {},
    this.focusNode,
    this.registryKey,
    this.onFocusChange,
    this.debugLabel,
    this.borderRadius,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.ensureVisibleOnFocus = true,
    this.targetScrollAlignment,
    this.padding,
    this.focusedScale = 1.0,
  }) : assert(
         child != null || builder != null,
         'Either child or builder must be provided',
       );

  const DesktopFocusWrapper.builder({
    super.key,
    required DesktopFocusBuilder this.builder,
    this.showDefaultFocusBorder = false,
    this.onTap,
    this.onKeyEvent,
    this.directionalKeyHandlers = const {},
    this.focusNode,
    this.registryKey,
    this.onFocusChange,
    this.debugLabel,
    this.borderRadius,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.ensureVisibleOnFocus = true,
    this.targetScrollAlignment,
    this.padding,
    this.focusedScale = 1.0,
  }) : child = null;

  @override
  State<DesktopFocusWrapper> createState() => _DesktopFocusWrapperState();
}

class _DesktopFocusWrapperState extends State<DesktopFocusWrapper> {
  FocusNode? _fallbackFocusNode;
  bool _isFocused = false;
  bool _isHovered = false;
  late FocusNode _observedFocusNode;

  FocusNode get _focusNode {
    if (widget.focusNode != null) return widget.focusNode!;
    if (widget.registryKey != null) {
      return DesktopFocusNodeRegistry.instance.getOrCreateNode(
        widget.registryKey!,
        debugLabel: widget.debugLabel ?? widget.registryKey,
      );
    }
    return _fallbackFocusNode ??= FocusNode(
      debugLabel: widget.debugLabel ?? 'Desktop action',
    );
  }

  @override
  void initState() {
    super.initState();
    _observedFocusNode = _focusNode;
    _observedFocusNode.addListener(_syncPrimaryFocus);
  }

  @override
  void didUpdateWidget(covariant DesktopFocusWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    final node = _focusNode;
    if (node != _observedFocusNode) {
      _observedFocusNode.removeListener(_syncPrimaryFocus);
      _observedFocusNode = node;
      node.addListener(_syncPrimaryFocus);
      _isFocused = node.hasPrimaryFocus;
    }
  }

  void _syncPrimaryFocus() {
    if (!mounted) return;
    final focused = _observedFocusNode.hasPrimaryFocus;
    if (_isFocused == focused) return;
    setState(() => _isFocused = focused);
    widget.onFocusChange?.call(focused);
    if (focused && widget.ensureVisibleOnFocus) _ensureFocusedItemVisible();
  }

  @override
  void dispose() {
    _observedFocusNode.removeListener(_syncPrimaryFocus);
    _fallbackFocusNode?.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (!_observedFocusNode.hasPrimaryFocus) return KeyEventResult.ignored;
    final customResult = widget.onKeyEvent?.call(event);
    if (customResult != null &&
        (customResult == KeyEventResult.handled ||
            customResult == KeyEventResult.skipRemainingHandlers)) {
      return customResult;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) {
        widget.onTap?.call();
      }
      return KeyEventResult.handled;
    }

    final directHandler = widget.directionalKeyHandlers[key];
    if (directHandler != null) {
      directHandler();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _ensureFocusedItemVisible() {
    if (!mounted || !_focusNode.hasFocus) return;
    DesktopFocusManager.ensureFocusedVisible(
      context,
      targetScrollAlignment: widget.targetScrollAlignment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(12);
    final isActive = _isFocused;

    final effectiveChild = widget.builder != null
        ? widget.builder!(context, _isFocused, _isHovered)
        : (widget.child ?? const SizedBox.shrink());

    final focusableChild = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.canRequestFocus,
      skipTraversal: false,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: Semantics(
        label: widget.debugLabel,
        button: widget.onTap != null,
        focusable: widget.canRequestFocus,
        focused: isActive,
        child: MouseRegion(
          cursor: widget.onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onEnter: (_) {
            if (mounted) {
              setState(() => _isHovered = true);
            }
          },
          onExit: (_) {
            if (mounted) {
              setState(() => _isHovered = false);
            }
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: RepaintBoundary(
              child: AnimatedScale(
                scale: isActive ? widget.focusedScale : 1.0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                child: (widget.showDefaultFocusBorder && widget.builder == null)
                    ? AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        padding: widget.padding,
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: _isFocused
                                ? Colors.white
                                : _isHovered
                                ? Colors.white38
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: effectiveChild,
                      )
                    : Container(padding: widget.padding, child: effectiveChild),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.directionalKeyHandlers.isEmpty) return focusableChild;

    return Shortcuts(
      shortcuts: {
        for (final key in widget.directionalKeyHandlers.keys)
          SingleActivator(key): _DesktopDirectionalKeyIntent(key),
      },
      child: Actions(
        actions: {
          _DesktopDirectionalKeyIntent:
              CallbackAction<_DesktopDirectionalKeyIntent>(
                onInvoke: (intent) {
                  widget.directionalKeyHandlers[intent.logicalKey]?.call();
                  return null;
                },
              ),
        },
        child: focusableChild,
      ),
    );
  }
}

class _DesktopDirectionalKeyIntent extends Intent {
  final LogicalKeyboardKey logicalKey;

  const _DesktopDirectionalKeyIntent(this.logicalKey);
}

// ── Backwards Compatibility Aliases ──────────────────────────────────────────
