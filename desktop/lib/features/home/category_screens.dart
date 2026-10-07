import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../services/anime_service.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/loading_shimmer.dart';
import '../../widgets/desktop_layout.dart';

class HotRightNowScreen extends StatelessWidget {
  const HotRightNowScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _CategoryPage(title: 'Hot Right Now', provider: hotRightNowProvider);
}

class UpcomingAnimeScreen extends StatelessWidget {
  const UpcomingAnimeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _CategoryPage(title: 'Upcoming Anime', provider: upcomingAnimeProvider);
}

class EveryonesWatchingScreen extends StatelessWidget {
  const EveryonesWatchingScreen({super.key});

  @override
  Widget build(BuildContext context) => _CategoryPage(
    title: "Everyone's Watching",
    provider: everyonesWatchingProvider,
  );
}

class BestOf2025Screen extends StatelessWidget {
  const BestOf2025Screen({super.key});

  @override
  Widget build(BuildContext context) =>
      _CategoryPage(title: 'Best of 2025', provider: recentlyUpdatedProvider);
}

class TopPicksScreen extends StatelessWidget {
  const TopPicksScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _CategoryPage(title: 'Top Picks', provider: topPicksProvider);
}

class TopMoviesScreen extends StatelessWidget {
  const TopMoviesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _CategoryPage(title: 'Top Movies', provider: topMoviesProvider);
}

class CuratedForYouScreen extends StatelessWidget {
  const CuratedForYouScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _CategoryPage(title: 'Curated For You', provider: curatedForYouProvider);
}

class RecommendedScreen extends StatelessWidget {
  const RecommendedScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      _CategoryPage(title: 'Recommended', provider: recommendedProvider);
}

class _CategoryPage extends ConsumerWidget {
  final String title;
  final FutureProvider<List<Anime>> provider;

  const _CategoryPage({required this.title, required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(provider);
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Stack(
        children: [
          const Positioned.fill(child: DesktopBackground()),
          SafeArea(
            child: Column(
              children: [
                DesktopPageHeader(
                  eyebrow: 'COLLECTION',
                  title: title,
                  subtitle: 'Curated for the big screen',
                  leading: DesktopBackButton(
                    autofocus: true,
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/home'),
                  ),
                ),
                Expanded(
                  child: asyncList.when(
                    data: (list) {
                      final items = list.take(30).toList();
                      if (items.isEmpty) {
                        return const DesktopEmptyState(
                          icon: Icons.video_library_outlined,
                          title: 'No titles yet',
                          message:
                              'This collection is being refreshed. Check back shortly.',
                        );
                      }
                      return _buildCategoryGrid(context, items);
                    },
                    loading: () => Padding(
                      padding: EdgeInsets.all(
                        DesktopLayout.pagePadding(context),
                      ),
                      child: LoadingShimmer.landscapeGrid(count: 9),
                    ),
                    error: (_, _) => const DesktopEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Collection unavailable',
                      message:
                          'AniWings could not load this collection. Check your connection and try again.',
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
}

Widget _buildCategoryGrid(BuildContext context, List<Anime> items) {
  final leftPadding = DesktopLayout.pageLeftPadding(context);
  final rightPadding = DesktopLayout.pagePadding(context);

  return GridView.builder(
    clipBehavior: Clip.none,
    scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
    padding: EdgeInsets.fromLTRB(leftPadding, 6, rightPadding, 36),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: DesktopLayout.landscapeGridMaxExtent(context),
      childAspectRatio: 16 / 9,
      crossAxisSpacing: DesktopLayout.cardGap(context),
      mainAxisSpacing: DesktopLayout.cardGap(context),
    ),
    itemCount: items.length,
    itemBuilder: (context, index) => AnimeCard(
      anime: items[index],
      width: double.infinity,
      height: double.infinity,
      layout: AnimeCardLayout.landscape,
    ),
  );
}
