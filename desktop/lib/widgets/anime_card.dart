import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_colors.dart';
import '../core/focus/desktop_focus_manager.dart';
import '../core/focus/desktop_focus_node_registry.dart';
import '../models/anime.dart';
import '../services/storage_service.dart';
import 'web_safe_image.dart';

enum AnimeCardLayout { poster, landscape }

class AnimeCard extends ConsumerStatefulWidget {
  final Anime anime;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final AnimeCardLayout layout;
  final FocusNode? focusNode;
  final String? registryKey;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onCardFocused;
  final Map<LogicalKeyboardKey, VoidCallback> directionalKeyHandlers;

  const AnimeCard({
    super.key,
    required this.anime,
    this.onTap,
    this.width = 175,
    this.height = 255,
    this.layout = AnimeCardLayout.poster,
    this.focusNode,
    this.registryKey,
    this.onFocusChange,
    this.onCardFocused,
    this.directionalKeyHandlers = const {},
  });

  @override
  ConsumerState<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends ConsumerState<AnimeCard> {
  FocusNode? _fallbackFocusNode;
  bool _isFocused = false;
  bool _isHovered = false;

  FocusNode get _effectiveFocusNode {
    if (widget.focusNode != null) {
      if (widget.registryKey != null) {
        DesktopFocusNodeRegistry.instance.register(
          widget.registryKey!,
          widget.focusNode!,
        );
      }
      return widget.focusNode!;
    }
    if (widget.registryKey != null) {
      return DesktopFocusNodeRegistry.instance.getOrCreateNode(
        widget.registryKey!,
        debugLabel: 'AnimeCard ${widget.anime.title}',
      );
    }
    return _fallbackFocusNode ??= FocusNode(
      debugLabel: 'AnimeCard ${widget.anime.title}',
    );
  }

  @override
  void dispose() {
    _fallbackFocusNode?.dispose();
    super.dispose();
  }

  String _getAgeRating() {
    final genres = widget.anime.genres.map((g) => g.toLowerCase()).toList();
    if (genres.contains('hentai')) return '18+';
    if (genres.any(
      (g) =>
          g.contains('ecchi') ||
          g.contains('horror') ||
          g.contains('erotica') ||
          g.contains('violence'),
    )) {
      return 'R-17+';
    }
    if (genres.any(
      (g) =>
          g.contains('action') ||
          g.contains('drama') ||
          g.contains('psychological') ||
          g.contains('thriller') ||
          g.contains('mystery'),
    )) {
      return 'PG-13';
    }
    return 'PG';
  }

  void _handleTap(BuildContext context) {
    if (widget.registryKey != null) {
      try {
        final currentRoute = GoRouterState.of(context).matchedLocation;
        DesktopFocusManager.instance.saveScreenFocus(
          currentRoute,
          widget.registryKey!,
        );
      } catch (_) {}
    }
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      context.push('/anime/${widget.anime.id}');
    }
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final storage = ref.read(storageServiceProvider);
    final inWatchlist = storage.isInWatchlist(widget.anime.id);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.elevatedSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.control,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      elevation: 8,
      items: [
        PopupMenuItem<String>(
          value: 'play',
          height: 38,
          child: Row(
            children: const [
              Icon(
                Icons.play_arrow_rounded,
                color: AppColors.accentPrimary,
                size: 20,
              ),
              SizedBox(width: 10),
              Text(
                'Play',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'details',
          height: 38,
          child: Row(
            children: const [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.textPrimary,
                size: 18,
              ),
              SizedBox(width: 10),
              Text(
                'View Details',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'watchlist',
          height: 38,
          child: Row(
            children: [
              Icon(
                inWatchlist
                    ? Icons.bookmark_remove_rounded
                    : Icons.bookmark_add_rounded,
                color: AppColors.accentWarm,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                inWatchlist ? 'Remove from My List' : 'Add to My List',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          height: 38,
          child: Row(
            children: const [
              Icon(
                Icons.copy_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
              SizedBox(width: 10),
              Text(
                'Copy Title',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted || selected == null) return;

    switch (selected) {
      case 'play':
      case 'details':
        _handleTap(context);
        break;
      case 'watchlist':
        await storage.toggleWatchlist(widget.anime);
        if (context.mounted) {
          final nowIn = storage.isInWatchlist(widget.anime.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                nowIn
                    ? 'Added "${widget.anime.title}" to My List'
                    : 'Removed "${widget.anime.title}" from My List',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: widget.anime.title));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Title copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        break;
    }
  }

  void _ensureFocusedCardVisible() {
    if (!mounted || !_isFocused) return;
    DesktopFocusManager.ensureFocusedVisible(context);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isSelectKey =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (isSelectKey) {
      if (event is KeyDownEvent) {
        _handleTap(context);
      }
      return KeyEventResult.handled;
    }

    final handler = widget.directionalKeyHandlers[key];
    if (handler != null) {
      handler();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.layout == AnimeCardLayout.landscape) {
      return _buildLandscapeCard(context);
    }

    final ageRating = _getAgeRating();
    final bool useExpanded =
        widget.width.isInfinite || widget.height.isInfinite;
    final isActive = _isFocused || _isHovered;
    final year = widget.anime.year.trim();
    final cardMeta = [
      if (year.isNotEmpty) year,
      if (widget.anime.totalEpisodes > 0)
        '${widget.anime.totalEpisodes} EP'
      else if (widget.anime.genres.isNotEmpty)
        widget.anime.genres.first,
    ].join(' • ');

    Widget posterImageWidget = AnimatedContainer(
      duration: AppDurations.hover,
      curve: AppCurves.standard,
      width: useExpanded ? double.infinity : widget.width,
      height: useExpanded ? null : widget.height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(
          color: _isFocused
              ? Colors.white
              : _isHovered
              ? Colors.white.withValues(alpha: 0.35)
              : AppColors.borderSubtle,
          width: _isFocused ? 2.0 : 1.0,
        ),
        boxShadow: isActive
            ? const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ]
            : const [AppColors.shadowPoster],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(11)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster Image with dedicated cache sizing to prevent decode stutters
            WebSafeImage(
              url: widget.anime.posterUrl,
              fit: BoxFit.cover,
              cacheWidth: 300,
              cacheHeight: 440,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) => Container(
                color: AppColors.surface,
                child: const Center(
                  child: Icon(
                    Icons.movie_filter_rounded,
                    color: AppColors.textMuted,
                    size: 26,
                  ),
                ),
              ),
            ),

            // Age Rating Badge (Top Left)
            if (ageRating.isNotEmpty)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white12, width: 0.8),
                  ),
                  child: Text(
                    ageRating,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

            // Rating Badge (Top Right)
            if (widget.anime.rating > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white12, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF59E0B),
                        size: 11,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        widget.anime.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Subtle bottom gradient to ground artwork
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x66000000)],
                  ),
                ),
              ),
            ),

            // Subtle Play Overlay on Hover/Focus
            if (isActive)
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xE614141A),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandRed, width: 1.2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return RepaintBoundary(
      child: Focus(
        focusNode: _effectiveFocusNode,
        onFocusChange: (focused) {
          if (_isFocused != focused) {
            setState(() => _isFocused = focused);
          }
          widget.onFocusChange?.call(focused);
          if (focused) {
            widget.onCardFocused?.call();
            _ensureFocusedCardVisible();
          }
        },
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (mounted) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (mounted) setState(() => _isHovered = false);
          },
          child: GestureDetector(
            onTap: () => _handleTap(context),
            onSecondaryTapUp: (details) =>
                _showContextMenu(context, details.globalPosition),
            child: Semantics(
              button: true,
              label: 'Open ${widget.anime.title}',
              child: AnimatedScale(
                scale: isActive ? 1.018 : 1.0,
                duration: AppDurations.hover,
                curve: AppCurves.standard,
                child: SizedBox(
                  width: useExpanded ? null : widget.width,
                  child: useExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: posterImageWidget),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Text(
                                widget.anime.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (cardMeta.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 2,
                                ),
                                child: Text(
                                  cardMeta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            posterImageWidget,
                            const SizedBox(height: 8),
                            SizedBox(
                              width: widget.width,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.anime.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isActive
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: isActive
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        height: 1.2,
                                      ),
                                    ),
                                    if (cardMeta.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        cardMeta,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
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
    );
  }

  Widget _buildLandscapeCard(BuildContext context) {
    final imageUrl = widget.anime.backdropUrl.isNotEmpty
        ? widget.anime.backdropUrl
        : widget.anime.posterUrl;
    final useExpanded = widget.width.isInfinite || widget.height.isInfinite;
    final year = widget.anime.year.trim();
    final metadata = [
      if (year.isNotEmpty) year,
      if (widget.anime.totalEpisodes > 0) '${widget.anime.totalEpisodes} EP',
    ].join(' • ');

    final isActive = _isFocused || _isHovered;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: useExpanded ? double.infinity : widget.width,
      height: useExpanded ? double.infinity : widget.height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(
          color: _isFocused
              ? Colors.white
              : _isHovered
              ? AppColors.accentPrimary.withValues(alpha: 0.65)
              : AppColors.borderSubtle,
          width: _isFocused ? 2.0 : (_isHovered ? 1.2 : 1.0),
        ),
        boxShadow: isActive
            ? const [
                BoxShadow(
                  color: Color(0x4D000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ]
            : const [AppColors.shadowPoster],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(11)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            WebSafeImage(
              url: imageUrl,
              fit: BoxFit.cover,
              cacheWidth: 500,
              cacheHeight: 282,
              filterQuality: FilterQuality.medium,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x33000000),
                    Color(0xEE000000),
                  ],
                  stops: [0.35, 0.65, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.white12, width: 0.8),
                ),
                child: Text(
                  _getAgeRating(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (widget.anime.rating > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white12, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF59E0B),
                        size: 11,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        widget.anime.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isActive)
              Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accentPrimary,
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4D000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.anime.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFC6CED9),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return RepaintBoundary(
      child: Focus(
        focusNode: _effectiveFocusNode,
        onFocusChange: (focused) {
          if (_isFocused != focused) setState(() => _isFocused = focused);
          widget.onFocusChange?.call(focused);
          if (focused) {
            widget.onCardFocused?.call();
            _ensureFocusedCardVisible();
          }
        },
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (mounted) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (mounted) setState(() => _isHovered = false);
          },
          child: GestureDetector(
            onTap: () => _handleTap(context),
            onSecondaryTapUp: (details) =>
                _showContextMenu(context, details.globalPosition),
            child: Semantics(
              button: true,
              label: 'Open ${widget.anime.title}',
              child: AnimatedScale(
                scale: isActive ? 1.025 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
