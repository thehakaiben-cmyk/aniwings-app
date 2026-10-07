import '../downloads/downloads_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../models/episode.dart';
import '../../models/watch_entry.dart';
import '../../services/anime_service.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/web_safe_image.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  final String animeId;

  const DetailsScreen({super.key, required this.animeId});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  late final ScrollController _detailsScrollController;
  late final FocusNode _startWatchingFocusNode;
  late final FocusNode _watchlistFocusNode;
  late final FocusNode _collectionFocusNode;
  late final FocusNode _shareFocusNode;
  late final FocusNode _backButtonFocusNode;

  List<Episode>? _cachedProvisionalEpisodes;
  String? _cachedProvisionalAnimeId;
  String _episodeSearchFilter = '';
  int _episodeViewMode = 0; // 0: cards, 1: pills, 2: list

  @override
  void initState() {
    super.initState();
    _detailsScrollController = ScrollController();
    _startWatchingFocusNode = FocusNode(debugLabel: 'Details Start Watching');
    _watchlistFocusNode = FocusNode(debugLabel: 'Details Watchlist Button');
    _collectionFocusNode = FocusNode(debugLabel: 'Details Collection Button');
    _shareFocusNode = FocusNode(debugLabel: 'Details Share Button');
    _backButtonFocusNode = FocusNode(debugLabel: 'Details Back Button');
  }

  @override
  void dispose() {
    _detailsScrollController.dispose();
    _startWatchingFocusNode.dispose();
    _watchlistFocusNode.dispose();
    _collectionFocusNode.dispose();
    _shareFocusNode.dispose();
    _backButtonFocusNode.dispose();
    super.dispose();
  }

  void _goBack(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return;
    }
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    router?.go('/home');
  }

  KeyEventResult _handleKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      _goBack(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _shareAnime(Anime anime) async {
    final text = 'Check out ${anime.title} on AniWings Desktop!';
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'Share ${anime.title}',
          subject: '${anime.title} on AniWings Desktop',
          text: text,
        ),
      );
    } catch (_) {}
  }

  List<Episode> _provisionalEpisodes(Anime anime) {
    if (_cachedProvisionalAnimeId == anime.id &&
        _cachedProvisionalEpisodes != null) {
      return _cachedProvisionalEpisodes!;
    }
    final count = anime.totalEpisodes > 0 ? anime.totalEpisodes : 12;
    final duration = Duration(
      minutes: anime.episodeDurationMinutes > 0
          ? anime.episodeDurationMinutes
          : 24,
    );
    final now = DateTime.now();
    _cachedProvisionalAnimeId = anime.id;
    _cachedProvisionalEpisodes = List.generate(count, (index) {
      final number = index + 1;
      return Episode(
        id: '${anime.id}_ep_$number',
        animeId: anime.id,
        episodeNumber: number,
        title: 'Episode $number',
        airDate: now,
        duration: duration,
        videoUrls: const [],
      );
    }, growable: false);
    return _cachedProvisionalEpisodes!;
  }

  String _resolvedDescription(Anime anime, Map<String, dynamic>? extraInfo) {
    bool isUseful(String value) {
      final normalized = value.trim().toLowerCase();
      return normalized.isNotEmpty &&
          normalized != 'no description available.' &&
          normalized != 'no description available';
    }

    if (isUseful(anime.description)) return anime.description;
    final extraDescription = extraInfo?['description']?.toString() ?? '';
    if (!isUseful(extraDescription)) return 'No description available.';
    return anime.copyWith(description: extraDescription).description;
  }

  String _getAgeRating(Anime anime) {
    final genres = anime.genres.map((g) => g.toLowerCase()).toList();
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

  Future<void> _showWatchlistStatusDialog(
    BuildContext context,
    Anime anime,
  ) async {
    final storage = ref.read(storageServiceProvider);
    const statuses = [
      ('Currently Watching', Icons.play_circle_fill_rounded, AppColors.success),
      ('Plan to Watch', Icons.bookmark_added_rounded, AppColors.accentPrimary),
      ('Completed', Icons.check_circle_rounded, Color(0xFF9D4EDD)),
      ('On Hold', Icons.pause_circle_filled_rounded, Color(0xFFFFB703)),
      ('Dropped', Icons.cancel_rounded, AppColors.danger),
    ];

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isMember = storage.isInWatchlist(anime.id);
          final activeStatus = storage.getWatchlistStatus(anime.id);

          return Dialog(
            backgroundColor: AppColors.secondaryBg,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadii.dialog,
              side: BorderSide(color: AppColors.border),
            ),
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.bookmark_rounded,
                        color: AppColors.brandRed,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Watchlist Status',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final item in statuses) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () async {
                          if (!isMember) {
                            await storage.addToWatchlist(anime);
                          }
                          await storage.setWatchlistStatus(anime.id, item.$1);
                          if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                          if (mounted) setState(() {});
                        },
                        borderRadius: AppRadii.control,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: activeStatus == item.$1
                                ? AppColors.brandRed.withValues(alpha: 0.12)
                                : AppColors.surface,
                            borderRadius: AppRadii.control,
                            border: Border.all(
                              color: activeStatus == item.$1
                                  ? AppColors.brandRed
                                  : AppColors.borderSubtle,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(item.$2, color: item.$3, size: 18),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.$1,
                                  style: TextStyle(
                                    color: activeStatus == item.$1
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                    fontSize: 13.5,
                                    fontWeight: activeStatus == item.$1
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (activeStatus == item.$1)
                                const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.brandRed,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (isMember) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        await storage.removeWatchlist(anime.id);
                        if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                        if (mounted) setState(() {});
                      },
                      borderRadius: AppRadii.control,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: AppRadii.control,
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.danger,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Remove from Watchlist',
                              style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddToCollectionDialog(
    BuildContext context,
    Anime anime,
  ) async {
    final storage = ref.read(storageServiceProvider);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final collections = storage.getCollections();
          return Dialog(
            backgroundColor: AppColors.secondaryBg,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadii.dialog,
              side: BorderSide(color: AppColors.border),
            ),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.playlist_add_rounded,
                        color: AppColors.brandRed,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Save to Collection',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: collections.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No collections created yet.',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: collections.length,
                            itemBuilder: (context, index) {
                              final col = collections[index];
                              final isMember = storage.isAnimeInCollection(
                                col.id,
                                anime.id,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () async {
                                    if (isMember) {
                                      await storage.removeAnimeFromCollection(
                                        col.id,
                                        anime.id,
                                      );
                                    } else {
                                      await storage.addAnimeToCollection(
                                        col.id,
                                        anime.id,
                                      );
                                    }
                                    setDialogState(() {});
                                    if (mounted) setState(() {});
                                  },
                                  borderRadius: AppRadii.control,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isMember
                                          ? AppColors.brandRed.withValues(
                                              alpha: 0.12,
                                            )
                                          : AppColors.surface,
                                      borderRadius: AppRadii.control,
                                      border: Border.all(
                                        color: isMember
                                            ? AppColors.brandRed
                                            : AppColors.borderSubtle,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isMember
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded,
                                          color: isMember
                                              ? AppColors.brandRed
                                              : AppColors.textMuted,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            col.name,
                                            style: TextStyle(
                                              color: isMember
                                                  ? Colors.white
                                                  : AppColors.textPrimary,
                                              fontSize: 13.5,
                                              fontWeight: isMember
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: const Text('Done'),
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

  @override
  Widget build(BuildContext context) {
    final storageService = ref.watch(storageServiceProvider);
    final user = ref.watch(authStateProvider);

    final animeAsync = ref.watch(animeDetailsProvider(widget.animeId));
    final episodesAsync = ref.watch(animeEpisodesProvider(widget.animeId));
    final extraInfoAsync = ref.watch(animeExtraInfoProvider(widget.animeId));
    final recommendedAsync = ref.watch(
      recommendedAnimeProvider(widget.animeId),
    );

    return Focus(
      onKeyEvent: (node, event) => _handleKey(context, event),
      child: Scaffold(
        backgroundColor: AppColors.primaryBg,
        body: animeAsync.when(
          data: (anime) {
            if (anime == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.movie_filter_rounded,
                      color: AppColors.textMuted,
                      size: 48,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Anime title not found',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: () => _goBack(context),
                      child: const Text('Return Home'),
                    ),
                  ],
                ),
              );
            }

            final activeUserId =
                user?.id ?? StorageService.guestWatchHistoryUserId;
            final watchEntry = storageService.getWatchEntryForAnime(
              anime.id,
              userId: activeUserId,
            );
            final resumeEpisodeNumber = watchEntry?.lastWatchedEpisode ?? 1;

            final episodes = episodesAsync.asData?.value;
            final provisionalEpisodes = _provisionalEpisodes(anime);
            final availableEpisodes = episodes != null && episodes.isNotEmpty
                ? episodes
                : provisionalEpisodes;

            final description = _resolvedDescription(
              anime,
              extraInfoAsync.asData?.value,
            );
            final isUpcoming =
                anime.status.toLowerCase().contains('upcoming') ||
                anime.status.toLowerCase().contains('not yet') ||
                anime.status.toLowerCase().contains('not_yet');

            final pageLeftPadding = DesktopLayout.pageLeftPadding(context);
            final pageRightPadding = DesktopLayout.pagePadding(context);
            final heroImageUrl = anime.backdropUrl.trim().isNotEmpty
                ? anime.backdropUrl
                : anime.posterUrl;
            final inWatchlist = storageService.isInWatchlist(anime.id);
            final watchlistStatus = storageService.getWatchlistStatus(anime.id);
            final ageRating = _getAgeRating(anime);

            final filteredEpisodes = availableEpisodes.where((ep) {
              if (_episodeSearchFilter.trim().isEmpty) return true;
              final q = _episodeSearchFilter.trim().toLowerCase();
              return ep.episodeNumber.toString() == q ||
                  ep.title.toLowerCase().contains(q);
            }).toList();

            return SingleChildScrollView(
              controller: _detailsScrollController,
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top Panoramic Backdrop & Navigation Bar ──
                  Stack(
                    children: [
                      // Backdrop Banner with dark bottom vignette
                      SliverBackdropBanner(heroImageUrl: heroImageUrl),

                      // Navigation Bar (Back Button)
                      Positioned(
                        top: 20,
                        left: pageLeftPadding,
                        child: DesktopBackButton(
                          focusNode: _backButtonFocusNode,
                          onPressed: () => _goBack(context),
                        ),
                      ),

                      // ── Two-Column Desktop Hero Header ──
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          pageLeftPadding,
                          120,
                          pageRightPadding,
                          28,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── LEFT COLUMN: Poster & Actions (~240px) ──
                            SizedBox(
                              width: 240,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Poster Card
                                  Container(
                                    height: 350,
                                    decoration: BoxDecoration(
                                      borderRadius: AppRadii.card,
                                      boxShadow: const [AppColors.shadowPoster],
                                      border: Border.all(
                                        color: AppColors.borderStrong,
                                        width: 1.0,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: WebSafeImage(
                                      url: anime.posterUrl,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  // Primary Action: Watch / Resume
                                  if (!isUpcoming) ...[
                                    ElevatedButton.icon(
                                      focusNode: _startWatchingFocusNode,
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 20,
                                      ),
                                      label: Text(
                                        watchEntry != null
                                            ? 'Resume EP $resumeEpisodeNumber'
                                            : 'Start Watching',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.brandRed,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size.fromHeight(38),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: AppRadii.control,
                                        ),
                                      ),
                                      onPressed: () {
                                        if (availableEpisodes.isEmpty) return;
                                        final ep = availableEpisodes.firstWhere(
                                          (e) =>
                                              e.episodeNumber ==
                                              resumeEpisodeNumber,
                                          orElse: () => availableEpisodes.first,
                                        );
                                        context.push(
                                          '/watch/${anime.id}/${ep.id}',
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                  ],

                                  // Watchlist Button
                                  OutlinedButton.icon(
                                    focusNode: _watchlistFocusNode,
                                    icon: Icon(
                                      inWatchlist
                                          ? Icons.bookmark_added_rounded
                                          : Icons.bookmark_add_outlined,
                                      size: 17,
                                      color: inWatchlist
                                          ? AppColors.brandRed
                                          : AppColors.textPrimary,
                                    ),
                                    label: Text(
                                      inWatchlist
                                          ? watchlistStatus
                                          : 'Add to List',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: inWatchlist
                                            ? AppColors.brandRed
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: inWatchlist
                                          ? AppColors.brandRed.withValues(
                                              alpha: 0.12,
                                            )
                                          : AppColors.surface,
                                      side: BorderSide(
                                        color: inWatchlist
                                            ? AppColors.brandRed
                                            : AppColors.border,
                                      ),
                                      minimumSize: const Size.fromHeight(38),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                      ),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: AppRadii.control,
                                      ),
                                    ),
                                    onPressed: () => _showWatchlistStatusDialog(
                                      context,
                                      anime,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Collection & Share Buttons Row
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          focusNode: _collectionFocusNode,
                                          icon: const Icon(
                                            Icons.playlist_add_rounded,
                                            size: 17,
                                          ),
                                          label: const Text(
                                            'Collection',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: AppColors.surface,
                                            foregroundColor:
                                                AppColors.textSecondary,
                                            side: const BorderSide(
                                              color: AppColors.border,
                                            ),
                                            minimumSize: const Size(0, 38),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: AppRadii.control,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _showAddToCollectionDialog(
                                                context,
                                                anime,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        focusNode: _shareFocusNode,
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: AppColors.surface,
                                          foregroundColor:
                                              AppColors.textSecondary,
                                          side: const BorderSide(
                                            color: AppColors.border,
                                          ),
                                          minimumSize: const Size(38, 38),
                                          padding: const EdgeInsets.all(0),
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: AppRadii.control,
                                          ),
                                        ),
                                        onPressed: () => _shareAnime(anime),
                                        child: const Icon(
                                          Icons.share_rounded,
                                          size: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 32),

                            // ── RIGHT COLUMN: Metadata, Genres, Synopsis (Expanded) ──
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  // Main Title
                                  Text(
                                    anime.title,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                      height: 1.2,
                                    ),
                                  ),
                                  if (anime.alternativeTitles.isNotEmpty &&
                                      anime.alternativeTitles.first
                                          .trim()
                                          .isNotEmpty &&
                                      anime.alternativeTitles.first !=
                                          anime.title) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      anime.alternativeTitles.first,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),

                                  // Metadata Badges Row
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      // Score Badge
                                      if (anime.rating > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0x18F59E0B),
                                            borderRadius: AppRadii.control,
                                            border: Border.all(
                                              color: const Color(0x35F59E0B),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.star_rounded,
                                                color: Color(0xFFF59E0B),
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                anime.rating.toStringAsFixed(1),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      // Year Badge
                                      if (anime.year.isNotEmpty)
                                        _buildMetaBadge(anime.year),

                                      // Status Badge
                                      _buildMetaBadge(
                                        anime.status,
                                        color:
                                            anime.status.toLowerCase().contains(
                                              'airing',
                                            )
                                            ? AppColors.success
                                            : null,
                                      ),

                                      // Total Episodes
                                      _buildMetaBadge(
                                        anime.totalEpisodes > 0
                                            ? '${anime.totalEpisodes} Episodes'
                                            : 'Episodes TBA',
                                      ),

                                      // Age Rating
                                      _buildMetaBadge(ageRating),
                                    ],
                                  ),
                                  const SizedBox(height: 14),

                                  // Genre Chips
                                  if (anime.genres.isNotEmpty)
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: anime.genres.map((g) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: AppRadii.control,
                                            border: Border.all(
                                              color: AppColors.borderSubtle,
                                            ),
                                          ),
                                          child: Text(
                                            g,
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  const SizedBox(height: 18),

                                  // Synopsis
                                  const Text(
                                    'SYNOPSIS',
                                    style: TextStyle(
                                      color: AppColors.brandRed,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    description,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13.5,
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // ── Episodes Section ──
                  if (!isUpcoming) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        pageLeftPadding,
                        8,
                        pageRightPadding,
                        14,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Episodes (${availableEpisodes.length})',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Tooltip(
                            message: 'Download episodes',
                            child: IconButton(
                              icon: const Icon(Icons.download_outlined),
                              color: AppColors.accentPrimary,
                              onPressed: episodes == null || episodes.isEmpty
                                  ? null
                                  : () => showAnimeDownloadDialog(
                                      context,
                                      anime,
                                      episodes,
                                    ),
                            ),
                          ),
                          // Quick episode search / filter
                          SizedBox(
                            width: 170,
                            height: 32,
                            child: TextField(
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Filter episode...',
                                hintStyle: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                                prefixIcon: const Icon(
                                  Icons.filter_list_rounded,
                                  size: 15,
                                  color: AppColors.textMuted,
                                ),
                                contentPadding: EdgeInsets.zero,
                                filled: true,
                                fillColor: AppColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: AppRadii.control,
                                  borderSide: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: AppRadii.control,
                                  borderSide: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: AppRadii.control,
                                  borderSide: const BorderSide(
                                    color: AppColors.brandRed,
                                  ),
                                ),
                              ),
                              onChanged: (v) {
                                setState(() {
                                  _episodeSearchFilter = v;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Segmented View Mode Switcher (Cards, Number Pills, List)
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryBg,
                              borderRadius: AppRadii.control,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildViewModeButton(
                                  icon: Icons.grid_view_rounded,
                                  tooltip: 'Compact Cards',
                                  mode: 0,
                                ),
                                _buildViewModeButton(
                                  icon: Icons.apps_rounded,
                                  tooltip: 'Number Pills',
                                  mode: 1,
                                ),
                                _buildViewModeButton(
                                  icon: Icons.view_list_rounded,
                                  tooltip: 'Detailed List',
                                  mode: 2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Episodes Shelf / Grid
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        pageLeftPadding,
                        0,
                        pageRightPadding,
                        32,
                      ),
                      child: SizedBox(
                        height: filteredEpisodes.length > 24 ? 480 : 280,
                        child: _episodeViewMode == 0
                            ? _buildEpisodeGrid(
                                context,
                                anime,
                                filteredEpisodes,
                                resumeEpisodeNumber,
                                watchEntry,
                              )
                            : _episodeViewMode == 1
                            ? _buildNumberPillsGrid(
                                context,
                                anime,
                                filteredEpisodes,
                                resumeEpisodeNumber,
                                watchEntry,
                              )
                            : _buildEpisodeList(
                                context,
                                anime,
                                filteredEpisodes,
                                resumeEpisodeNumber,
                                watchEntry,
                              ),
                      ),
                    ),
                  ],

                  // ── Franchise & Related Anime ──
                  Builder(
                    builder: (context) {
                      final extraData = extraInfoAsync.asData?.value;
                      final relationsRaw =
                          (extraData?['relations']?['edges'] as List?) ?? [];
                      final animeRelations = relationsRaw.where((edge) {
                        final node = edge['node'];
                        final type = node?['type']?.toString();
                        return type == 'ANIME';
                      }).toList();

                      if (animeRelations.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              left: pageLeftPadding,
                              right: pageRightPadding,
                            ),
                            child: const Text(
                              'Related Anime',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 220,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.only(
                                left: pageLeftPadding,
                                right: pageRightPadding,
                              ),
                              itemCount: animeRelations.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final edge = animeRelations[index];
                                final node = edge['node'] ?? {};
                                final relId = node['id']?.toString() ?? '';
                                final relTitle =
                                    node['title']?['english'] ??
                                    node['title']?['romaji'] ??
                                    node['title']?['userPreferred'] ??
                                    'Unknown';
                                final cover =
                                    node['coverImage']?['large'] ?? '';
                                final relationType =
                                    edge['relationType']?.toString() ??
                                    'RELATED';

                                return InkWell(
                                  onTap: () {
                                    if (relId.isNotEmpty) {
                                      context.push('/anime/$relId');
                                    }
                                  },
                                  borderRadius: AppRadii.card,
                                  child: Container(
                                    width: 135,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: AppRadii.card,
                                      border: Border.all(
                                        color: AppColors.borderSubtle,
                                      ),
                                      boxShadow: const [AppColors.shadowSoft],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              WebSafeImage(
                                                url: cover,
                                                fit: BoxFit.cover,
                                              ),
                                              Positioned(
                                                top: 6,
                                                left: 6,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 2,
                                                      ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        color:
                                                            AppColors.brandRed,
                                                        borderRadius:
                                                            AppRadii.control,
                                                      ),
                                                  child: Text(
                                                    relationType,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 8.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(
                                            relTitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      );
                    },
                  ),

                  // ── Recommendations Shelf ──
                  recommendedAsync.when(
                    data: (recs) {
                      if (recs.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              left: pageLeftPadding,
                              right: pageRightPadding,
                            ),
                            child: const Text(
                              'Recommendations',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 280,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.only(
                                left: pageLeftPadding,
                                right: pageRightPadding,
                              ),
                              itemCount: recs.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final rAnime = recs[index];
                                return SizedBox(
                                  width: 145,
                                  child: AnimeCard(
                                    anime: rAnime,
                                    width: 145,
                                    height: 210,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 48),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accentPrimary),
          ),
          error: (err, _) => Center(
            child: Text(
              'Error loading anime details: $err',
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaBadge(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.control,
        border: Border.all(color: color ?? AppColors.borderSubtle),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? AppColors.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required String tooltip,
    required int mode,
  }) {
    final isSelected = _episodeViewMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            _episodeViewMode = mode;
          });
        },
        borderRadius: AppRadii.control,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandRed : Colors.transparent,
            borderRadius: AppRadii.control,
          ),
          child: Icon(
            icon,
            size: 15,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPillsGrid(
    BuildContext context,
    Anime anime,
    List<Episode> episodes,
    int resumeEpisodeNumber,
    WatchEntry? watchEntry,
  ) {
    if (episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No matching episodes found.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 56).floor().clamp(6, 20);
        return GridView.builder(
          primary: false,
          physics: const ClampingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.0,
          ),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final ep = episodes[index];
            final isCurrentResume = ep.episodeNumber == resumeEpisodeNumber;
            final isWatched =
                watchEntry != null &&
                (ep.episodeNumber < resumeEpisodeNumber ||
                    (isCurrentResume && watchEntry.isCompleted));

            return Tooltip(
              message: 'Episode ${ep.episodeNumber}: ${ep.title}',
              child: InkWell(
                onTap: () => context.push('/watch/${anime.id}/${ep.id}'),
                borderRadius: AppRadii.control,
                child: Container(
                  decoration: BoxDecoration(
                    color: isCurrentResume
                        ? AppColors.brandRed
                        : (isWatched
                              ? AppColors.surface
                              : AppColors.secondaryBg),
                    borderRadius: AppRadii.control,
                    border: Border.all(
                      color: isCurrentResume
                          ? AppColors.brandRed
                          : (isWatched
                                ? AppColors.brandRed.withValues(alpha: 0.4)
                                : AppColors.borderSubtle),
                      width: isCurrentResume ? 1.5 : 1.0,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${ep.episodeNumber}',
                      style: TextStyle(
                        color: isCurrentResume
                            ? Colors.white
                            : (isWatched
                                  ? AppColors.brandRed
                                  : AppColors.textSecondary),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEpisodeGrid(
    BuildContext context,
    Anime anime,
    List<Episode> episodes,
    int resumeEpisodeNumber,
    WatchEntry? watchEntry,
  ) {
    if (episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No matching episodes found.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 145).floor().clamp(3, 8);
        return GridView.builder(
          primary: false,
          physics: const ClampingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.62,
          ),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final ep = episodes[index];
            final isCurrentResume = ep.episodeNumber == resumeEpisodeNumber;
            final isWatched =
                watchEntry != null &&
                (ep.episodeNumber < resumeEpisodeNumber ||
                    (isCurrentResume && watchEntry.isCompleted));
            final progress = (isCurrentResume && watchEntry != null)
                ? (ep.duration.inSeconds > 0
                      ? (watchEntry.watchedDuration.inSeconds /
                                ep.duration.inSeconds)
                            .clamp(0.0, 1.0)
                      : 0.0)
                : (isWatched ? 1.0 : 0.0);

            return InkWell(
              onTap: () => context.push('/watch/${anime.id}/${ep.id}'),
              borderRadius: AppRadii.card,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.card,
                  border: Border.all(
                    color: isCurrentResume
                        ? AppColors.brandRed
                        : AppColors.borderSubtle,
                    width: isCurrentResume ? 1.5 : 1.0,
                  ),
                  boxShadow: const [AppColors.shadowSoft],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          WebSafeImage(
                            url:
                                (ep.thumbnailUrl != null &&
                                    ep.thumbnailUrl!.isNotEmpty)
                                ? ep.thumbnailUrl!
                                : anime.backdropUrl,
                            fit: BoxFit.cover,
                          ),
                          Container(
                            color: Colors.black.withValues(alpha: 0.25),
                          ),
                          Positioned(
                            top: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: isCurrentResume
                                    ? AppColors.brandRed
                                    : AppColors.surface.withValues(alpha: 0.9),
                                borderRadius: AppRadii.control,
                              ),
                              child: Text(
                                'EP ${ep.episodeNumber}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.0,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          if (progress > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 2.0,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.brandRed,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              ep.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrentResume
                                    ? AppColors.brandRed
                                    : AppColors.textPrimary,
                                fontSize: 11.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${ep.duration.inMinutes > 0 ? ep.duration.inMinutes : 24}m',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEpisodeList(
    BuildContext context,
    Anime anime,
    List<Episode> episodes,
    int resumeEpisodeNumber,
    WatchEntry? watchEntry,
  ) {
    return ListView.separated(
      primary: false,
      physics: const ClampingScrollPhysics(),
      itemCount: episodes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final ep = episodes[index];
        final isCurrentResume = ep.episodeNumber == resumeEpisodeNumber;
        return InkWell(
          onTap: () => context.push('/watch/${anime.id}/${ep.id}'),
          borderRadius: AppRadii.control,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isCurrentResume
                  ? AppColors.brandRed.withValues(alpha: 0.1)
                  : AppColors.surface,
              borderRadius: AppRadii.control,
              border: Border.all(
                color: isCurrentResume
                    ? AppColors.brandRed
                    : AppColors.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  alignment: Alignment.center,
                  child: Text(
                    'EP ${ep.episodeNumber}',
                    style: TextStyle(
                      color: isCurrentResume
                          ? AppColors.brandRed
                          : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    ep.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrentResume
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isCurrentResume
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${ep.duration.inMinutes > 0 ? ep.duration.inMinutes : 24}m',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.play_circle_outline_rounded,
                  color: isCurrentResume
                      ? AppColors.brandRed
                      : AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SliverBackdropBanner extends StatelessWidget {
  final String heroImageUrl;

  const SliverBackdropBanner({super.key, required this.heroImageUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 340,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebSafeImage(url: heroImageUrl, fit: BoxFit.cover),
          // Left dark fade
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppColors.primaryBg.withValues(alpha: 0.95),
                    AppColors.primaryBg.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),
          // Bottom gradient fade into background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.primaryBg.withValues(alpha: 0.8),
                    AppColors.primaryBg,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
