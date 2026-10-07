import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../models/user.dart';
import '../../services/anime_service.dart';
import '../../services/storage_service.dart';
import '../../services/desktop_preferences.dart';
import '../../services/auth_service.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/loading_shimmer.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/desktop_side_nav.dart';
import '../../widgets/web_safe_image.dart';
import '../../widgets/social_follow_dialog.dart';
import '../../core/focus/desktop_focus_manager.dart';
import '../../core/focus/desktop_focus_node_registry.dart';

double _homeHeroHeight(BuildContext context) {
  final screenHeight = MediaQuery.sizeOf(context).height;
  return (screenHeight * 0.46).clamp(380.0, 480.0);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final Set<String> _dismissedAnimeIds = {};
  final Map<String, Future<Anime?>> _animeFutures = {};

  late final FocusNode _topSearchFocusNode;
  late final FocusNode _topProfileFocusNode;
  late final FocusNode _topSettingsFocusNode;

  late final FocusNode _heroFocusNode;
  late final FocusNode _continueWatchingFocusNode;
  late final FocusNode _trendingFocusNode;
  late final FocusNode _recentlyUpdatedFocusNode;
  late final FocusNode _newEpisodesFocusNode;
  late final FocusNode _popularFocusNode;
  late final FocusNode _recentlyAddedFocusNode;
  late final FocusNode _recommendedFocusNode;
  late final FocusNode _watchlistHighlightsFocusNode;
  late final FocusNode _discoverFocusNode;
  late final FocusNode _spotlightFocusNode;

  late final ScrollController _homeScrollController;
  final Map<String, ScrollController> _rowControllers = {};
  final Map<String, int> _rowCountMap = {};
  final Map<String, GlobalKey> _rowKeys = {};

  GlobalKey _getRowKey(String rowId) {
    return _rowKeys.putIfAbsent(rowId, () => GlobalKey());
  }

  bool _continueWatchingHovered = false;

  void _scrollContinueWatching(double delta) {
    final controller = _getScrollController('continue_watching');
    if (controller.hasClients) {
      final current = controller.offset;
      final target = (current + delta).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  ScrollController _getScrollController(String rowId) {
    return _rowControllers.putIfAbsent(rowId, () => ScrollController());
  }

  List<String> _getActiveRows(bool hasHistory, bool hasWatchlist) {
    return [
      if (hasHistory) 'continue_watching',
      'trending',
      'recently_updated',
      'new_episodes',
      'popular',
      'recently_added',
      'recommended',
      if (hasWatchlist) 'watchlist_highlights',
      'discover',
      'spotlight',
    ];
  }

  void _scrollToRow(String rowId) {
    final key = _rowKeys[rowId];
    final rowContext = key?.currentContext;
    if (rowContext != null && rowContext.mounted) {
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.12,
        duration: Duration.zero,
      );
    }
  }

  void _moveBetweenRows({
    required String fromRow,
    required bool isDown,
    required int currentIndex,
    required bool hasHistory,
    required bool hasWatchlist,
  }) {
    final rows = _getActiveRows(hasHistory, hasWatchlist);
    final current = rows.indexOf(fromRow);
    if (current < 0) return;
    final step = isDown ? 1 : -1;
    for (var i = current + step; i >= 0 && i < rows.length; i += step) {
      final target = rows[i];
      final count = _rowCountMap[target] ?? 0;
      if (count == 0) continue;
      _scrollToRow(target);
      DesktopFocusManager.instance.moveFocusBetweenRows(
        fromRowId: fromRow,
        toRowId: target,
        currentIndex: currentIndex,
        toRowCount: count,
        cardWidth:
            (target == 'continue_watching' || target == 'recently_updated')
            ? 260
            : 175,
        scrollController: _getScrollController(target),
      );
      return;
    }
    if (!isDown) {
      final hero = DesktopFocusNodeRegistry.instance.getNode('hero_watch_now');
      if (hero?.context != null && hero!.canRequestFocus) {
        hero.requestFocus();
      } else {
        _heroFocusNode.requestFocus();
      }
      _scrollToTop();
    }
  }

  void _moveFromHeroToFirstRow(int targetIndex, bool hasHistory) {
    final firstRow = hasHistory ? 'continue_watching' : 'trending';
    final savedIndex = DesktopFocusManager.instance.getRowFocusedIndex(
      firstRow,
    );
    final effectiveIndex = targetIndex > 0 ? targetIndex : savedIndex;
    final count = _rowCountMap[firstRow] ?? 10;
    final cardWidth = firstRow == 'continue_watching' ? 260.0 : 175.0;
    _scrollToRow(firstRow);
    DesktopFocusManager.instance.moveFocusBetweenRows(
      fromRowId: 'hero',
      toRowId: firstRow,
      currentIndex: effectiveIndex,
      toRowCount: count,
      cardWidth: cardWidth,
      scrollController: _getScrollController(firstRow),
      fallback: () {
        if (hasHistory && firstRow != 'trending') {
          final trendingCount = _rowCountMap['trending'] ?? 10;
          DesktopFocusManager.instance.moveFocusBetweenRows(
            fromRowId: 'hero',
            toRowId: 'trending',
            currentIndex: 0,
            toRowCount: trendingCount,
            cardWidth: 175.0,
            scrollController: _getScrollController('trending'),
          );
          _scrollToRow('trending');
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _homeScrollController = ScrollController();

    _topSearchFocusNode = FocusNode(debugLabel: 'Top Bar Search');
    _topProfileFocusNode = FocusNode(debugLabel: 'Top Bar Profile');
    _topSettingsFocusNode = FocusNode(debugLabel: 'Top Bar Settings');

    _heroFocusNode = FocusNode(debugLabel: 'Home Hero Slider');
    _continueWatchingFocusNode = FocusNode(debugLabel: 'Continue Watching Row');
    _trendingFocusNode = FocusNode(debugLabel: 'Hot Right Now Row');
    _recentlyUpdatedFocusNode = FocusNode(debugLabel: 'Recently Updated Row');
    _newEpisodesFocusNode = FocusNode(debugLabel: 'New Episodes Row');
    _popularFocusNode = FocusNode(debugLabel: 'Popular Anime Row');
    _recentlyAddedFocusNode = FocusNode(debugLabel: 'Recently Added Row');
    _recommendedFocusNode = FocusNode(debugLabel: 'Recommended For You Row');
    _watchlistHighlightsFocusNode = FocusNode(
      debugLabel: 'Watchlist Highlights Row',
    );
    _discoverFocusNode = FocusNode(debugLabel: 'Discover Something New Row');
    _spotlightFocusNode = FocusNode(debugLabel: 'Anime Spotlight Row');

    // Register all primary row focus nodes in the central registry
    DesktopFocusNodeRegistry.instance.register(
      'home_row_continue_watching_0',
      _continueWatchingFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_trending_0',
      _trendingFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_recently_updated_0',
      _recentlyUpdatedFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_new_episodes_0',
      _newEpisodesFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_popular_0',
      _popularFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_recently_added_0',
      _recentlyAddedFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_recommended_0',
      _recommendedFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_watchlist_highlights_0',
      _watchlistHighlightsFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_discover_0',
      _discoverFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'home_row_spotlight_0',
      _spotlightFocusNode,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!DesktopFocusManager.instance.restoreScreenFocus('/home')) {
        if (context.findAncestorWidgetOfExactType<DesktopSideNav>() != null) {
          DesktopSideNav.focusRail(context);
        } else {
          _heroFocusNode.requestFocus();
        }
      }
      _checkAndShowSocialPopup();
    });
  }

  void _checkAndShowSocialPopup() {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') return;
    final storage = ref.read(storageServiceProvider);
    if (!storage.getHideSocialPopupForever()) {
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.75),
        builder: (context) => const SocialFollowDialog(),
      );
    }
  }

  @override
  void dispose() {
    _homeScrollController.dispose();
    for (final c in _rowControllers.values) {
      c.dispose();
    }

    DesktopFocusNodeRegistry.instance.unregister(
      'home_row_continue_watching_0',
    );
    DesktopFocusNodeRegistry.instance.unregister('home_row_trending_0');
    DesktopFocusNodeRegistry.instance.unregister('home_row_recently_updated_0');
    DesktopFocusNodeRegistry.instance.unregister('home_row_new_episodes_0');
    DesktopFocusNodeRegistry.instance.unregister('home_row_popular_0');
    DesktopFocusNodeRegistry.instance.unregister('home_row_recently_added_0');
    DesktopFocusNodeRegistry.instance.unregister('home_row_recommended_0');
    DesktopFocusNodeRegistry.instance.unregister(
      'home_row_watchlist_highlights_0',
    );
    DesktopFocusNodeRegistry.instance.unregister('home_row_discover_0');
    DesktopFocusNodeRegistry.instance.unregister('home_row_spotlight_0');

    void safeDispose(FocusNode node) {
      try {
        node.dispose();
      } catch (_) {}
    }

    safeDispose(_topSearchFocusNode);
    safeDispose(_topProfileFocusNode);
    safeDispose(_topSettingsFocusNode);

    safeDispose(_heroFocusNode);
    safeDispose(_continueWatchingFocusNode);
    safeDispose(_trendingFocusNode);
    safeDispose(_recentlyUpdatedFocusNode);
    safeDispose(_newEpisodesFocusNode);
    safeDispose(_popularFocusNode);
    safeDispose(_recentlyAddedFocusNode);
    safeDispose(_recommendedFocusNode);
    safeDispose(_watchlistHighlightsFocusNode);
    safeDispose(_discoverFocusNode);
    safeDispose(_spotlightFocusNode);
    super.dispose();
  }

  void _scrollToTop() {
    if (_homeScrollController.hasClients) {
      _homeScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildHeroShimmer() {
    return LoadingShimmer(
      child: Container(
        width: double.infinity,
        height: _homeHeroHeight(context),
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: AppRadii.panel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(animeServiceProvider, (previous, next) {
      if (previous != next) _animeFutures.clear();
    });
    final animeService = ref.watch(animeServiceProvider);
    final storageService = ref.watch(storageServiceProvider);
    final user = ref.watch(authStateProvider);
    final activeUserId = user?.id ?? StorageService.guestWatchHistoryUserId;
    // Watch storage revision so watchlist changes trigger rebuild
    ref.watch(storageRevisionProvider);

    final trendingAsync = ref.watch(trendingAnimeProvider);

    final rawHistory = storageService.getWatchHistory(userId: activeUserId);
    final history = rawHistory
        .where(
          (entry) =>
              !entry.isExternalSync &&
              !_dismissedAnimeIds.contains(entry.animeId),
        )
        .toList();

    final hasHistory = history.isNotEmpty;
    final watchlistAnime = storageService.getWatchlistAnime();

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Stack(
        children: [
          const Positioned.fill(child: DesktopBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A. PINNED TOP NAVIGATION BAR
                Container(
                  color: AppColors.primaryBg,
                  padding: EdgeInsets.fromLTRB(
                    DesktopLayout.pageLeftPadding(context),
                    14,
                    DesktopLayout.pagePadding(context),
                    10,
                  ),
                  child: _buildTopNavigationBar(context, user),
                ),

                // B. INDEPENDENTLY SCROLLING CONTENT
                Expanded(
                  child: SingleChildScrollView(
                    controller: _homeScrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // HERO BANNER
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            DesktopLayout.pageLeftPadding(context),
                            4,
                            DesktopLayout.pagePadding(context),
                            0,
                          ),
                          child: ClipRRect(
                            borderRadius: AppRadii.panel,
                            child: trendingAsync.when(
                              data: (trending) => trending.isEmpty
                                  ? const SizedBox.shrink()
                                  : HomeHeroSlider(
                                      trending: trending,
                                      focusNode: _heroFocusNode,
                                      onNavigateUp: () =>
                                          _topSearchFocusNode.requestFocus(),
                                      onNavigateDown: () =>
                                          _moveFromHeroToFirstRow(
                                            0,
                                            hasHistory,
                                          ),
                                    ),
                              loading: () => _buildHeroShimmer(),
                              error: (_, _) => const SizedBox(
                                height: 240,
                                child: DesktopEmptyState(
                                  icon: Icons.cloud_off_rounded,
                                  title: 'Featured titles unavailable',
                                  message: 'Could not connect to service.',
                                ),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: DesktopLayout.sectionGap(context)),

                        // C. CONTENT ROWS

                        // 1. CONTINUE WATCHING
                        if (hasHistory) ...[
                          KeyedSubtree(
                            key: _getRowKey('continue_watching'),
                            child: _buildContinueWatching(
                              context,
                              history,
                              animeService,
                              activeUserId,
                              watchlistAnime.isNotEmpty,
                            ),
                          ),
                          SizedBox(height: DesktopLayout.sectionGap(context)),
                        ],

                        // 2. TRENDING ANIME (Top 10 Ranked)
                        HomeCategoryRow(
                          key: _getRowKey('trending'),
                          rowId: 'trending',
                          title: 'Top 10 Trending This Week',
                          isRanked: true,
                          provider: trendingAnimeProvider,
                          firstCardFocusNode: _trendingFocusNode,
                          scrollController: _getScrollController('trending'),
                          onSeeAll: () => context.go('/discover'),
                          onDataLoaded: (cnt) => _rowCountMap['trending'] = cnt,
                          onNavigateDownWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'trending',
                            isDown: true,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                          onNavigateUpWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'trending',
                            isDown: false,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                        ),

                        // 3. RECENTLY UPDATED (Landscape card format for episodes)
                        HomeCategoryRow(
                          key: _getRowKey('recently_updated'),
                          rowId: 'recently_updated',
                          title: 'Recently Updated',
                          provider: recentlyUpdatedProvider,
                          layout: AnimeCardLayout.landscape,
                          cardWidth: 260,
                          cardHeight: 146,
                          firstCardFocusNode: _recentlyUpdatedFocusNode,
                          scrollController: _getScrollController(
                            'recently_updated',
                          ),
                          onSeeAll: () => context.go('/discover'),
                          onDataLoaded: (cnt) =>
                              _rowCountMap['recently_updated'] = cnt,
                          onNavigateDownWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'recently_updated',
                            isDown: true,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                          onNavigateUpWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'recently_updated',
                            isDown: false,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                        ),

                        // 4. NEW EPISODES
                        HomeCategoryRow(
                          key: _getRowKey('new_episodes'),
                          rowId: 'new_episodes',
                          title: 'New Episodes & Premieres',
                          provider: upcomingAnimeProvider,
                          firstCardFocusNode: _newEpisodesFocusNode,
                          scrollController: _getScrollController(
                            'new_episodes',
                          ),
                          onSeeAll: () => context.go('/discover'),
                          onDataLoaded: (cnt) =>
                              _rowCountMap['new_episodes'] = cnt,
                          onNavigateDownWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'new_episodes',
                            isDown: true,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                          onNavigateUpWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'new_episodes',
                            isDown: false,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                        ),

                        // 5. POPULAR ANIME
                        HomeCategoryRow(
                          key: _getRowKey('popular'),
                          rowId: 'popular',
                          title: 'Popular Anime',
                          provider: everyonesWatchingProvider,
                          firstCardFocusNode: _popularFocusNode,
                          scrollController: _getScrollController('popular'),
                          onSeeAll: () => context.go('/discover'),
                          onDataLoaded: (cnt) => _rowCountMap['popular'] = cnt,
                          onNavigateDownWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'popular',
                            isDown: true,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                          onNavigateUpWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'popular',
                            isDown: false,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                        ),

                        // 6. RECENTLY ADDED
                        HomeCategoryRow(
                          key: _getRowKey('recently_added'),
                          rowId: 'recently_added',
                          title: 'Recently Added',
                          provider: topPicksProvider,
                          firstCardFocusNode: _recentlyAddedFocusNode,
                          scrollController: _getScrollController(
                            'recently_added',
                          ),
                          onSeeAll: () => context.go('/discover'),
                          onDataLoaded: (cnt) =>
                              _rowCountMap['recently_added'] = cnt,
                          onNavigateDownWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'recently_added',
                            isDown: true,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                          onNavigateUpWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'recently_added',
                            isDown: false,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                        ),

                        // 7. RECOMMENDED FOR YOU
                        HomeCategoryRow(
                          key: _getRowKey('recommended'),
                          rowId: 'recommended',
                          title: 'Recommended for You',
                          provider: curatedForYouProvider,
                          firstCardFocusNode: _recommendedFocusNode,
                          scrollController: _getScrollController('recommended'),
                          onSeeAll: () => context.go('/discover'),
                          onDataLoaded: (cnt) =>
                              _rowCountMap['recommended'] = cnt,
                          onNavigateDownWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'recommended',
                            isDown: true,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                          onNavigateUpWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'recommended',
                            isDown: false,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                        ),

                        // 8. WATCHLIST HIGHLIGHTS
                        if (watchlistAnime.isNotEmpty) ...[
                          KeyedSubtree(
                            key: _getRowKey('watchlist_highlights'),
                            child: _buildWatchlistRow(
                              context,
                              watchlistAnime,
                              hasHistory,
                            ),
                          ),
                          SizedBox(height: DesktopLayout.sectionGap(context)),
                        ],

                        // 9. DISCOVER SOMETHING NEW
                        HomeCategoryRow(
                          key: _getRowKey('discover'),
                          rowId: 'discover',
                          title: 'Discover Something New',
                          provider: scheduleProvider,
                          firstCardFocusNode: _discoverFocusNode,
                          scrollController: _getScrollController('discover'),
                          onSeeAll: () => context.go('/discover'),
                          onDataLoaded: (cnt) => _rowCountMap['discover'] = cnt,
                          onNavigateDownWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'discover',
                            isDown: true,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                          onNavigateUpWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'discover',
                            isDown: false,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                        ),

                        // 10. ANIME SPOTLIGHT
                        HomeCategoryRow(
                          key: _getRowKey('spotlight'),
                          rowId: 'spotlight',
                          title: 'Anime Spotlight',
                          provider: hotRightNowProvider,
                          firstCardFocusNode: _spotlightFocusNode,
                          scrollController: _getScrollController('spotlight'),
                          onSeeAll: () => context.go('/discover'),
                          onDataLoaded: (cnt) =>
                              _rowCountMap['spotlight'] = cnt,
                          onNavigateUpWithIndex: (idx) => _moveBetweenRows(
                            fromRow: 'spotlight',
                            isDown: false,
                            currentIndex: idx,
                            hasHistory: hasHistory,
                            hasWatchlist: watchlistAnime.isNotEmpty,
                          ),
                        ),

                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _moveDownFromTopBar() {
    final watchNow = DesktopFocusNodeRegistry.instance.getNode(
      'hero_watch_now',
    );
    if (watchNow != null &&
        watchNow.context != null &&
        watchNow.canRequestFocus) {
      watchNow.requestFocus();
    } else {
      _heroFocusNode.requestFocus();
    }
  }

  // --- Desktop Top Header Bar ---
  Widget _buildTopNavigationBar(BuildContext context, User? user) {
    return LayoutBuilder(
      builder: (context, bounds) => Row(
        children: [
          // Desktop Search Bar
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, minWidth: 260),
            child: DesktopFocusWrapper(
              focusNode: _topSearchFocusNode,
              onTap: () => context.go('/search'),
              borderRadius: AppRadii.control,
              directionalKeyHandlers: {
                LogicalKeyboardKey.arrowLeft: () {
                  DesktopFocusManager.instance.recordPreSidebarFocus(
                    _topSearchFocusNode,
                  );
                  DesktopSideNav.focusRail(context);
                },
                LogicalKeyboardKey.arrowDown: _moveDownFromTopBar,
                LogicalKeyboardKey.arrowRight: () =>
                    _topProfileFocusNode.requestFocus(),
              },
              builder: (context, focused, hovered) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: focused
                        ? const Color(0xFF141414)
                        : (hovered
                              ? const Color(0xFF111111)
                              : const Color(0xFF0A0A0A)),
                    borderRadius: AppRadii.control,
                    border: Border.all(
                      color: focused
                          ? AppColors.brandRed
                          : (hovered
                                ? const Color(0xFF2E2E2E)
                                : const Color(0xFF1E1E1E)),
                      width: focused ? 1.4 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: focused
                            ? AppColors.brandRed
                            : AppColors.textMuted,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Search anime, movies, genres...',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x12FFFFFF),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0x18FFFFFF)),
                        ),
                        child: const Text(
                          'Ctrl + K',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          if (bounds.maxWidth >= 1180) ...[
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTopNavChip(
                  context,
                  'Discover',
                  '/discover',
                  Icons.explore_outlined,
                ),
                const SizedBox(width: 8),
                _buildTopNavChip(
                  context,
                  'Top Movies',
                  '/top-movies',
                  Icons.movie_outlined,
                ),
                const SizedBox(width: 8),
                _buildTopNavChip(
                  context,
                  'Hot Now',
                  '/hot-right-now',
                  Icons.local_fire_department_outlined,
                ),
              ],
            ),
          ],

          const Spacer(),

          // User Profile Pill
          DesktopFocusWrapper(
            focusNode: _topProfileFocusNode,
            onTap: () => context.go('/profile'),
            borderRadius: AppRadii.control,
            directionalKeyHandlers: {
              LogicalKeyboardKey.arrowLeft: () =>
                  _topSearchFocusNode.requestFocus(),
              LogicalKeyboardKey.arrowDown: _moveDownFromTopBar,
              LogicalKeyboardKey.arrowRight: () =>
                  _topSettingsFocusNode.requestFocus(),
            },
            builder: (context, focused, hovered) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: focused
                      ? const Color(0xFF141414)
                      : (hovered
                            ? const Color(0xFF111111)
                            : const Color(0xFF0A0A0A)),
                  borderRadius: AppRadii.control,
                  border: Border.all(
                    color: focused
                        ? AppColors.brandRed
                        : (hovered
                              ? const Color(0xFF2E2E2E)
                              : const Color(0xFF1E1E1E)),
                    width: focused ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.elevatedSurface,
                      foregroundImage:
                          user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                          ? (user.avatarUrl!.startsWith('assets/')
                                ? AssetImage(user.avatarUrl!) as ImageProvider
                                : NetworkImage(user.avatarUrl!))
                          : null,
                      child: user?.avatarUrl == null || user!.avatarUrl!.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 14,
                              color: AppColors.textSecondary,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: Text(
                        user?.username ?? 'Guest',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          // Settings Quick Button
          DesktopFocusWrapper(
            focusNode: _topSettingsFocusNode,
            onTap: () => context.go('/settings'),
            borderRadius: AppRadii.control,
            directionalKeyHandlers: {
              LogicalKeyboardKey.arrowLeft: () =>
                  _topProfileFocusNode.requestFocus(),
              LogicalKeyboardKey.arrowDown: _moveDownFromTopBar,
            },
            builder: (context, focused, hovered) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: focused
                      ? const Color(0xFF141414)
                      : (hovered
                            ? const Color(0xFF111111)
                            : const Color(0xFF0A0A0A)),
                  borderRadius: AppRadii.control,
                  border: Border.all(
                    color: focused
                        ? AppColors.brandRed
                        : (hovered
                              ? const Color(0xFF2E2E2E)
                              : const Color(0xFF1E1E1E)),
                    width: focused ? 1.4 : 1,
                  ),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: focused ? AppColors.brandRed : AppColors.textMuted,
                  size: 19,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavChip(
    BuildContext context,
    String label,
    String route,
    IconData icon,
  ) {
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: AppRadii.control,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.control,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Watchlist Row ---
  Widget _buildWatchlistRow(
    BuildContext context,
    List<Anime> watchlistAnime,
    bool hasHistory,
  ) {
    _rowCountMap['watchlist_highlights'] = watchlistAnime.length;
    final leftPadding = DesktopLayout.pageLeftPadding(context);
    final rightPadding = DesktopLayout.pagePadding(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: leftPadding, right: rightPadding),
          child: DesktopSectionHeader(
            title: 'Watchlist Highlights',
            subtitle: 'From your personal saved collection',
            trailing: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              onPressed: () => context.go('/watchlist'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text(
                'View All',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 345,
          child: ListView.builder(
            controller: _getScrollController('watchlist_highlights'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
            itemCount: watchlistAnime.length,
            padding: EdgeInsets.only(
              left: leftPadding,
              right: rightPadding,
              top: 8,
              bottom: 8,
            ),
            itemBuilder: (context, index) {
              _rowCountMap['watchlist_highlights'] = watchlistAnime.length;
              final isFirst = index == 0;
              final directionalHandlers = <LogicalKeyboardKey, VoidCallback>{
                LogicalKeyboardKey.arrowDown: () => _moveBetweenRows(
                  fromRow: 'watchlist_highlights',
                  isDown: true,
                  currentIndex: index,
                  hasHistory: hasHistory,
                  hasWatchlist: true,
                ),
                LogicalKeyboardKey.pageDown: () => _moveBetweenRows(
                  fromRow: 'watchlist_highlights',
                  isDown: true,
                  currentIndex: index,
                  hasHistory: hasHistory,
                  hasWatchlist: true,
                ),
                LogicalKeyboardKey.channelDown: () => _moveBetweenRows(
                  fromRow: 'watchlist_highlights',
                  isDown: true,
                  currentIndex: index,
                  hasHistory: hasHistory,
                  hasWatchlist: true,
                ),
                LogicalKeyboardKey.arrowUp: () => _moveBetweenRows(
                  fromRow: 'watchlist_highlights',
                  isDown: false,
                  currentIndex: index,
                  hasHistory: hasHistory,
                  hasWatchlist: true,
                ),
                LogicalKeyboardKey.pageUp: () => _moveBetweenRows(
                  fromRow: 'watchlist_highlights',
                  isDown: false,
                  currentIndex: index,
                  hasHistory: hasHistory,
                  hasWatchlist: true,
                ),
                LogicalKeyboardKey.channelUp: () => _moveBetweenRows(
                  fromRow: 'watchlist_highlights',
                  isDown: false,
                  currentIndex: index,
                  hasHistory: hasHistory,
                  hasWatchlist: true,
                ),
              };

              final isLast = index == watchlistAnime.length - 1;

              if (isFirst) {
                directionalHandlers[LogicalKeyboardKey.arrowLeft] = () {
                  DesktopSideNav.focusRail(context);
                };
              }
              if (isLast) {
                directionalHandlers[LogicalKeyboardKey.arrowRight] = () {};
              }

              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: AnimeCard(
                  anime: watchlistAnime[index],
                  width: 175,
                  height: 255,
                  registryKey: 'home_row_watchlist_highlights_$index',
                  onCardFocused: () {
                    DesktopFocusManager.instance.recordRowFocus(
                      'watchlist_highlights',
                      index,
                    );
                  },
                  focusNode: isFirst ? _watchlistHighlightsFocusNode : null,
                  directionalKeyHandlers: directionalHandlers,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- Continue Watching Row ---
  Widget _buildContinueWatching(
    BuildContext context,
    List<dynamic> history,
    AnimeService service,
    String activeUserId,
    bool hasWatchlist,
  ) {
    _rowCountMap['continue_watching'] = history.length;
    final leftPadding = DesktopLayout.pageLeftPadding(context);
    final rightPadding = DesktopLayout.pagePadding(context);
    const cardWidth = 260.0;
    const cardHeight = 146.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: leftPadding, right: rightPadding),
          child: DesktopSectionHeader(
            title: 'Continue Watching',
            subtitle: 'Pick up where you left off',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () => context.go('/history'),
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text(
                    'Timeline',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () async {
                    await ref
                        .read(storageServiceProvider)
                        .clearWatchHistory(userId: activeUserId);
                    if (!mounted) return;
                    setState(() {});
                  },
                  child: const Text(
                    'Clear history',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        MouseRegion(
          onEnter: (_) => setState(() => _continueWatchingHovered = true),
          onExit: (_) => setState(() => _continueWatchingHovered = false),
          child: SizedBox(
            height: 195,
            child: Stack(
              children: [
                ListView.builder(
                  controller: _getScrollController('continue_watching'),
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
                  itemCount: history.length,
                  padding: EdgeInsets.only(
                    left: leftPadding,
                    right: rightPadding,
                    top: 6,
                    bottom: 6,
                  ),
                  itemBuilder: (context, index) {
                    _rowCountMap['continue_watching'] = history.length;
                    final isFirst = index == 0;
                    final entry = history[index];
                    final directionalHandlers =
                        <LogicalKeyboardKey, VoidCallback>{
                          LogicalKeyboardKey.arrowUp: () => _moveBetweenRows(
                            fromRow: 'continue_watching',
                            isDown: false,
                            currentIndex: index,
                            hasHistory: true,
                            hasWatchlist: hasWatchlist,
                          ),
                          LogicalKeyboardKey.pageUp: () => _moveBetweenRows(
                            fromRow: 'continue_watching',
                            isDown: false,
                            currentIndex: index,
                            hasHistory: true,
                            hasWatchlist: hasWatchlist,
                          ),
                          LogicalKeyboardKey.channelUp: () => _moveBetweenRows(
                            fromRow: 'continue_watching',
                            isDown: false,
                            currentIndex: index,
                            hasHistory: true,
                            hasWatchlist: hasWatchlist,
                          ),
                          LogicalKeyboardKey.arrowDown: () => _moveBetweenRows(
                            fromRow: 'continue_watching',
                            isDown: true,
                            currentIndex: index,
                            hasHistory: true,
                            hasWatchlist: hasWatchlist,
                          ),
                          LogicalKeyboardKey.pageDown: () => _moveBetweenRows(
                            fromRow: 'continue_watching',
                            isDown: true,
                            currentIndex: index,
                            hasHistory: true,
                            hasWatchlist: hasWatchlist,
                          ),
                          LogicalKeyboardKey.channelDown: () =>
                              _moveBetweenRows(
                                fromRow: 'continue_watching',
                                isDown: true,
                                currentIndex: index,
                                hasHistory: true,
                                hasWatchlist: hasWatchlist,
                              ),
                        };

                    final isLast = index == history.length - 1;

                    if (isFirst) {
                      directionalHandlers[LogicalKeyboardKey.arrowLeft] = () {
                        DesktopSideNav.focusRail(context);
                      };
                    }
                    if (isLast) {
                      directionalHandlers[LogicalKeyboardKey.arrowRight] =
                          () {};
                    }

                    return FutureBuilder<Anime?>(
                      future: _animeFutures.putIfAbsent(
                        entry.animeId,
                        () => service.getAnimeById(entry.animeId),
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Container(
                            width: cardWidth,
                            height: cardHeight,
                            margin: const EdgeInsets.only(right: 14),
                            child: LoadingShimmer(
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppColors.cardSurface,
                                  borderRadius: AppRadii.card,
                                ),
                              ),
                            ),
                          );
                        }
                        final anime = snapshot.data;
                        if (anime == null) return const SizedBox.shrink();

                        double percent;
                        if (entry.isCompleted) {
                          percent = 1.0;
                        } else {
                          final duration = entry.watchedDuration;
                          final totalSec =
                              (anime.episodeDurationMinutes > 0
                                      ? anime.episodeDurationMinutes * 60
                                      : 1440)
                                  .clamp(1, 24 * 60 * 60);
                          percent = (duration.inSeconds / totalSec).clamp(
                            0.0,
                            1.0,
                          );
                        }

                        void openWatch() {
                          final episodeNumber = entry.lastWatchedEpisode <= 0
                              ? 1
                              : entry.lastWatchedEpisode;
                          final episodeId = '${anime.id}_ep_$episodeNumber';
                          context.push('/watch/${anime.id}/$episodeId');
                        }

                        final coverUrl = (anime.backdropUrl.trim().isNotEmpty)
                            ? anime.backdropUrl
                            : anime.posterUrl;

                        final card = Container(
                          width: cardWidth,
                          height: cardHeight,
                          decoration: BoxDecoration(
                            color: AppColors.cardSurface,
                            borderRadius: AppRadii.card,
                            border: Border.all(
                              color: AppColors.borderSubtle,
                              width: 1,
                            ),
                            boxShadow: const [AppColors.shadowSoft],
                          ),
                          child: ClipRRect(
                            borderRadius: AppRadii.card,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                WebSafeImage(
                                  url: coverUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 480,
                                  cacheHeight: 270,
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.3),
                                        Colors.black.withValues(alpha: 0.9),
                                      ],
                                      stops: const [0.0, 0.45, 1.0],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 10,
                                  left: 10,
                                  right: 10,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.accentPrimary,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'EP ${entry.lastWatchedEpisode}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          const Icon(
                                            Icons.play_circle_fill_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        anime.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: Container(
                                          height: 4,
                                          color: Colors.white24,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: FractionallySizedBox(
                                              widthFactor: percent.clamp(
                                                0.0,
                                                1.0,
                                              ),
                                              child: Container(
                                                color: AppColors.accentPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );

                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: RepaintBoundary(
                            child: DesktopFocusWrapper(
                              registryKey: 'home_row_continue_watching_$index',
                              focusNode: isFirst
                                  ? _continueWatchingFocusNode
                                  : null,
                              directionalKeyHandlers: directionalHandlers,
                              onFocusChange: (focused) {
                                if (focused) {
                                  DesktopFocusManager.instance.recordRowFocus(
                                    'continue_watching',
                                    index,
                                  );
                                }
                              },
                              onTap: () {
                                DesktopFocusManager.instance.saveScreenFocus(
                                  '/home',
                                  'home_row_continue_watching_$index',
                                );
                                openWatch();
                              },
                              borderRadius: AppRadii.card,
                              focusedScale: 1.03,
                              child: card,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                // Left Desktop Scroll Chevron
                if (_continueWatchingHovered)
                  Positioned(
                    left: leftPadding - 6,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: InkWell(
                        onTap: () =>
                            _scrollContinueWatching(-(cardWidth + 14) * 2),
                        borderRadius: AppRadii.control,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.elevatedSurface.withValues(
                              alpha: 0.95,
                            ),
                            borderRadius: AppRadii.control,
                            border: Border.all(color: AppColors.border),
                            boxShadow: const [AppColors.shadowSoft],
                          ),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Right Desktop Scroll Chevron
                if (_continueWatchingHovered)
                  Positioned(
                    right: rightPadding - 6,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: InkWell(
                        onTap: () =>
                            _scrollContinueWatching((cardWidth + 14) * 2),
                        borderRadius: AppRadii.control,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.elevatedSurface.withValues(
                              alpha: 0.95,
                            ),
                            borderRadius: AppRadii.control,
                            border: Border.all(color: AppColors.border),
                            boxShadow: const [AppColors.shadowSoft],
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- Hero Banner Slider ---
class HomeHeroSlider extends ConsumerStatefulWidget {
  final List<Anime> trending;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateUp;
  final FocusNode? focusNode;

  const HomeHeroSlider({
    super.key,
    required this.trending,
    this.onNavigateDown,
    this.onNavigateUp,
    this.focusNode,
  });

  @override
  ConsumerState<HomeHeroSlider> createState() => _HomeHeroSliderState();
}

class _HomeHeroSliderState extends ConsumerState<HomeHeroSlider> {
  late final FocusNode _internalFocusNode;
  late final FocusNode _watchNowFocusNode;
  late final FocusNode _detailsFocusNode;
  late final FocusNode _watchlistFocusNode;

  FocusNode get _heroFocusNode => widget.focusNode ?? _internalFocusNode;
  Timer? _sliderTimer;
  bool _heroHasFocus = false;
  bool _heroIsHovered = false;
  int _activeSlideIndex = 0;
  final Set<String> _warmedBackdrops = {};

  List<Anime> get _dailySlides => widget.trending.take(6).toList();

  bool get _hasAnyHeroFocus =>
      _heroFocusNode.hasFocus ||
      _watchNowFocusNode.hasFocus ||
      _detailsFocusNode.hasFocus ||
      _watchlistFocusNode.hasFocus ||
      _heroIsHovered;

  @override
  void initState() {
    super.initState();
    _watchNowFocusNode = FocusNode(debugLabel: 'Hero Watch Now');
    _detailsFocusNode = FocusNode(debugLabel: 'Hero Details');
    _watchlistFocusNode = FocusNode(debugLabel: 'Hero Watchlist');

    DesktopFocusNodeRegistry.instance.register(
      'hero_watch_now',
      _watchNowFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'hero_details',
      _detailsFocusNode,
    );
    DesktopFocusNodeRegistry.instance.register(
      'hero_watchlist',
      _watchlistFocusNode,
    );

    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode(debugLabel: 'Home hero banner');
    }
    _heroFocusNode.addListener(_syncHeroFocus);
    _startSliderTimer();
    _warmNextBackdrop();
  }

  @override
  void didUpdateWidget(covariant HomeHeroSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _warmNextBackdrop();
  }

  void _warmNextBackdrop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dailySlides.isEmpty) return;
      final next = _dailySlides[(_activeSlideIndex + 1) % _dailySlides.length];
      final url = next.backdropUrl.isNotEmpty
          ? next.backdropUrl
          : next.posterUrl;
      if (url.isEmpty || !_warmedBackdrops.add(url)) return;
      unawaited(
        precacheImage(
          WebSafeImage.provider(
            url,
            cacheWidth: WebSafeImage.homeBackdropCacheWidth,
          ),
          context,
          onError: (_, _) => _warmedBackdrops.remove(url),
        ),
      );
    });
  }

  @override
  void dispose() {
    _sliderTimer?.cancel();
    DesktopFocusNodeRegistry.instance.unregister('hero_watch_now');
    DesktopFocusNodeRegistry.instance.unregister('hero_details');
    DesktopFocusNodeRegistry.instance.unregister('hero_watchlist');
    _watchNowFocusNode.dispose();
    _detailsFocusNode.dispose();
    _watchlistFocusNode.dispose();
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    _heroFocusNode.removeListener(_syncHeroFocus);
    super.dispose();
  }

  void _syncHeroFocus() {
    if (!mounted) return;
    final focused = _heroFocusNode.hasPrimaryFocus;
    if (_heroHasFocus != focused) setState(() => _heroHasFocus = focused);
  }

  void _showSlide(int index) {
    if (!mounted || _dailySlides.isEmpty) return;
    setState(() => _activeSlideIndex = index % _dailySlides.length);
    _warmNextBackdrop();
  }

  void _startSliderTimer() {
    _sliderTimer?.cancel();
    _sliderTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_hasAnyHeroFocus) return;
      final slidesCount = _dailySlides.length;
      if (slidesCount == 0) return;
      final next = (_activeSlideIndex + 1) % slidesCount;
      _showSlide(next);
    });
  }

  KeyEventResult _handleHeroKey(FocusNode node, KeyEvent event) {
    if (FocusManager.instance.primaryFocus != node) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isDownKey =
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.channelDown;
    if (isDownKey) {
      if (_watchNowFocusNode.canRequestFocus) {
        _watchNowFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (widget.onNavigateDown != null) {
        widget.onNavigateDown!();
        return KeyEventResult.handled;
      }
    }

    final isUpKey =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.channelUp;
    if (isUpKey && widget.onNavigateUp != null) {
      widget.onNavigateUp!();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_activeSlideIndex == 0) {
        return KeyEventResult.ignored;
      }
      if (_dailySlides.isNotEmpty) {
        final prev =
            (_activeSlideIndex - 1 + _dailySlides.length) % _dailySlides.length;
        _showSlide(prev);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (_dailySlides.isNotEmpty) {
        final next = (_activeSlideIndex + 1) % _dailySlides.length;
        _showSlide(next);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      final slides = _dailySlides;
      if (slides.isEmpty) return KeyEventResult.ignored;
      context.push('/anime/${slides[_activeSlideIndex].id}');
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final slides = _dailySlides;
    if (slides.isEmpty) return const SizedBox.shrink();

    final heroHeight = _homeHeroHeight(context);
    final isHeroActive = _heroHasFocus;
    final storageService = ref.watch(storageServiceProvider);

    return Focus(
      focusNode: _heroFocusNode,
      onKeyEvent: _handleHeroKey,
      onFocusChange: (focused) {
        if (focused) {
          _sliderTimer?.cancel();
        } else {
          _startSliderTimer();
        }
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) {
            setState(() => _heroIsHovered = true);
            _sliderTimer?.cancel();
          }
        },
        onExit: (_) {
          if (mounted) {
            setState(() => _heroIsHovered = false);
            if (!_heroHasFocus) _startSliderTimer();
          }
        },
        child: AnimatedContainer(
          key: const ValueKey('home-hero-frame'),
          duration: AppDurations.quick,
          curve: AppCurves.standard,
          height: heroHeight,
          decoration: BoxDecoration(
            borderRadius: AppRadii.panel,
            border: Border.all(
              color: isHeroActive
                  ? AppColors.accentPrimary
                  : Colors.transparent,
              width: isHeroActive ? 1.5 : 0,
            ),
          ),
          child: ClipRRect(
            borderRadius: AppRadii.panel,
            child: Stack(
              children: [
                Builder(
                  builder: (context) {
                    final anime =
                        slides[_activeSlideIndex.clamp(0, slides.length - 1)];
                    final isInWatchlist = storageService.isInWatchlist(
                      anime.id,
                    );

                    final screenWidth = MediaQuery.sizeOf(context).width;
                    final hasBackdrop = anime.backdropUrl.trim().isNotEmpty;
                    final coverUrl = hasBackdrop
                        ? anime.backdropUrl
                        : anime.posterUrl;

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background Artwork Layer
                        WebSafeImage(
                          url: coverUrl,
                          fit: BoxFit.cover,
                          cacheWidth: WebSafeImage.homeBackdropCacheWidth,
                          filterQuality: FilterQuality.medium,
                        ),
                        // Dark overlay if portrait poster is stretched
                        if (!hasBackdrop)
                          Container(color: const Color(0x88000000)),
                        // Cinematic text-protection gradient: solid on the left, clear on the artwork
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                AppColors.primaryBg.withValues(alpha: 0.95),
                                AppColors.primaryBg.withValues(alpha: 0.80),
                                AppColors.primaryBg.withValues(alpha: 0.25),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.42, 0.68, 1.0],
                            ),
                          ),
                        ),
                        // Bottom smooth transition into the surrounding page
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Color(0x66111214),
                                AppColors.primaryBg,
                              ],
                              stops: [0.45, 0.78, 1.0],
                            ),
                          ),
                        ),

                        // Desktop High-Res Poster Showcase Card (Right Side)
                        if (screenWidth > 1050 && anime.posterUrl.isNotEmpty)
                          Positioned(
                            right: 48,
                            top: 24,
                            bottom: 24,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: AppRadii.card,
                                  boxShadow: const [AppColors.shadowPoster],
                                  border: Border.all(
                                    color: AppColors.border,
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: AppRadii.card,
                                  child: WebSafeImage(
                                    url: anime.posterUrl,
                                    fit: BoxFit.cover,
                                    cacheWidth: 300,
                                    cacheHeight: 440,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Hero Content
                        Positioned(
                          bottom: 28,
                          left: 36,
                          right: screenWidth > 1050 ? 320 : 80,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Featured metadata
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentPrimary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'FEATURED SPOTLIGHT',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  if (anime.rating > 0) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.6,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.amber.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.star_rounded,
                                            color: Colors.amber[400],
                                            size: 15,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            anime.rating.toStringAsFixed(1),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (anime.year.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      anime.year,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  if (anime.genres.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '•  ${anime.genres.take(3).join(', ')}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                anime.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                anime.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 18),
                              // Hero desktop Action Buttons
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  children: [
                                    // Watch Now Button
                                    DesktopFocusWrapper(
                                      registryKey: 'hero_watch_now',
                                      focusNode: _watchNowFocusNode,
                                      debugLabel: 'Hero Watch Now',
                                      onTap: () {
                                        DesktopFocusManager.instance
                                            .saveScreenFocus(
                                              '/home',
                                              'hero_watch_now',
                                            );
                                        context.push('/anime/${anime.id}');
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowLeft: () {
                                          DesktopSideNav.focusRail(context);
                                        },
                                        LogicalKeyboardKey.arrowRight: () =>
                                            _detailsFocusNode.requestFocus(),
                                        if (widget.onNavigateDown != null) ...{
                                          LogicalKeyboardKey.arrowDown:
                                              widget.onNavigateDown!,
                                          LogicalKeyboardKey.pageDown:
                                              widget.onNavigateDown!,
                                          LogicalKeyboardKey.channelDown:
                                              widget.onNavigateDown!,
                                        },
                                        if (widget.onNavigateUp != null) ...{
                                          LogicalKeyboardKey.arrowUp:
                                              widget.onNavigateUp!,
                                          LogicalKeyboardKey.pageUp:
                                              widget.onNavigateUp!,
                                          LogicalKeyboardKey.channelUp:
                                              widget.onNavigateUp!,
                                        },
                                      },
                                      onFocusChange: (focused) {
                                        if (focused) {
                                          _sliderTimer?.cancel();
                                        } else if (!_hasAnyHeroFocus) {
                                          _startSliderTimer();
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 10,
                                        ),
                                        decoration: const BoxDecoration(
                                          color: AppColors.accentPrimary,
                                          borderRadius: AppRadii.control,
                                          boxShadow: [AppColors.shadowSoft],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.play_arrow_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                            SizedBox(width: 7),
                                            Text(
                                              'Watch Now',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Details Button
                                    DesktopFocusWrapper(
                                      registryKey: 'hero_details',
                                      focusNode: _detailsFocusNode,
                                      debugLabel: 'Hero Details',
                                      onTap: () {
                                        DesktopFocusManager.instance
                                            .saveScreenFocus(
                                              '/home',
                                              'hero_details',
                                            );
                                        context.push('/anime/${anime.id}');
                                      },
                                      borderRadius: AppRadii.control,
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowLeft: () =>
                                            _watchNowFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowRight: () =>
                                            _watchlistFocusNode.requestFocus(),
                                        if (widget.onNavigateDown != null) ...{
                                          LogicalKeyboardKey.arrowDown:
                                              widget.onNavigateDown!,
                                          LogicalKeyboardKey.pageDown:
                                              widget.onNavigateDown!,
                                          LogicalKeyboardKey.channelDown:
                                              widget.onNavigateDown!,
                                        },
                                        if (widget.onNavigateUp != null) ...{
                                          LogicalKeyboardKey.arrowUp:
                                              widget.onNavigateUp!,
                                          LogicalKeyboardKey.pageUp:
                                              widget.onNavigateUp!,
                                          LogicalKeyboardKey.channelUp:
                                              widget.onNavigateUp!,
                                        },
                                      },
                                      onFocusChange: (focused) {
                                        if (focused) {
                                          _sliderTimer?.cancel();
                                        } else if (!_hasAnyHeroFocus) {
                                          _startSliderTimer();
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.elevatedSurface,
                                          borderRadius: AppRadii.control,
                                          border: Border.all(
                                            color: AppColors.border,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.info_outline_rounded,
                                              color: AppColors.textPrimary,
                                              size: 17,
                                            ),
                                            SizedBox(width: 7),
                                            Text(
                                              'More Details',
                                              style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Watchlist Action Button
                                    DesktopFocusWrapper(
                                      registryKey: 'hero_watchlist',
                                      focusNode: _watchlistFocusNode,
                                      debugLabel: 'Hero Watchlist',
                                      onTap: () async {
                                        await storageService.toggleWatchlist(
                                          anime,
                                        );
                                        if (mounted) setState(() {});
                                      },
                                      borderRadius: AppRadii.control,
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowLeft: () =>
                                            _detailsFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowRight: () {
                                          if (_dailySlides.isNotEmpty) {
                                            final next =
                                                (_activeSlideIndex + 1) %
                                                _dailySlides.length;
                                            _showSlide(next);
                                          }
                                        },
                                        if (widget.onNavigateDown != null) ...{
                                          LogicalKeyboardKey.arrowDown:
                                              widget.onNavigateDown!,
                                          LogicalKeyboardKey.pageDown:
                                              widget.onNavigateDown!,
                                          LogicalKeyboardKey.channelDown:
                                              widget.onNavigateDown!,
                                        },
                                        if (widget.onNavigateUp != null) ...{
                                          LogicalKeyboardKey.arrowUp:
                                              widget.onNavigateUp!,
                                          LogicalKeyboardKey.pageUp:
                                              widget.onNavigateUp!,
                                          LogicalKeyboardKey.channelUp:
                                              widget.onNavigateUp!,
                                        },
                                      },
                                      onFocusChange: (focused) {
                                        if (focused) {
                                          _sliderTimer?.cancel();
                                        } else if (!_hasAnyHeroFocus) {
                                          _startSliderTimer();
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.elevatedSurface,
                                          borderRadius: AppRadii.control,
                                          border: Border.all(
                                            color: isInWatchlist
                                                ? AppColors.accentPrimary
                                                      .withValues(alpha: 0.6)
                                                : AppColors.border,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isInWatchlist
                                                  ? Icons.bookmark_added_rounded
                                                  : Icons
                                                        .bookmark_border_rounded,
                                              color: isInWatchlist
                                                  ? AppColors.accentPrimary
                                                  : AppColors.textPrimary,
                                              size: 17,
                                            ),
                                            const SizedBox(width: 7),
                                            Text(
                                              isInWatchlist
                                                  ? 'In Watchlist'
                                                  : 'Watchlist',
                                              style: TextStyle(
                                                color: isInWatchlist
                                                    ? AppColors.accentPrimary
                                                    : AppColors.textPrimary,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // Clickable Slide Indicators
                Positioned(
                  bottom: 24,
                  right: MediaQuery.sizeOf(context).width > 1050 ? 320 : 28,
                  child: Row(
                    children: List.generate(slides.length, (i) {
                      final isActive = i == _activeSlideIndex;
                      return InkWell(
                        onTap: () => _showSlide(i),
                        borderRadius: BorderRadius.circular(3),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: isActive ? 24 : 7,
                          height: 4.5,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.accentPrimary
                                : AppColors.borderStrong,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                // Desktop Hover Navigation Chevrons
                if (_heroIsHovered && slides.length > 1) ...[
                  Positioned(
                    left: 14,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: InkWell(
                        onTap: () {
                          final prev =
                              (_activeSlideIndex - 1 + slides.length) %
                              slides.length;
                          _showSlide(prev);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xCC111116),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: InkWell(
                        onTap: () {
                          final next = (_activeSlideIndex + 1) % slides.length;
                          _showSlide(next);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xCC111116),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Reusable desktop Category Row ---
class HomeCategoryRow extends ConsumerStatefulWidget {
  final String rowId;
  final String title;
  final FutureProvider<List<Anime>> provider;
  final FocusNode? firstCardFocusNode;
  final ScrollController? scrollController;
  final void Function(int index)? onNavigateDownWithIndex;
  final void Function(int index)? onNavigateUpWithIndex;
  final void Function(int count)? onDataLoaded;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onSeeAll;
  final AnimeCardLayout layout;
  final double cardWidth;
  final double cardHeight;
  final bool isRanked;

  const HomeCategoryRow({
    super.key,
    required this.rowId,
    required this.title,
    required this.provider,
    this.firstCardFocusNode,
    this.scrollController,
    this.onNavigateDownWithIndex,
    this.onNavigateUpWithIndex,
    this.onDataLoaded,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onSeeAll,
    this.layout = AnimeCardLayout.poster,
    this.cardWidth = 175,
    this.cardHeight = 255,
    this.isRanked = false,
  });

  @override
  ConsumerState<HomeCategoryRow> createState() => _HomeCategoryRowState();
}

class _HomeCategoryRowState extends ConsumerState<HomeCategoryRow> {
  bool _isHovered = false;

  void _scrollRow(double delta) {
    final controller = widget.scrollController;
    if (controller != null && controller.hasClients) {
      final current = controller.offset;
      final target = (current + delta).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final animeListAsync = ref.watch(widget.provider);
    final leftPadding = DesktopLayout.pageLeftPadding(context);
    final rightPadding = DesktopLayout.pagePadding(context);
    final isLandscape = widget.layout == AnimeCardLayout.landscape;
    final scale = desktopCardScale(ref.watch(desktopDensityProvider));
    final cardWidth = widget.cardWidth * scale;
    final cardHeight = widget.cardHeight * scale;
    final rowHeight = isLandscape ? (cardHeight + 40) : (cardHeight + 85);
    final scrollDelta = (cardWidth + 14) * 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: leftPadding, right: rightPadding),
          child: DesktopSectionHeader(
            title: widget.title,
            trailing: widget.onSeeAll != null
                ? TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accentPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    onPressed: widget.onSeeAll,
                    child: const Text(
                      'See All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: SizedBox(
            height: rowHeight,
            child: animeListAsync.when(
              data: (animeList) {
                if (widget.onDataLoaded != null) {
                  widget.onDataLoaded!(animeList.length);
                }
                if (animeList.isEmpty) return const SizedBox.shrink();

                return Stack(
                  children: [
                    ListView.builder(
                      controller: widget.scrollController,
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                      itemCount: animeList.length,
                      padding: EdgeInsets.only(
                        left: leftPadding,
                        right: rightPadding,
                        top: 8,
                        bottom: 8,
                      ),
                      itemBuilder: (context, index) {
                        final isFirst = index == 0;
                        final directionalHandlers =
                            <LogicalKeyboardKey, VoidCallback>{};
                        if (widget.onNavigateDownWithIndex != null) {
                          directionalHandlers[LogicalKeyboardKey.arrowDown] =
                              () => widget.onNavigateDownWithIndex!(index);
                          directionalHandlers[LogicalKeyboardKey.pageDown] =
                              () => widget.onNavigateDownWithIndex!(index);
                          directionalHandlers[LogicalKeyboardKey.channelDown] =
                              () => widget.onNavigateDownWithIndex!(index);
                        } else if (widget.onNavigateDown != null) {
                          directionalHandlers[LogicalKeyboardKey.arrowDown] =
                              widget.onNavigateDown!;
                          directionalHandlers[LogicalKeyboardKey.pageDown] =
                              widget.onNavigateDown!;
                          directionalHandlers[LogicalKeyboardKey.channelDown] =
                              widget.onNavigateDown!;
                        }
                        if (widget.onNavigateUpWithIndex != null) {
                          directionalHandlers[LogicalKeyboardKey.arrowUp] =
                              () => widget.onNavigateUpWithIndex!(index);
                          directionalHandlers[LogicalKeyboardKey.pageUp] = () =>
                              widget.onNavigateUpWithIndex!(index);
                          directionalHandlers[LogicalKeyboardKey.channelUp] =
                              () => widget.onNavigateUpWithIndex!(index);
                        } else if (widget.onNavigateUp != null) {
                          directionalHandlers[LogicalKeyboardKey.arrowUp] =
                              widget.onNavigateUp!;
                          directionalHandlers[LogicalKeyboardKey.pageUp] =
                              widget.onNavigateUp!;
                          directionalHandlers[LogicalKeyboardKey.channelUp] =
                              widget.onNavigateUp!;
                        }

                        final isLast = index == animeList.length - 1;
                        void focusCard(int target) {
                          DesktopFocusManager.instance.moveFocusBetweenRows(
                            fromRowId: widget.rowId,
                            toRowId: widget.rowId,
                            currentIndex: target,
                            toRowCount: animeList.length,
                            scrollController: widget.scrollController,
                            cardWidth: cardWidth + 14,
                          );
                        }

                        if (!isFirst) {
                          directionalHandlers[LogicalKeyboardKey.arrowLeft] =
                              () => focusCard(index - 1);
                        }
                        if (!isLast) {
                          directionalHandlers[LogicalKeyboardKey.arrowRight] =
                              () => focusCard(index + 1);
                        }

                        if (isFirst) {
                          directionalHandlers[LogicalKeyboardKey.arrowLeft] =
                              () {
                                DesktopSideNav.focusRail(context);
                              };
                        }
                        if (isLast) {
                          directionalHandlers[LogicalKeyboardKey.arrowRight] =
                              () {};
                        }

                        final card = AnimeCard(
                          anime: animeList[index],
                          layout: widget.layout,
                          width: cardWidth,
                          height: cardHeight,
                          registryKey: 'home_row_${widget.rowId}_$index',
                          onCardFocused: () {
                            DesktopFocusManager.instance.recordRowFocus(
                              widget.rowId,
                              index,
                            );
                          },
                          focusNode: isFirst ? widget.firstCardFocusNode : null,
                          directionalKeyHandlers: directionalHandlers,
                        );

                        if (widget.isRanked && index < 10) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: index == 9 ? 48 : 34,
                                  height: cardHeight,
                                  child: Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 24,
                                        right: 4,
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontSize: 52,
                                          fontWeight: FontWeight.w900,
                                          color: index < 3
                                              ? AppColors.brandRed
                                              : const Color(0x35FFFFFF),
                                          letterSpacing: -3,
                                          height: 0.9,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                card,
                              ],
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: card,
                        );
                      },
                    ),

                    // Left Desktop Scroll Chevron
                    if (_isHovered)
                      Positioned(
                        left: leftPadding - 6,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: InkWell(
                            onTap: () => _scrollRow(-scrollDelta),
                            borderRadius: AppRadii.control,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.elevatedSurface.withValues(
                                  alpha: 0.95,
                                ),
                                borderRadius: AppRadii.control,
                                border: Border.all(color: AppColors.border),
                                boxShadow: const [AppColors.shadowSoft],
                              ),
                              child: const Icon(
                                Icons.chevron_left_rounded,
                                color: AppColors.textPrimary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Right Desktop Scroll Chevron
                    if (_isHovered)
                      Positioned(
                        right: rightPadding - 6,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: InkWell(
                            onTap: () => _scrollRow(scrollDelta),
                            borderRadius: AppRadii.control,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.elevatedSurface.withValues(
                                  alpha: 0.95,
                                ),
                                borderRadius: AppRadii.control,
                                border: Border.all(color: AppColors.border),
                                boxShadow: const [AppColors.shadowSoft],
                              ),
                              child: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textPrimary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => Padding(
                padding: EdgeInsets.only(
                  left: leftPadding,
                  right: rightPadding,
                ),
                child: LoadingShimmer.horizontalList(),
              ),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        SizedBox(height: DesktopLayout.sectionGap(context)),
      ],
    );
  }
}
