import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../core/focus/desktop_focus_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../services/storage_service.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/desktop_side_nav.dart';

final watchlistFilterProvider = StateProvider<String>((ref) => 'All');
final watchlistSortProvider = StateProvider<String>((ref) => 'Recently Added');

/// AniWings Desktop — Smart Watchlist Screen.
class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  late final ScrollController _scrollController;
  final List<FocusNode> _gridFocusNodes = [];

  static const List<String> _filters = [
    'All',
    'Currently Watching',
    'Plan to Watch',
    'Completed',
    'On Hold',
    'Dropped',
  ];

  static const List<String> _sorts = ['Recently Added', 'Rating', 'A-Z'];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!DesktopFocusManager.instance.restoreScreenFocus('/watchlist')) {
        if (_gridFocusNodes.isNotEmpty &&
            _gridFocusNodes.first.canRequestFocus) {
          _gridFocusNodes.first.requestFocus();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final node in _gridFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNodeFor(int index) {
    while (_gridFocusNodes.length <= index) {
      _gridFocusNodes.add(
        FocusNode(debugLabel: 'Watchlist Card ${_gridFocusNodes.length}'),
      );
    }
    return _gridFocusNodes[index];
  }

  List<Anime> _filterAndSort(
    List<Anime> original,
    String filter,
    String sort,
    StorageService storage,
  ) {
    var list = List<Anime>.from(original);

    // Filter by personal anime tracking status
    if (filter != 'All') {
      list = list.where((a) {
        final status = storage.getWatchlistStatus(a.id);
        return status.toLowerCase() == filter.toLowerCase();
      }).toList();
    }

    // Apply Sorting
    switch (sort) {
      case 'Rating':
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'A-Z':
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case 'Recently Added':
      default:
        // Keep order or reverse
        break;
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final storageService = ref.watch(storageServiceProvider);
    // Watch revision so list updates reactively on add/remove
    ref.watch(storageRevisionProvider);

    final rawWatchlist = storageService.getWatchlistAnime();
    final currentFilter = ref.watch(watchlistFilterProvider);
    final currentSort = ref.watch(watchlistSortProvider);

    final filteredList = _filterAndSort(
      rawWatchlist,
      currentFilter,
      currentSort,
      storageService,
    );

    final leftPadding = DesktopLayout.pageLeftPadding(context);
    final rightPadding = DesktopLayout.pagePadding(context);

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Stack(
        children: [
          const Positioned.fill(child: DesktopBackground()),
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(leftPadding, 24, rightPadding, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _buildHeader(rawWatchlist.length),

                  const SizedBox(height: 20),

                  // Filter & Sort Pills
                  _buildFilters(currentFilter, currentSort),

                  const SizedBox(height: 24),

                  // Watchlist Grid or Empty State
                  if (filteredList.isEmpty)
                    _buildEmptyState(context, rawWatchlist.isEmpty)
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      clipBehavior: Clip.none,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 215,
                            mainAxisExtent: 310,
                            crossAxisSpacing: 18,
                            mainAxisSpacing: 22,
                          ),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final anime = filteredList[index];
                        final node = _focusNodeFor(index);
                        return AnimeCard(
                          anime: anime,
                          registryKey: 'watchlist_card_$index',
                          focusNode: node,
                          width: double.infinity,
                          height: double.infinity,
                          layout: AnimeCardLayout.poster,
                          directionalKeyHandlers: {
                            if (index % 5 == 0)
                              LogicalKeyboardKey.arrowLeft: () {
                                DesktopFocusManager.instance
                                    .recordPreSidebarFocus(node);
                                DesktopSideNav.focusRail(context);
                              },
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int totalCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.brandRed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'YOUR LIBRARY',
                  style: TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Watchlist',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$totalCount titles',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilters(String currentFilter, String currentSort) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.panel,
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.filter_list_rounded,
            color: AppColors.brandRed,
            size: 18,
          ),
          const SizedBox(width: 10),

          // Status Filters
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isSelected = filter == currentFilter;

                  return DesktopFocusWrapper.builder(
                    onTap: () =>
                        ref.read(watchlistFilterProvider.notifier).state =
                            filter,
                    borderRadius: AppRadii.control,
                    builder: (context, isFocused, isHovered) {
                      final active = isFocused || isHovered;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.brandRed
                              : (active
                                    ? AppColors.hoverState
                                    : Colors.transparent),
                          borderRadius: AppRadii.control,
                          border: Border.all(
                            color: active
                                ? AppColors.borderStrong
                                : (isSelected
                                      ? AppColors.brandRed
                                      : AppColors.border),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            color: isSelected || active
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),

          const SizedBox(width: 12),
          Container(width: 1, height: 22, color: AppColors.border),
          const SizedBox(width: 12),

          // Sort Options
          ..._sorts.map((sort) {
            final isSelected = currentSort == sort;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: DesktopFocusWrapper.builder(
                onTap: () =>
                    ref.read(watchlistSortProvider.notifier).state = sort,
                borderRadius: AppRadii.control,
                builder: (context, isFocused, isHovered) {
                  final active = isFocused || isHovered;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.elevatedSurface
                          : (active
                                ? AppColors.hoverState
                                : Colors.transparent),
                      borderRadius: AppRadii.control,
                      border: Border.all(
                        color: active
                            ? AppColors.borderStrong
                            : (isSelected
                                  ? AppColors.brandRed
                                  : AppColors.border),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      sort,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.brandRed
                            : (active ? Colors.white : AppColors.textSecondary),
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isOverallEmpty) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.secondaryBg,
        borderRadius: AppRadii.dialog,
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.brandRed.withValues(alpha: 0.12),
              borderRadius: AppRadii.control,
              border: Border.all(
                color: AppColors.brandRed.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.bookmark_outline_rounded,
              color: AppColors.brandRed,
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isOverallEmpty
                ? 'Your Watchlist is empty'
                : 'No titles in this section',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isOverallEmpty
                ? 'Save your favorite anime series and movies here for quick access on your desktop.'
                : 'Try switching to "All" or adding anime to this collection category.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          DesktopFocusWrapper.builder(
            autofocus: true,
            onTap: () => context.go('/discover'),
            borderRadius: AppRadii.control,
            builder: (context, isFocused, isHovered) {
              final active = isFocused || isHovered;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: active ? AppColors.brandRedHover : AppColors.brandRed,
                  borderRadius: AppRadii.control,
                  border: Border.all(
                    color: active ? Colors.white : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.explore_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Discover Anime',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
