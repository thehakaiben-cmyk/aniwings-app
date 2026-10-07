import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/focus/desktop_focus_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../models/watch_entry.dart';
import '../../services/anime_service.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/web_safe_image.dart';

/// AniWings Desktop — Viewing History and Timeline Screen.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final ScrollController _scrollController;
  final Map<String, Future<Anime?>> _animeFutures = {};
  String _filter = 'All'; // 'All', 'In Progress', 'Completed'
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DesktopFocusManager.instance.restoreScreenFocus('/history');
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<Anime?> _getAnime(
    AnimeService service,
    StorageService storage,
    String animeId,
  ) {
    return _animeFutures.putIfAbsent(animeId, () async {
      final cached = storage.getCachedAnimeById(animeId);
      if (cached != null) return cached;
      return service.getAnimeById(animeId);
    });
  }

  String _timelineGroup(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeek = today.subtract(const Duration(days: 7));
    final entryDate = DateTime(date.year, date.month, date.day);

    if (entryDate == today) return 'Today';
    if (entryDate == yesterday) return 'Yesterday';
    if (entryDate.isAfter(thisWeek)) return 'This Week';
    return 'Earlier';
  }

  void _showClearAllConfirmation(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.secondaryBg,
            borderRadius: AppRadii.dialog,
            border: Border.all(color: AppColors.border, width: 1.0),
            boxShadow: const [AppColors.shadowPanel],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandRed.withValues(alpha: 0.15),
                      borderRadius: AppRadii.control,
                      border: Border.all(
                        color: AppColors.brandRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_sweep_rounded,
                      color: AppColors.brandRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Clear Viewing History?',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'This will remove all recorded watch progress across all anime series for this profile. This action cannot be undone.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.control,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.control,
                      ),
                    ),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      final user = ref.read(authStateProvider);
                      final uid =
                          user?.id ?? StorageService.guestWatchHistoryUserId;
                      await ref
                          .read(storageServiceProvider)
                          .clearWatchHistory(userId: uid);
                      if (mounted) {
                        setState(() {
                          _animeFutures.clear();
                        });
                        ref.read(storageRevisionProvider.notifier).state++;
                      }
                    },
                    child: const Text(
                      'Clear History',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animeService = ref.watch(animeServiceProvider);
    final storageService = ref.watch(storageServiceProvider);
    final user = ref.watch(authStateProvider);
    final activeUserId = user?.id ?? StorageService.guestWatchHistoryUserId;

    ref.watch(storageRevisionProvider);

    final rawHistory = storageService.getWatchHistory(userId: activeUserId);
    final allHistory = rawHistory
        .where((entry) => !entry.isExternalSync)
        .toList();

    // Apply Filter
    final filteredHistory = allHistory.where((entry) {
      if (_filter == 'In Progress') return !entry.isCompleted;
      if (_filter == 'Completed') return entry.isCompleted;
      return true;
    }).toList();

    // Group entries by timeline
    final grouped = <String, List<WatchEntry>>{};
    for (final entry in filteredHistory) {
      final group = _timelineGroup(entry.lastWatchedAt);
      grouped.putIfAbsent(group, () => []).add(entry);
    }

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
                  // Desktop Header
                  _buildHeader(
                    context,
                    allHistory.length,
                    filteredHistory.length,
                  ),

                  const SizedBox(height: 18),

                  // Filter & View Mode Controls Bar
                  _buildControlsBar(allHistory.length),

                  const SizedBox(height: 20),

                  if (filteredHistory.isEmpty)
                    _buildEmptyState(context, isFiltered: allHistory.isNotEmpty)
                  else if (_isGridView)
                    _buildGridView(
                      filteredHistory,
                      animeService,
                      storageService,
                    )
                  else
                    ...grouped.entries.map((entry) {
                      final groupTitle = entry.key;
                      final entries = entry.value;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Group Title Banner
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12, top: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 3,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: AppColors.brandRed,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  groupTitle.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '(${entries.length})',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // List of Desktop History Cards
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final watchEntry = entries[index];
                              return _buildHistoryRow(
                                context: context,
                                entry: watchEntry,
                                animeFuture: _getAnime(
                                  animeService,
                                  storageService,
                                  watchEntry.animeId,
                                ),
                                activeUserId: activeUserId,
                              );
                            },
                          ),

                          const SizedBox(height: 14),
                        ],
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int totalCount, int filteredCount) {
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
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.brandRed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'WATCH TIMELINE',
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
                  'Viewing History',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
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
                    '$totalCount episodes logged',
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

        if (totalCount > 0)
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Clear All'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.borderStrong),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _showClearAllConfirmation(context),
          ),
      ],
    );
  }

  Widget _buildControlsBar(int totalCount) {
    const filters = ['All', 'In Progress', 'Completed'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.panel,
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Row(
        children: [
          // Filter tabs
          for (final f in filters) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () {
                  setState(() => _filter = f);
                },
                borderRadius: AppRadii.control,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _filter == f
                        ? AppColors.brandRed
                        : Colors.transparent,
                    borderRadius: AppRadii.control,
                    border: Border.all(
                      color: _filter == f
                          ? AppColors.brandRed
                          : AppColors.borderSubtle,
                    ),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      color: _filter == f
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: _filter == f
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],

          const Spacer(),

          // Grid vs List View Toggle
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            tooltip: _isGridView
                ? 'Switch to list view'
                : 'Switch to grid view',
            onPressed: () {
              setState(() => _isGridView = !_isGridView);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(
    List<WatchEntry> entries,
    AnimeService animeService,
    StorageService storageService,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 215,
            mainAxisExtent: 310,
            crossAxisSpacing: 18,
            mainAxisSpacing: 22,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return FutureBuilder<Anime?>(
              future: _getAnime(animeService, storageService, entry.animeId),
              builder: (context, snapshot) {
                final anime = snapshot.data;
                if (anime == null) {
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }
                return Stack(
                  children: [
                    AnimeCard(
                      anime: anime,
                      width: double.infinity,
                      height: double.infinity,
                      onTap: () {
                        final epId =
                            '${entry.animeId}_ep_${entry.lastWatchedEpisode}';
                        context.push('/watch/${entry.animeId}/$epId');
                      },
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.accentPrimary),
                        ),
                        child: Text(
                          'EP ${entry.lastWatchedEpisode}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryRow({
    required BuildContext context,
    required WatchEntry entry,
    required Future<Anime?> animeFuture,
    required String activeUserId,
  }) {
    final timeStr = DateFormat('MMM d, h:mm a').format(entry.lastWatchedAt);

    return FutureBuilder<Anime?>(
      future: animeFuture,
      builder: (context, snapshot) {
        final anime = snapshot.data;
        final title = anime?.title ?? 'Episode ${entry.lastWatchedEpisode}';
        final backdrop = anime?.backdropUrl.isNotEmpty == true
            ? anime!.backdropUrl
            : (anime?.posterUrl ?? '');

        final progress = entry.progressPercentage.clamp(0.0, 1.0);
        final itemKey = 'history_${entry.animeId}_${entry.lastWatchedEpisode}';

        return DesktopFocusWrapper.builder(
          registryKey: itemKey,
          onTap: () {
            DesktopFocusManager.instance.saveScreenFocus('/history', itemKey);
            final epId = '${entry.animeId}_ep_${entry.lastWatchedEpisode}';
            context.push('/watch/${entry.animeId}/$epId');
          },
          borderRadius: AppRadii.card,
          builder: (context, isFocused, isHovered) {
            final active = isFocused || isHovered;
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: active ? AppColors.hoverState : AppColors.surface,
                borderRadius: AppRadii.card,
                border: Border.all(
                  color: active ? AppColors.brandRed : AppColors.border,
                  width: 1.0,
                ),
                boxShadow: active ? const [AppColors.shadowSoft] : null,
              ),
              child: Row(
                children: [
                  // Landscape Thumbnail
                  ClipRRect(
                    borderRadius: AppRadii.control,
                    child: SizedBox(
                      width: 140,
                      height: 80,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (backdrop.isNotEmpty)
                            WebSafeImage(url: backdrop, fit: BoxFit.cover)
                          else
                            Container(color: AppColors.secondaryBg),

                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.65),
                                ],
                              ),
                            ),
                          ),

                          if (active)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: AppColors.brandRed,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),

                          // Progress Bar
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.brandRed,
                              ),
                              minHeight: 3.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Metadata Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: entry.isCompleted
                                    ? AppColors.success.withValues(alpha: 0.15)
                                    : AppColors.brandRed.withValues(
                                        alpha: 0.15,
                                      ),
                                borderRadius: AppRadii.control,
                                border: Border.all(
                                  color: entry.isCompleted
                                      ? AppColors.success.withValues(alpha: 0.4)
                                      : AppColors.brandRed.withValues(
                                          alpha: 0.4,
                                        ),
                                ),
                              ),
                              child: Text(
                                entry.isCompleted
                                    ? 'COMPLETED'
                                    : 'EPISODE ${entry.lastWatchedEpisode}',
                                style: TextStyle(
                                  color: entry.isCompleted
                                      ? AppColors.success
                                      : AppColors.brandRed,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: AppColors.textDisabled,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Stopped at ${entry.formattedWatchedDuration}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Action Buttons: Resume, Details, Delete
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(
                          'Resume EP ${entry.lastWatchedEpisode}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.borderStrong),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () {
                          final epId =
                              '${entry.animeId}_ep_${entry.lastWatchedEpisode}';
                          context.push('/watch/${entry.animeId}/$epId');
                        },
                      ),
                      const SizedBox(width: 8),
                      if (anime != null)
                        IconButton(
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                          ),
                          tooltip: 'Anime details',
                          color: AppColors.textSecondary,
                          onPressed: () {
                            context.push('/anime/${entry.animeId}');
                          },
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        tooltip: 'Remove from history',
                        color: AppColors.textMuted,
                        hoverColor: AppColors.danger.withValues(alpha: 0.15),
                        onPressed: () async {
                          await ref
                              .read(storageServiceProvider)
                              .removeWatchEntry(
                                entry.animeId,
                                userId: activeUserId,
                              );
                          if (mounted) {
                            setState(() {
                              _animeFutures.remove(entry.animeId);
                            });
                            ref.read(storageRevisionProvider.notifier).state++;
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, {bool isFiltered = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.brandRed.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_rounded,
              color: AppColors.brandRed,
              size: 44,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isFiltered
                ? 'No matching history entries'
                : 'No viewing history yet',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltered
                ? 'Try selecting a different filter option above.'
                : 'Episodes and movies you watch on AniWings Desktop will automatically appear here with saved resume points.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (!isFiltered) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Browse Anime'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => context.go('/home'),
            ),
          ],
        ],
      ),
    );
  }
}
