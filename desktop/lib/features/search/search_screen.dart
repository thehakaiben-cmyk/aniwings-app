import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../services/anime_service.dart';
import '../../services/storage_service.dart';
import '../../services/desktop_preferences.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/loading_shimmer.dart';
import '../../widgets/desktop_layout.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');
final _debouncedQueryProvider = StateProvider<String>((ref) => '');

final searchAnimeProvider = FutureProvider.autoDispose<List<Anime>>((
  ref,
) async {
  final query = ref.watch(_debouncedQueryProvider);
  if (query.trim().length < 2) return [];
  return ref
      .watch(animeServiceProvider)
      .queryAnime(query: query, genre: 'All', sortBy: 'Trending');
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  late final FocusNode _searchFocusNode;
  final ScrollController _resultsScrollController = ScrollController();
  Timer? _debounceTimer;
  String? _selectedGenre;

  static const List<String> _quickGenres = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Fantasy',
    'Romance',
    'Sci-Fi',
    'Supernatural',
    'Mystery',
    'Thriller',
    'Slice of Life',
    'Sports',
    'Isekai',
  ];

  static const List<String> _trendingSearches = [
    'Solo Leveling',
    'Jujutsu Kaisen',
    'Frieren',
    'Demon Slayer',
    'One Piece',
    'Attack on Titan',
    'Chainsaw Man',
    'Bleach',
  ];

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(searchQueryProvider);
    _controller = TextEditingController(text: initialQuery);
    _searchFocusNode = FocusNode(debugLabel: 'Desktop Search Field');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _resultsScrollController.dispose();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    ref.read(searchQueryProvider.notifier).state = value;
    _debounceTimer?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      ref.read(_debouncedQueryProvider.notifier).state = '';
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 320), () {
      if (mounted && _controller.text.trim() == query) {
        ref.read(_debouncedQueryProvider.notifier).state = query;
      }
    });
  }

  void _submitSearch(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    ref.read(storageServiceProvider).addToSearchHistory(trimmed);
    ref.read(searchQueryProvider.notifier).state = trimmed;
    ref.read(_debouncedQueryProvider.notifier).state = trimmed;
    setState(() {});
  }

  void _applyQuery(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _submitSearch(query);
  }

  void _clearSearch() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    _debounceTimer?.cancel();
    ref.read(_debouncedQueryProvider.notifier).state = '';
    setState(() {
      _selectedGenre = null;
    });
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final debouncedQuery = ref.watch(_debouncedQueryProvider).trim();
    final resultsAsync = ref.watch(searchAnimeProvider);
    final recentSearches = ref.watch(storageServiceProvider).getSearchHistory();

    final leftPadding = DesktopLayout.pageLeftPadding(context);
    final rightPadding = DesktopLayout.pagePadding(context);

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: SafeArea(
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              if (_controller.text.isNotEmpty) {
                _clearSearch();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Pinned Search Input & Controls Bar ──
              Padding(
                padding: EdgeInsets.fromLTRB(leftPadding, 20, rightPadding, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Page Title & Subtitle
                    Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          color: AppColors.brandRed,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Search',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadii.control,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Text(
                            'Ctrl + K to focus',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Desktop Search Input Field
                    Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.control,
                        border: Border.all(
                          color: _searchFocusNode.hasFocus
                              ? AppColors.brandRed
                              : AppColors.border,
                          width: _searchFocusNode.hasFocus ? 1.5 : 1.0,
                        ),
                        boxShadow: _searchFocusNode.hasFocus
                            ? const [AppColors.shadowSoft]
                            : null,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Icon(
                            Icons.search_rounded,
                            color: _searchFocusNode.hasFocus
                                ? AppColors.brandRed
                                : AppColors.textMuted,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              autofocus: true,
                              controller: _controller,
                              focusNode: _searchFocusNode,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: const InputDecoration(
                                filled: false,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                hintText:
                                    'Search anime by title, character, or genre...',
                                hintStyle: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w400,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: _submitSearch,
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          if (_controller.text.isNotEmpty) ...[
                            IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: AppColors.textMuted,
                                size: 18,
                              ),
                              tooltip: 'Clear search (Esc)',
                              hoverColor: AppColors.hoverState,
                              splashRadius: 16,
                              onPressed: _clearSearch,
                            ),
                          ],
                          const SizedBox(width: 6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Genre Filter Pills
                    SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _quickGenres.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, index) {
                          final genre = _quickGenres[index];
                          final isSelected = _selectedGenre == genre;
                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedGenre = null;
                                } else {
                                  _selectedGenre = genre;
                                  _applyQuery(genre);
                                }
                              });
                            },
                            borderRadius: AppRadii.control,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.brandRed
                                    : AppColors.surface,
                                borderRadius: AppRadii.control,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.brandRed
                                      : AppColors.border,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  genre,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ── Independently Scrolling Results / Discovery Area ──
              Expanded(
                child: Scrollbar(
                  controller: _resultsScrollController,
                  thumbVisibility: true,
                  child: CustomScrollView(
                    key: const PageStorageKey('desktop-search-results'),
                    controller: _resultsScrollController,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      if (debouncedQuery.isNotEmpty) ...[
                        // Results Header
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              leftPadding,
                              8,
                              rightPadding,
                              14,
                            ),
                            child: resultsAsync.when(
                              data: (results) => Row(
                                children: [
                                  Text(
                                    'Results for "$debouncedQuery"',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${results.length} found)',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              loading: () => const Text(
                                'Searching anime database...',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              error: (err, _) => const Text(
                                'Unable to load search results',
                                style: TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Results Content
                        resultsAsync.when(
                          data: (results) {
                            if (results.isEmpty) {
                              return SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    leftPadding,
                                    48,
                                    rightPadding,
                                    48,
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: AppRadii.control,
                                            border: Border.all(
                                              color: AppColors.border,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.search_off_rounded,
                                            color: AppColors.textMuted,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No anime found for "$debouncedQuery"',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Try checking your spelling, using English or Romaji titles, or searching by genre.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }

                            return SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                leftPadding,
                                0,
                                rightPadding,
                                36,
                              ),
                              sliver: SliverGrid(
                                key: const ValueKey('search-results-grid'),
                                gridDelegate:
                                    DesktopLayout.responsiveGridDelegate(
                                      context,
                                      maxExtent:
                                          210 *
                                          desktopCardScale(
                                            ref.watch(desktopDensityProvider),
                                          ),
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final anime = results[index];
                                  return AnimeCard(
                                    anime: anime,
                                    width: double.infinity,
                                    height: double.infinity,
                                    onTap: () {
                                      context.push('/anime/${anime.id}');
                                      ref
                                          .read(storageServiceProvider)
                                          .addToSearchHistory(debouncedQuery);
                                    },
                                  );
                                }, childCount: results.length),
                              ),
                            );
                          },
                          loading: () => SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              leftPadding,
                              0,
                              rightPadding,
                              36,
                            ),
                            sliver: SliverGrid(
                              gridDelegate:
                                  DesktopLayout.responsiveGridDelegate(context),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                return LoadingShimmer.card();
                              }, childCount: 12),
                            ),
                          ),
                          error: (error, _) => SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                leftPadding,
                                40,
                                rightPadding,
                                40,
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: AppColors.danger,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Search error: $error',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        // ── Initial Discovery View (Empty Query) ──
                        SliverToBoxAdapter(
                          key: const ValueKey('search-landing'),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              leftPadding,
                              8,
                              rightPadding,
                              36,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Recent Searches Section
                                if (recentSearches.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.history_rounded,
                                        color: AppColors.textMuted,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Recent Searches',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () async {
                                          await ref
                                              .read(storageServiceProvider)
                                              .clearSearchHistory();
                                          setState(() {});
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.textMuted,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                        ),
                                        child: const Text(
                                          'Clear all',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: recentSearches.take(10).map((
                                      item,
                                    ) {
                                      return InkWell(
                                        onTap: () => _applyQuery(item),
                                        borderRadius: AppRadii.control,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 11,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: AppRadii.control,
                                            border: Border.all(
                                              color: AppColors.borderSubtle,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.north_west_rounded,
                                                size: 12,
                                                color: AppColors.textMuted,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                item,
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                // Trending Searches Section
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.trending_up_rounded,
                                      color: AppColors.brandRed,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Trending Searches',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _trendingSearches.map((title) {
                                    return InkWell(
                                      onTap: () => _applyQuery(title),
                                      borderRadius: AppRadii.control,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius: AppRadii.control,
                                          border: Border.all(
                                            color: AppColors.borderSubtle,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.search_rounded,
                                              size: 13,
                                              color: AppColors.brandRed,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),

                                const SizedBox(height: 24),

                                // Quick Commands / App Navigation
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.terminal_rounded,
                                      color: AppColors.accentSecondary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Quick Commands',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      [
                                        (
                                          label: 'Go to Home',
                                          icon: Icons.home_rounded,
                                          route: '/home',
                                        ),
                                        (
                                          label: 'Go to Discover',
                                          icon: Icons.explore_rounded,
                                          route: '/discover',
                                        ),
                                        (
                                          label: 'Go to Watchlist',
                                          icon: Icons.bookmark_rounded,
                                          route: '/watchlist',
                                        ),
                                        (
                                          label: 'Go to History',
                                          icon: Icons.history_rounded,
                                          route: '/history',
                                        ),
                                        (
                                          label: 'Go to Collections',
                                          icon: Icons.video_library_rounded,
                                          route: '/collections',
                                        ),
                                        (
                                          label: 'Open Settings',
                                          icon: Icons.settings_rounded,
                                          route: '/settings',
                                        ),
                                        (
                                          label: 'Open Profile',
                                          icon: Icons.person_rounded,
                                          route: '/profile',
                                        ),
                                      ].map((cmd) {
                                        return InkWell(
                                          onTap: () => context.go(cmd.route),
                                          borderRadius: AppRadii.control,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 7,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.surface,
                                              borderRadius: AppRadii.control,
                                              border: Border.all(
                                                color: AppColors.borderSubtle,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  cmd.icon,
                                                  size: 14,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                                const SizedBox(width: 7),
                                                Text(
                                                  cmd.label,
                                                  style: const TextStyle(
                                                    color:
                                                        AppColors.textSecondary,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                ),

                                const SizedBox(height: 28),

                                // Popular Anime Right Now
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.local_fire_department_rounded,
                                      color: AppColors.brandRed,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Popular Anime Right Now',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Text(
                                      'Click any title to explore',
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                ref
                                    .watch(hotRightNowProvider)
                                    .when(
                                      data: (animeList) {
                                        if (animeList.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        final previewList = animeList
                                            .take(8)
                                            .toList();
                                        return LayoutBuilder(
                                          builder: (context, constraints) {
                                            final count =
                                                (constraints.maxWidth /
                                                        (180 *
                                                            desktopCardScale(
                                                              ref.watch(
                                                                desktopDensityProvider,
                                                              ),
                                                            )))
                                                    .floor()
                                                    .clamp(3, 8);
                                            return GridView.builder(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              gridDelegate:
                                                  SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: count,
                                                    childAspectRatio: 0.65,
                                                    crossAxisSpacing: 16,
                                                    mainAxisSpacing: 16,
                                                  ),
                                              itemCount: previewList.length,
                                              itemBuilder: (context, index) {
                                                final anime =
                                                    previewList[index];
                                                return AnimeCard(
                                                  anime: anime,
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                      loading: () =>
                                          LoadingShimmer.horizontalList(),
                                      error: (_, _) => const SizedBox.shrink(),
                                    ),
                              ],
                            ),
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
    );
  }
}
