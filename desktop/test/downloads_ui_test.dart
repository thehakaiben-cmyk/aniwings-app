import 'package:aniwings/core/theme/app_colors.dart';
import 'package:aniwings/core/theme/app_theme.dart';
import 'package:aniwings/features/downloads/downloads_screen.dart';
import 'package:aniwings/models/anime.dart';
import 'package:aniwings/models/episode.dart';
import 'package:aniwings/models/video_provider.dart';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/download_service.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Catalog extends AnimeService {
  @override
  Future<List<VideoProviderSource>> getVideoProvidersForEpisode(
    String id,
    int number,
  ) async => [];
}

void main() {
  test('AMOLED background uses the mobile accent palette', () {
    expect(AppColors.primaryBg, Colors.black);
    expect(AppColors.accentPrimary, const Color(0xFFFF2A54));
    expect(AppColors.textSecondary, const Color(0xFF94A3B8));
  });
  for (final size in [const Size(1280, 720), const Size(960, 540)]) {
    testWidgets(
      'batch download picker fits $size and queues selected episodes with saved defaults',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'settings_default_download_quality': '720P',
          'settings_default_download_audio': 'DUB',
        });
        final preferences = await SharedPreferences.getInstance();
        final catalog = _Catalog();
        addTearDown(catalog.dispose);
        final anime = Anime(
          id: 'download-ui',
          title: 'Anime download test with a long title',
          description: '',
          posterUrl: '',
          backdropUrl: '',
          rating: 8,
          status: 'Completed',
          genres: const [],
          totalEpisodes: 20,
          year: '2026',
        );
        final episodes = List.generate(
          20,
          (index) => Episode(
            id: 'episode-$index',
            animeId: anime.id,
            episodeNumber: index + 1,
            title: 'Episode ${index + 1}',
            airDate: DateTime(2026),
            duration: const Duration(minutes: 24),
            videoUrls: const [],
          ),
        );
        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              animeServiceProvider.overrideWithValue(catalog),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return Scaffold(
                    body: Center(
                      child: FilledButton(
                        onPressed: () =>
                            showAnimeDownloadDialog(context, anime, episodes),
                        child: const Text('Download'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('Download'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.byType(DropdownButton<String>),
              )
              .value,
          '720P',
        );
        await tester.enterText(find.byType(TextField), 'Episode 20');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select all visible'));
        await tester.pumpAndSettle();
        expect(find.text('Download 1 episode(s)'), findsOneWidget);
        await tester.tap(find.text('Download 1 episode(s)'));
        await tester.pumpAndSettle();
        final task = container.read(downloadServiceProvider).tasks.single;
        expect(task.episode.episodeNumber, 20);
        expect(task.quality, '720P');
        expect(task.audio, 'DUB');
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
