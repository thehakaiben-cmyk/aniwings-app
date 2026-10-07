import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../services/anime_service.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/loading_shimmer.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/web_safe_image.dart';

final discoverGenreProvider = StateProvider<String>((ref) => 'All');
final discoverSortProvider = StateProvider<String>((ref) => 'Trending');
final discoverMoodProvider = StateProvider<String?>((ref) => null);

final discoverAnimeListProvider = FutureProvider<List<Anime>>((ref) async {
  final genre = ref.watch(discoverGenreProvider);
  final sort = ref.watch(discoverSortProvider);
  final mood = ref.watch(discoverMoodProvider);

  final animeService = ref.watch(animeServiceProvider);

  // If a mood is selected, apply mood genre & filter
  if (mood != null) {
    return switch (mood) {
      'exciting' => animeService.queryAnime(
        query: '',
        genre: 'Action',
        sortBy: 'Rating',
      ),
      'relaxing' => animeService.queryAnime(
        query: '',
        genre: 'Slice of Life',
        sortBy: 'Rating',
      ),
      'emotional' => animeService.queryAnime(
        query: '',
        genre: 'Drama',
        sortBy: 'Rating',
      ),
      'comedy' => animeService.queryAnime(
        query: '',
        genre: 'Comedy',
        sortBy: 'Rating',
      ),
      'fantasy' => animeService.queryAnime(
        query: '',
        genre: 'Fantasy',
        sortBy: 'Trending',
      ),
      'scifi' => animeService.queryAnime(
        query: '',
        genre: 'Sci-Fi',
        sortBy: 'Rating',
      ),
      _ => animeService.queryAnime(query: '', genre: genre, sortBy: sort),
    };
  }

  if (genre == 'All' && sort == 'Trending') {
    return ref.watch(trendingAnimeProvider.future);
  }

  return animeService.queryAnime(query: '', genre: genre, sortBy: sort);
});

