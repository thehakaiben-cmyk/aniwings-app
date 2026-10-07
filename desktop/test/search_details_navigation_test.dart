import 'package:aniwings/features/details/details_screen.dart';
import 'package:aniwings/features/search/search_screen.dart';
import 'package:aniwings/models/anime.dart';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:aniwings/widgets/anime_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'clicking a search result opens its details and Back restores search',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final anime = Anime(
        id: 'dragon-ball',
        title: 'Dragon Ball',
        description: 'Fixture synopsis',
        posterUrl: '',
        backdropUrl: '',
        rating: 8,
        status: 'Completed',
        genres: const ['Action'],
        totalEpisodes: 1,
        year: '1986',
      );
      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
          GoRoute(
            path: '/anime/:id',
            builder: (_, state) =>
                DetailsScreen(animeId: state.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            searchAnimeProvider.overrideWith((ref) async => [anime]),
            animeDetailsProvider.overrideWith((ref, id) async => anime),
            animeEpisodesProvider.overrideWith((ref, id) async => []),
            animeExtraInfoProvider.overrideWith((ref, id) async => null),
            animeCharactersProvider.overrideWith((ref, id) async => []),
            recommendedAnimeProvider.overrideWith((ref, id) async => []),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.enterText(find.byType(TextField), 'dragon ball');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.byType(AnimeCard).first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DetailsScreen>(find.byType(DetailsScreen)).animeId,
        'dragon-ball',
      );
      expect(find.byType(DetailsScreen), findsOneWidget);
      expect(find.text('Fixture synopsis'), findsOneWidget);
      expect(StorageService(prefs).getSearchHistory(), contains('dragon ball'));
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'dragon ball',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
