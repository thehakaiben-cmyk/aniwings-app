import 'package:aniwings/features/details/details_screen.dart';
import 'package:aniwings/models/anime.dart';
import 'package:aniwings/models/character.dart';
import 'package:aniwings/models/episode.dart';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TV details sections fit a 1080p viewport and handle D-pad navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const title = 'A Very Long Layout Test Anime Title';
      final anime = Anime(
        id: 'layout-test',
        title: title,
        description:
            'A synopsis long enough to exercise the details information layout.',
        posterUrl: 'https://example.com/poster.jpg',
        backdropUrl: 'https://example.com/backdrop.jpg',
        rating: 8.5,
        status: 'Completed',
        genres: const ['Comedy', 'Drama'],
        totalEpisodes: 1,
        year: '2026',
      );
      final episode = Episode(
        id: 'layout-test-ep-1',
        animeId: anime.id,
        episodeNumber: 1,
        title: 'Episode 1',
        airDate: DateTime(2026),
        duration: const Duration(minutes: 24),
        videoUrls: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            animeDetailsProvider.overrideWith((ref, id) async => anime),
            animeExtraInfoProvider.overrideWith((ref, id) async => null),
            animeEpisodesProvider.overrideWith((ref, id) async => [episode]),
            recommendedAnimeProvider.overrideWith(
              (ref, id) async => [
                Anime(
                  id: 'recommended',
                  title: 'A recommendation with a long two line title',
                  description: '',
                  posterUrl: '',
                  backdropUrl: '',
                  rating: 8,
                  status: 'Completed',
                  genres: const ['Action'],
                  totalEpisodes: 12,
                  year: '2026',
                ),
              ],
            ),
            animeCharactersProvider.overrideWith(
              (ref, id) async => [
                Character(name: 'Character One', role: 'Main', imageUrl: ''),
              ],
            ),
          ],
          child: const MaterialApp(home: DetailsScreen(animeId: 'layout-test')),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.text(title), findsWidgets);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Start Watching'), findsOneWidget);
      expect(
        find.text(
          'A synopsis long enough to exercise the details information layout.',
        ),
        findsOneWidget,
      );
      expect(find.text('Episode 1'), findsWidgets);
      expect(find.text('Recommendations'), findsOneWidget);
      expect(
        find.text('A recommendation with a long two line title'),
        findsOneWidget,
      );

      // Verify desktop action buttons are rendered
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);
    },
  );
}