/// AniWings Desktop — Smart Anime Discovery Screen.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  late final ScrollController _scrollController;
  Anime? _surpriseAnime;
  bool _isLoadingSurprise = false;

  // Watch Time Calculator state
  int _calcEpisodes = 24;
  int _calcDurationMins = 24;
  int _calcEpisodesPerDay = 3;

  late final FocusNode _surpriseWatchFocus;
  late final FocusNode _surpriseDetailsFocus;
  late final FocusNode _surpriseRerollFocus;
  late final FocusNode _firstGenreFocus;

  static const List<String> _sortOptions = [
    'Trending',
    'Rating',
    'Latest',
    'A-Z',
  ];

  static const List<Map<String, dynamic>> _moodCategories = [
    {
      'id': 'exciting',
      'label': 'High Adrenaline',
      'sub': 'Action',
      'icon': Icons.flash_on_rounded,
      'color': Color(0xFFFF2A54),
    },
    {
      'id': 'relaxing',
      'label': 'Peaceful & Chill',
      'sub': 'Slice of Life',
      'icon': Icons.spa_rounded,
      'color': Color(0xFF10B981),
    },
    {
      'id': 'emotional',
      'label': 'Tearjerkers',
      'sub': 'Drama',
      'icon': Icons.favorite_rounded,
      'color': Color(0xFFFF3038),
    },
    {
      'id': 'comedy',
      'label': 'Comedy Night',
      'sub': 'Pure Fun & Laughs',
      'icon': Icons.sentiment_very_satisfied_rounded,
      'color': Color(0xFFFFB020),
    },
    {
      'id': 'fantasy',
      'label': 'Epic Fantasy',
      'sub': 'Magic & Worlds',
      'icon': Icons.auto_awesome_rounded,
      'color': Color(0xFF8B5CF6),
    },
    {
      'id': 'scifi',
      'label': 'Futuristic Sci-Fi',
      'sub': 'Cyberpunk & Space',
      'icon': Icons.rocket_launch_rounded,
      'color': Color(0xFF3B82F6),
    },
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _surpriseWatchFocus = FocusNode(debugLabel: 'Surprise Watch');
    _surpriseDetailsFocus = FocusNode(debugLabel: 'Surprise Details');
    _surpriseRerollFocus = FocusNode(debugLabel: 'Surprise Reroll');
    _firstGenreFocus = FocusNode(debugLabel: 'First Genre');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSurpriseAnime();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _surpriseWatchFocus.dispose();
    _surpriseDetailsFocus.dispose();
    _surpriseRerollFocus.dispose();
    _firstGenreFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSurpriseAnime() async {
    if (_isLoadingSurprise) return;
    setState(() => _isLoadingSurprise = true);

    try {
      final list = await ref.read(trendingAnimeProvider.future);
      if (list.isNotEmpty) {
        final rng = Random();
        final selected = list[rng.nextInt(list.length)];
        if (mounted) {
          setState(() {
            _surpriseAnime = selected;
            _calcEpisodes = selected.totalEpisodes > 0
                ? selected.totalEpisodes
                : 24;
            _calcDurationMins = selected.episodeDurationMinutes > 0
                ? selected.episodeDurationMinutes
                : 24;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingSurprise = false);
    }
  }

  void _showWatchTimeCalculator() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalMinutes = _calcEpisodes * _calcDurationMins;
          final totalHours = (totalMinutes / 60).toStringAsFixed(1);
          final daysToFinish = (_calcEpisodes / max(1, _calcEpisodesPerDay))
              .ceil();

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.elevatedSurface,
                borderRadius: AppRadii.dialog,
                border: Border.all(color: AppColors.borderStrong, width: 1.0),
                boxShadow: const [AppColors.shadowPanel],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadii.control,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(
                          Icons.calculate_rounded,
                          color: AppColors.accentPrimary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Watch Time Calculator',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Inputs Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildCalculatorInputCard(
                          label: 'Episodes',
                          value: '$_calcEpisodes',
                          onDecrement: () {
                            if (_calcEpisodes > 1) {
                              setDialogState(() => _calcEpisodes--);
                              setState(() {});
                            }
                          },
                          onIncrement: () {
                            setDialogState(() => _calcEpisodes++);
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCalculatorInputCard(
                          label: 'Eps / Day',
                          value: '$_calcEpisodesPerDay',
                          onDecrement: () {
                            if (_calcEpisodesPerDay > 1) {
                              setDialogState(() => _calcEpisodesPerDay--);
                              setState(() {});
                            }
                          },
                          onIncrement: () {
                            setDialogState(() => _calcEpisodesPerDay++);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Results Banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadii.card,
                      border: Border.all(color: AppColors.borderStrong),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text(
                              'TOTAL WATCH TIME',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$totalHours hrs',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: AppColors.border,
                        ),
                        Column(
                          children: [
                            const Text(
                              'DAYS TO COMPLETE',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$daysToFinish days',
                              style: const TextStyle(
                                color: AppColors.accentPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Align(
                    alignment: Alignment.centerRight,
                    child: DesktopFocusWrapper(
                      autofocus: true,
                      borderRadius: AppRadii.control,
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 9,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.accentPrimary,
                          borderRadius: AppRadii.control,
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalculatorInputCard({
    required String label,
    required String value,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.control,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: AppColors.textSecondary,
                ),
                onPressed: onDecrement,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: AppColors.accentPrimary,
                ),
                onPressed: onIncrement,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animeService = ref.watch(animeServiceProvider);
    final selectedGenre = ref.watch(discoverGenreProvider);
    final selectedSort = ref.watch(discoverSortProvider);
    final selectedMood = ref.watch(discoverMoodProvider);
    final animeListAsync = ref.watch(discoverAnimeListProvider);

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
              padding: EdgeInsets.fromLTRB(leftPadding, 20, rightPadding, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Bar
                  _buildHeaderBar(),

                  const SizedBox(height: 20),

                  // 1. "Surprise Me" Cinematic Card
                  _buildSurpriseMeBanner(),

                  const SizedBox(height: 28),

                  // 2. Mood-Based Categories Row
                  _buildMoodSection(selectedMood),

                  const SizedBox(height: 28),

                  // 3. Filter Controls: Genres & Sort
                  _buildFilterBar(
                    animeService: animeService,
                    selectedGenre: selectedGenre,
                    selectedSort: selectedSort,
                  ),

                  const SizedBox(height: 24),

                  // 4. Discovery Results Grid
                  animeListAsync.when(
                    data: (animeList) => animeList.isEmpty
                        ? const DesktopEmptyState(
                            icon: Icons.movie_filter_rounded,
                            title: 'No titles discovered',
                            message:
                                'Try selecting a different genre or mood filter.',
                          )
                        : GridView.builder(
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
                            itemCount: animeList.length,
                            itemBuilder: (context, index) => AnimeCard(
                              anime: animeList[index],
                              width: double.infinity,
                              height: double.infinity,
                              layout: AnimeCardLayout.poster,
                            ),
                          ),
                    loading: () => LoadingShimmer.grid(),
                    error: (_, _) => const DesktopEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Discovery unavailable',
                      message: 'Could not connect to anime directory.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'DISCOVERY HUB',
                  style: TextStyle(
                    color: AppColors.accentPrimary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Explore Anime',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),

        // Watch Time Calculator trigger
        DesktopFocusWrapper.builder(
          onTap: _showWatchTimeCalculator,
          borderRadius: AppRadii.control,
          builder: (context, isFocused, isHovered) {
            final active = isFocused || isHovered;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.hoverState : AppColors.surface,
                borderRadius: AppRadii.control,
                border: Border.all(
                  color: active ? AppColors.borderStrong : AppColors.border,
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 15,
                    color: active
                        ? AppColors.accentPrimary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Time Calculator',
                    style: TextStyle(
                      color: active
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSurpriseMeBanner() {
    if (!_isLoadingSurprise && _surpriseAnime == null) {
      return Center(
        child: TextButton.icon(
          onPressed: () {
            ref.invalidate(trendingAnimeProvider);
            _loadSurpriseAnime();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Retry surprise recommendation'),
        ),
      );
    }
    if (_isLoadingSurprise || _surpriseAnime == null) {
      return LoadingShimmer(
        child: Container(
          height: 195,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.panel,
          ),
        ),
      );
    }

    final anime = _surpriseAnime!;

    return Container(
      height: 195,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.panel,
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: const [AppColors.shadowPanel],
      ),
      child: ClipRRect(
        borderRadius: AppRadii.panel,
        child: Stack(
          children: [
            // Backdrop Image
            Positioned.fill(
              child: WebSafeImage(
                url: anime.backdropUrl.isNotEmpty
                    ? anime.backdropUrl
                    : anime.posterUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),

            // Black-to-transparent gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.primaryBg.withValues(alpha: 0.98),
                      AppColors.primaryBg.withValues(alpha: 0.90),
                      AppColors.primaryBg.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.40, 0.70, 1.0],
                  ),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Row(
                children: [
                  // Poster Thumbnail
                  Container(
                    decoration: const BoxDecoration(
                      borderRadius: AppRadii.card,
                      boxShadow: [AppColors.shadowPoster],
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadii.card,
                      child: SizedBox(
                        width: 105,
                        height: 155,
                        child: WebSafeImage(
                          url: anime.posterUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Info & Actions
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: const BoxDecoration(
                                color: AppColors.brandRed,
                                borderRadius: AppRadii.control,
                              ),
                              child: const Text(
                                'SURPRISE ME',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: AppColors.studioGold,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${anime.rating}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              anime.genres.take(3).join(' • '),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          anime.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          anime.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Action Buttons
                        Row(
                          children: [
                            DesktopFocusWrapper.builder(
                              focusNode: _surpriseWatchFocus,
                              onTap: () {
                                final epId = '${anime.id}_ep_1';
                                context.push('/watch/${anime.id}/$epId');
                              },
                              borderRadius: AppRadii.control,
                              directionalKeyHandlers: {
                                LogicalKeyboardKey.arrowRight: () =>
                                    _surpriseDetailsFocus.requestFocus(),
                              },
                              builder: (context, isFocused, isHovered) {
                                final active = isFocused || isHovered;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.brandRedHover
                                        : AppColors.brandRed,
                                    borderRadius: AppRadii.control,
                                    border: Border.all(
                                      color: active
                                          ? Colors.white.withValues(alpha: 0.3)
                                          : AppColors.brandRed,
                                    ),
                                    boxShadow: const [AppColors.shadowSoft],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Watch Now',
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
                            const SizedBox(width: 10),
                            DesktopFocusWrapper.builder(
                              focusNode: _surpriseDetailsFocus,
                              onTap: () => context.push('/anime/${anime.id}'),
                              borderRadius: AppRadii.control,
                              directionalKeyHandlers: {
                                LogicalKeyboardKey.arrowLeft: () =>
                                    _surpriseWatchFocus.requestFocus(),
                                LogicalKeyboardKey.arrowRight: () =>
                                    _surpriseRerollFocus.requestFocus(),
                              },
                              builder: (context, isFocused, isHovered) {
                                final active = isFocused || isHovered;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.hoverState
                                        : AppColors.surface,
                                    borderRadius: AppRadii.control,
                                    border: Border.all(
                                      color: active
                                          ? AppColors.borderStrong
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    'Details',
                                    style: TextStyle(
                                      color: active
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 10),
                            DesktopFocusWrapper.builder(
                              focusNode: _surpriseRerollFocus,
                              onTap: _loadSurpriseAnime,
                              borderRadius: AppRadii.control,
                              directionalKeyHandlers: {
                                LogicalKeyboardKey.arrowLeft: () =>
                                    _surpriseDetailsFocus.requestFocus(),
                              },
                              builder: (context, isFocused, isHovered) {
                                final active = isFocused || isHovered;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.hoverState
                                        : AppColors.surface,
                                    borderRadius: AppRadii.control,
                                    border: Border.all(
                                      color: active
                                          ? AppColors.borderStrong
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.casino_rounded,
                                        size: 16,
                                        color: active
                                            ? AppColors.brandRed
                                            : AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Try Another',
                                        style: TextStyle(
                                          color: active
                                              ? AppColors.textPrimary
                                              : AppColors.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodSection(String? selectedMood) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mood-Based Discovery',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _moodCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final mood = _moodCategories[index];
              final isSelected = selectedMood == mood['id'];
              final color = mood['color'] as Color;

              return DesktopFocusWrapper.builder(
                onTap: () {
                  if (isSelected) {
                    ref.read(discoverMoodProvider.notifier).state = null;
                  } else {
                    ref.read(discoverMoodProvider.notifier).state =
                        mood['id'] as String;
                  }
                },
                borderRadius: AppRadii.card,
                builder: (context, isFocused, isHovered) {
                  final active = isFocused || isHovered;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 160,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.12)
                          : (active ? AppColors.hoverState : AppColors.surface),
                      borderRadius: AppRadii.card,
                      border: Border.all(
                        color: isSelected
                            ? color.withValues(alpha: 0.7)
                            : (active
                                  ? AppColors.borderStrong
                                  : AppColors.border),
                        width: 1.0,
                      ),
                      boxShadow: const [AppColors.shadowSoft],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: AppRadii.control,
                          ),
                          child: Icon(
                            mood['icon'] as IconData,
                            size: 16,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                mood['label'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isSelected || active
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                mood['sub'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar({
    required AnimeService animeService,
    required String selectedGenre,
    required String selectedSort,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.secondaryBg,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: AppColors.brandRed, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: animeService.genres.length,
                itemBuilder: (context, index) {
                  final genre = animeService.genres[index];
                  final isSelected = genre == selectedGenre;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DesktopFocusWrapper.builder(
                      focusNode: index == 0 ? _firstGenreFocus : null,
                      onTap: () {
                        ref.read(discoverMoodProvider.notifier).state = null;
                        ref.read(discoverGenreProvider.notifier).state = genre;
                      },
                      borderRadius: AppRadii.control,
                      builder: (context, isFocused, isHovered) {
                        final active = isFocused || isHovered;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
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
                              color: isSelected
                                  ? AppColors.brandRed
                                  : (active
                                        ? AppColors.borderStrong
                                        : AppColors.borderSubtle),
                            ),
                          ),
                          child: Text(
                            genre,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : (active
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary),
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
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: AppColors.border),
          const SizedBox(width: 12),

          // Sort Options
          ..._sortOptions.map((sort) {
            final isSelected = selectedSort == sort;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: DesktopFocusWrapper.builder(
                onTap: () =>
                    ref.read(discoverSortProvider.notifier).state = sort,
                borderRadius: AppRadii.control,
                builder: (context, isFocused, isHovered) {
                  final active = isFocused || isHovered;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.surface
                          : (active
                                ? AppColors.hoverState
                                : Colors.transparent),
                      borderRadius: AppRadii.control,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.brandRed
                            : (active
                                  ? AppColors.borderStrong
                                  : AppColors.borderSubtle),
                      ),
                    ),
                    child: Text(
                      sort,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.brandRed
                            : (active
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary),
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
}
