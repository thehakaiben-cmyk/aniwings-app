import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_colors.dart';
import '../core/focus/desktop_focus_manager.dart';
import '../core/focus/desktop_navigation_controller.dart';
import 'desktop_update_dialog.dart';

/// Persistent desktop navigation sidebar and rail with collapsible states,
/// mouse hover feedback, and keyboard shortcuts.
class DesktopSideNav extends StatefulWidget {
  final int currentIndex;
  final Widget child;
  final ValueChanged<int>? onDestinationSelected;

  const DesktopSideNav({
    super.key,
    required this.currentIndex,
    required this.child,
    this.onDestinationSelected,
  });

  static void focusRail(BuildContext context) {
    final state = context.findAncestorStateOfType<_DesktopSideNavState>();
    state?._focusCurrentItem();
  }

  @override
  State<DesktopSideNav> createState() => _DesktopSideNavState();
}

class _NavItemData {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? branchIndex;
  final String? route;
  const _NavItemData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.branchIndex,
    this.route,
  });
}

class _DesktopSideNavState extends State<DesktopSideNav> {
  late final List<FocusNode> _navFocusNodes;
  late final FocusScopeNode _navFocusScopeNode;
  late final FocusScopeNode _contentFocusScopeNode;
  bool _navHasFocus = false;
  bool _isCollapsed = false;

  static const List<_NavItemData> _primaryNavItems = [
    _NavItemData(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
      branchIndex: 0,
    ),
    _NavItemData(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
      label: 'Discover',
      branchIndex: 1,
    ),
    _NavItemData(
      icon: Icons.search_rounded,
      selectedIcon: Icons.search_rounded,
      label: 'Search',
      branchIndex: 2,
    ),
    _NavItemData(
      icon: Icons.bookmark_outline_rounded,
      selectedIcon: Icons.bookmark_rounded,
      label: 'Watchlist',
      branchIndex: 3,
    ),
    _NavItemData(
      icon: Icons.history_rounded,
      selectedIcon: Icons.history_rounded,
      label: 'History',
      branchIndex: 4,
    ),
    _NavItemData(
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library_rounded,
      label: 'Collections',
      branchIndex: 5,
    ),
    _NavItemData(
      icon: Icons.download_outlined,
      selectedIcon: Icons.download_rounded,
      label: 'Downloads',
      branchIndex: 7,
    ),
    _NavItemData(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: 'Settings',
      branchIndex: 6,
    ),
  ];

  static const List<_NavItemData> _bottomNavItems = [
    _NavItemData(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Profile',
      route: '/profile',
    ),
  ];

  List<_NavItemData> get _allNavItems => [
    ..._primaryNavItems,
    ..._bottomNavItems,
  ];

  @override
  void initState() {
    super.initState();
    _navFocusScopeNode = FocusScopeNode(
      debugLabel: 'Desktop navigation rail',
      skipTraversal: true,
      traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
      directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
    );
    _contentFocusScopeNode = FocusScopeNode(
      debugLabel: 'Desktop page content',
      skipTraversal: true,
      traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
      directionalTraversalEdgeBehavior: TraversalEdgeBehavior.stop,
    );
    _navFocusNodes = List.generate(
      _allNavItems.length,
      (index) =>
          FocusNode(debugLabel: 'DesktopSideNav ${_allNavItems[index].label}'),
    );
  }

  @override
  void didUpdateWidget(covariant DesktopSideNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex && _navHasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusCurrentItem();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _navFocusNodes) {
      node.dispose();
    }
    _navFocusScopeNode.dispose();
    _contentFocusScopeNode.dispose();
    super.dispose();
  }

  void _focusCurrentItem() {
    int targetIndex = 0;
    final all = _allNavItems;
    for (int i = 0; i < all.length; i++) {
      if (all[i].branchIndex == widget.currentIndex) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < _navFocusNodes.length) {
      _navFocusNodes[targetIndex].requestFocus();
    }
  }

  void _onNavigate(_NavItemData item, int index) {
    if (item.branchIndex != null) {
      if (item.branchIndex == widget.currentIndex) {
        _focusContent();
        return;
      }
      widget.onDestinationSelected?.call(item.branchIndex!);
    } else if (item.route != null) {
      context.push(item.route!).then((_) {
        if (mounted && _navHasFocus) {
          _navFocusNodes[index].requestFocus();
        }
      });
    }
  }

  void _focusNavItem(int index) {
    final target = index.clamp(0, _navFocusNodes.length - 1).toInt();
    _navFocusNodes[target].requestFocus();
  }

  bool _focusContent() {
    if (DesktopFocusManager.instance.restorePreSidebarFocus()) {
      return true;
    }

    final preferredLabels = switch (widget.currentIndex) {
      0 => [
        'home hero slider',
        'hero watch now',
        'watch now',
        'hero details',
        'hero showcase',
      ],
      2 => ['search field', 'search input'],
      _ => <String>[],
    };

    if (preferredLabels.isNotEmpty) {
      for (final preferredLabel in preferredLabels) {
        for (final node in _contentFocusScopeNode.descendants) {
          if (node.debugLabel?.toLowerCase() == preferredLabel &&
              node.canRequestFocus) {
            node.requestFocus();
            return true;
          }
        }
      }
    }

    final rememberedChild = _contentFocusScopeNode.focusedChild;
    if (rememberedChild != null && rememberedChild.canRequestFocus) {
      rememberedChild.requestFocus();
      return true;
    }

    for (final node in _contentFocusScopeNode.traversalDescendants) {
      if (node.canRequestFocus && !node.skipTraversal) {
        node.requestFocus();
        return true;
      }
    }
    return false;
  }

  KeyEventResult _handleContentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isBackKey = DesktopNavigationController.isDesktopBackKey(event);

    if (isBackKey) {
      final currentFocus = FocusManager.instance.primaryFocus;
      if (currentFocus != null && currentFocus != node) {
        return KeyEventResult.ignored;
      }
      _focusCurrentItem();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _focusCurrentItem();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handleNavFocusChange(bool hasFocus) {
    if (!mounted || _navHasFocus == hasFocus) return;
    setState(() => _navHasFocus = hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bool isSmallScreen = screenWidth < 1080;
    final bool isCollapsed = _isCollapsed || isSmallScreen;
    final double railWidth = isCollapsed ? 64.0 : 224.0;

    return Row(
      children: [
        // ── Persistent Desktop Sidebar ──
        AnimatedContainer(
          key: const ValueKey('desktop-nav-rail'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: railWidth,
          decoration: const BoxDecoration(
            color: AppColors.secondaryBg,
            border: Border(
              right: BorderSide(color: AppColors.borderSubtle, width: 1.0),
            ),
          ),
          child: SafeArea(
            left: false,
            right: false,
            child: Material(
              color: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = (constraints.maxHeight - 20).clamp(
                    0.0,
                    double.infinity,
                  );
                  final bool needsScroll = availableHeight < 700;

                  final navColumn = Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ── Upper Section: Brand + Primary Navigation ──
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Top Brand Header (Direct surface integration, not a card) ──
                          Container(
                            height: 48,
                            margin: EdgeInsets.symmetric(
                              horizontal: isCollapsed ? 8 : 14,
                              vertical: 10,
                            ),
                            child: isCollapsed
                                ? Center(
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      width: 24,
                                      height: 24,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.centerLeft,
                                      minWidth: 196,
                                      maxWidth: 196,
                                      minHeight: 48,
                                      maxHeight: 48,
                                      child: Row(
                                        children: [
                                          const SizedBox(width: 4),
                                          Image.asset(
                                            'assets/images/logo.png',
                                            width: 24,
                                            height: 24,
                                            fit: BoxFit.contain,
                                          ),
                                          const SizedBox(width: 10),
                                          const Expanded(
                                            child: Text(
                                              'AniWings',
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.clip,
                                              style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.3,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.brandRed
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: AppColors.brandRed
                                                    .withValues(alpha: 0.35),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: const Text(
                                              'DESKTOP',
                                              style: TextStyle(
                                                color: AppColors.brandRed,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 4),

                          // ── Primary Navigation Items ──
                          for (
                            int index = 0;
                            index < _primaryNavItems.length;
                            index++
                          ) ...[
                            if (index == 0 || index == 3 || index == 7) ...[
                              ClipRect(
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 140),
                                  opacity: isCollapsed ? 0.0 : 1.0,
                                  child: SizedBox(
                                    width: 196,
                                    height: index == 0 ? 22 : 30,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          14,
                                          index == 0 ? 4 : 12,
                                          14,
                                          6,
                                        ),
                                        child: Text(
                                          index == 0
                                              ? 'EXPLORE'
                                              : index == 3
                                              ? 'LIBRARY'
                                              : 'SYSTEM',
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.clip,
                                          style: const TextStyle(
                                            color: Color(0x66FFFFFF),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            Builder(
                              builder: (context) {
                                final item = _primaryNavItems[index];
                                final isSelected =
                                    item.branchIndex == widget.currentIndex;
                                return FocusTraversalOrder(
                                  order: NumericFocusOrder(index.toDouble()),
                                  child: _DesktopNavItem(
                                    focusNode: _navFocusNodes[index],
                                    item: item,
                                    isSelected: isSelected,
                                    isCollapsed: isCollapsed,
                                    onMoveUp: () => _focusNavItem(index - 1),
                                    onMoveDown: () => _focusNavItem(index + 1),
                                    onMoveRight: _focusContent,
                                    onTap: () => _onNavigate(item, index),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                          ],
                        ],
                      ),

                      // ── Lower Section: Profile & Collapse Toggle ──
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Divider(color: Color(0x18FFFFFF), height: 1),
                          ),

                          // ── Profile Item ──
                          for (
                            int bIdx = 0;
                            bIdx < _bottomNavItems.length;
                            bIdx++
                          ) ...[
                            Builder(
                              builder: (context) {
                                final globalIndex =
                                    _primaryNavItems.length + bIdx;
                                final item = _bottomNavItems[bIdx];
                                final isSelected =
                                    item.branchIndex == widget.currentIndex;
                                return FocusTraversalOrder(
                                  order: NumericFocusOrder(
                                    globalIndex.toDouble(),
                                  ),
                                  child: _DesktopNavItem(
                                    focusNode: _navFocusNodes[globalIndex],
                                    item: item,
                                    isSelected: isSelected,
                                    isCollapsed: isCollapsed,
                                    onMoveUp: () =>
                                        _focusNavItem(globalIndex - 1),
                                    onMoveDown: () =>
                                        _focusNavItem(globalIndex + 1),
                                    onMoveRight: _focusContent,
                                    onTap: () => _onNavigate(item, globalIndex),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                          ],

                          // ── Collapse / Expand Sidebar Button ──
                          if (!isSmallScreen) ...[
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isCollapsed ? 6 : 10,
                                vertical: 4,
                              ),
                              child: Tooltip(
                                message: isCollapsed
                                    ? 'Expand sidebar'
                                    : 'Collapse sidebar',
                                waitDuration: const Duration(milliseconds: 300),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isCollapsed = !_isCollapsed;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    height: 38,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCollapsed ? 0 : 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: isCollapsed
                                        ? const Center(
                                            child: Icon(
                                              Icons.chevron_right_rounded,
                                              color: AppColors.textSecondary,
                                              size: 20,
                                            ),
                                          )
                                        : ClipRect(
                                            child: OverflowBox(
                                              alignment: Alignment.centerLeft,
                                              minWidth: 196,
                                              maxWidth: 196,
                                              minHeight: 38,
                                              maxHeight: 38,
                                              child: Row(
                                                children: [
                                                  const SizedBox(width: 8),
                                                  Icon(
                                                    isCollapsed
                                                        ? Icons
                                                              .chevron_right_rounded
                                                        : Icons
                                                              .chevron_left_rounded,
                                                    color: AppColors.textMuted,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  const Expanded(
                                                    child: Text(
                                                      'Collapse sidebar',
                                                      overflow:
                                                          TextOverflow.clip,
                                                      maxLines: 1,
                                                      softWrap: false,
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.textMuted,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],

                          // ── Version Pill (Click to Check Updates) ──
                          Tooltip(
                            message: 'Check for updates',
                            child: InkWell(
                              onTap: () => showDesktopUpdateDialog(context),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                height: isCollapsed ? 32 : null,
                                margin: EdgeInsets.symmetric(
                                  horizontal: isCollapsed ? 6 : 10,
                                  vertical: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x0CFFFFFF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0x18FFFFFF),
                                    width: 0.8,
                                  ),
                                ),
                                child: isCollapsed
                                    ? const Center(
                                        child: Icon(
                                          Icons.system_update_rounded,
                                          size: 18,
                                          color: AppColors.textMuted,
                                        ),
                                      )
                                    : FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.center,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              isCollapsed
                                                  ? 'v1.2.5'
                                                  : 'AniWings Desktop v1.2.5',
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.2,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                            if (!isCollapsed) ...[
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.system_update_rounded,
                                                size: 10,
                                                color: AppColors.textMuted,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ],
                  );

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Focus(
                      canRequestFocus: false,
                      onFocusChange: _handleNavFocusChange,
                      child: FocusScope(
                        node: _navFocusScopeNode,
                        child: FocusTraversalGroup(
                          policy: OrderedTraversalPolicy(),
                          child: needsScroll
                              ? SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  child: navColumn,
                                )
                              : navColumn,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // ── Main Content Area (Side-by-Side) ──
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _handleContentKey,
            child: FocusScope(
              node: _contentFocusScopeNode,
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopNavItem extends StatefulWidget {
  final FocusNode focusNode;
  final _NavItemData item;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final bool Function() onMoveRight;
  final VoidCallback onTap;

  const _DesktopNavItem({
    required this.focusNode,
    required this.item,
    required this.isSelected,
    required this.isCollapsed,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMoveRight,
    required this.onTap,
  });

  @override
  State<_DesktopNavItem> createState() => _DesktopNavItemState();
}

class _DesktopNavItemState extends State<_DesktopNavItem> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isHighlighted = _isFocused || _isHovered;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.0),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? const Color(0xFF1B1B22)
            : (isHighlighted ? AppColors.hoverState : Colors.transparent),
        borderRadius: AppRadii.control,
        border: Border.all(
          color: widget.isSelected
              ? AppColors.borderStrong
              : (_isFocused ? AppColors.accentPrimary : Colors.transparent),
          width: 1.0,
        ),
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Left selection indicator bar
          if (widget.isSelected)
            Positioned(
              left: 0,
              top: 10,
              bottom: 10,
              child: Container(
                width: 3.2,
                decoration: const BoxDecoration(
                  color: AppColors.accentPrimary,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
            ),

          // Icon + Label (Overflow-safe clipping during collapse/expand animation)
          Positioned.fill(
            child: widget.isCollapsed
                ? Center(
                    child: Icon(
                      widget.isSelected
                          ? widget.item.selectedIcon
                          : widget.item.icon,
                      color: widget.isSelected
                          ? AppColors.brandRed
                          : (isHighlighted
                                ? AppColors.textPrimary
                                : AppColors.textSecondary),
                      size: 20,
                    ),
                  )
                : ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 196,
                      maxWidth: 196,
                      minHeight: 38,
                      maxHeight: 38,
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Icon(
                            widget.isSelected
                                ? widget.item.selectedIcon
                                : widget.item.icon,
                            color: widget.isSelected
                                ? AppColors.brandRed
                                : (isHighlighted
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.item.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                color: widget.isSelected
                                    ? AppColors.textPrimary
                                    : (isHighlighted
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary),
                                fontSize: 13,
                                fontWeight: widget.isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                letterSpacing: 0.1,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );

    final itemWidget = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.isSelected,
      onFocusChange: (focused) {
        if (mounted) {
          setState(() => _isFocused = focused);
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          widget.onMoveUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          widget.onMoveDown();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          final moved = widget.onMoveRight();
          return moved ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.select) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _isHovered = false);
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: content,
        ),
      ),
    );

    if (widget.isCollapsed) {
      return Tooltip(
        message: widget.item.label,
        waitDuration: const Duration(milliseconds: 300),
        child: itemWidget,
      );
    }

    return itemWidget;
  }
}

// ── Backwards Compatibility Alias ──────────────────────────────────────────
