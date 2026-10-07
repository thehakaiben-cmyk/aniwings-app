import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aniwings/core/theme/app_theme.dart';
import 'package:aniwings/features/settings/desktop_settings_screen.dart';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/metadata_provider_service.dart';
import 'package:aniwings/services/storage_service.dart';

Map<String, dynamic> media({int? mal = 1, int id = 100}) => {
  'id': id,
  'idMal': mal,
  'title': {'english': 'AniList Title'},
  'description': 'AniList description',
  'coverImage': {'large': ''},
  'status': 'RELEASING',
  'genres': ['Action'],
  'episodes': 12,
  'seasonYear': 2026,
  'nextAiringEpisode': {
    'episode': 4,
    'airingAt':
        DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch ~/
        1000,
  },
  'airingSchedule': {
    'nodes': [
      for (final number in [1, 2, 3])
        {
          'episode': number,
          'airingAt': DateTime(2026).millisecondsSinceEpoch ~/ 1000,
        },
    ],
  },
  'streamingEpisodes': [
    {'title': 'Episode 3 - Third', 'thumbnail': 'third.jpg'},
    {'title': 'Episode 1 - First', 'thumbnail': 'first.jpg'},
  ],
  'characters': {'edges': []},
};

final malData = <String, dynamic>{
  'mal_id': 1,
  'title': 'MAL Title',
  'synopsis': 'MAL description',
  'status': 'Currently Airing',
  'episodes': 12,
  'year': 2026,
  'genres': [
    {'name': 'Action'},
  ],
};

void main() {
  late SharedPreferences prefs;
  late StorageService storage;
  late List<Uri> requests;
  late MockClient client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    requests = [];
    client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'graphql.anilist.co') {
        final body = jsonDecode(request.body) as Map;
        final query = body['query'] as String;
        if (query.contains('mediaByMalId')) {
          return http.Response(
            jsonEncode({
              'data': {'mediaByMalId': media(), 'mediaById': media()},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {
              'Page': {
                'media': [media()],
              },
            },
          }),
          200,
        );
      }
      if (request.url.host == 'api.jikan.moe') {
        final path = request.url.path;
        if (path.endsWith('/full')) {
          return http.Response(jsonEncode({'data': malData}), 200);
        }
        if (path.endsWith('/episodes')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'mal_id': 1,
                  'title': 'MAL episode one',
                  'aired': '2026-01-01T00:00:00Z',
                },
              ],
              'pagination': {'has_next_page': false},
            }),
            200,
          );
        }
        if (path.endsWith('/characters')) {
          return http.Response('{"data":[]}', 200);
        }
        return http.Response(
          jsonEncode({
            'data': [malData],
          }),
          200,
        );
      }
      throw StateError('Unexpected metadata host ${request.url}');
    });
  });

  test(
    'AniList applies to home, browse, search, details and released episodes without MAL requests',
    () async {
      final service = AnimeService(
        storage: storage,
        metadataProvider: MetadataProvider.aniList,
        client: client,
      );
      expect((await service.getTrendingAnime()).first.title, 'AniList Title');
      expect((await service.getHotRightNow()).first.title, 'AniList Title');
      expect(
        (await service.queryAnime(
          query: 'Title',
          genre: 'All',
          sortBy: 'Rating',
        )).first.title,
        'AniList Title',
      );
      expect(
        (await service.queryAnime(
          query: '',
          genre: 'Action',
          sortBy: 'Latest',
        )).first.title,
        'AniList Title',
      );
      expect((await service.getAnimeById('1'))?.title, 'AniList Title');
      final episodes = await service.getEpisodesForAnime('1');
      expect(episodes.map((episode) => episode.episodeNumber), [1, 2, 3]);
      expect(episodes.first.title, 'Episode 1 - First');
      expect(episodes.last.title, 'Episode 3 - Third');
      expect(episodes[1].title, 'Episode 2');
      expect(episodes.first.animeId, '1');
      expect(requests.every((url) => url.host == 'graphql.anilist.co'), isTrue);
    },
  );

  test(
    'MAL applies to catalog, details, characters and episodes without depending on AniList',
    () async {
      final service = AnimeService(
        storage: storage,
        metadataProvider: MetadataProvider.myAnimeList,
        client: client,
      );
      expect((await service.getTrendingAnime()).first.title, 'MAL Title');
      expect(
        (await service.queryAnime(
          query: 'Title',
          genre: 'All',
          sortBy: 'Rating',
        )).first.title,
        'MAL Title',
      );
      expect((await service.getAnimeById('1'))?.description, 'MAL description');
      await service.getCharactersForAnime('1');
      await service.getMetadataExtraInfo('1');
      final episodes = await service.getEpisodesForAnime('1');
      expect(episodes.length, 1);
      expect(episodes.first.title, 'MAL episode one');
      expect(requests.every((url) => url.host == 'api.jikan.moe'), isTrue);
    },
  );

  test(
    'switch recreates service, refreshes providers, separates caches and persists choice',
    () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          animeServiceProvider.overrideWith(
            (ref) => AnimeService(
              storage: ref.watch(storageServiceProvider),
              metadataProvider: ref.watch(metadataProviderPreference),
              client: client,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        (await container.read(trendingAnimeProvider.future)).first.title,
        'AniList Title',
      );
      await container
          .read(metadataProviderPreference.notifier)
          .select(MetadataProvider.myAnimeList);
      expect(
        (await container.read(trendingAnimeProvider.future)).first.title,
        'MAL Title',
      );
      expect(prefs.getString('metadata_provider'), 'myAnimeList');
      await container
          .read(metadataProviderPreference.notifier)
          .select(MetadataProvider.aniList);
      expect(
        (await container.read(trendingAnimeProvider.future)).first.title,
        'AniList Title',
      );
      expect(
        storage
            .getCachedCategoryList('metadata_myAnimeList_trending')
            ?.first
            .title,
        'MAL Title',
      );
      expect(
        storage.getCachedCategoryList('metadata_aniList_trending')?.first.title,
        'AniList Title',
      );
    },
  );

  test('AniList-only IDs never collide with numeric MAL IDs', () async {
    final special = MockClient((request) async {
      final variables = jsonDecode(request.body)['variables'];
      expect(variables['id'], 1);
      expect(variables['byAni'], true);
      expect(variables['byMal'], false);
      return http.Response(
        jsonEncode({
          'data': {
            'mediaById': media(id: 1, mal: null),
            'mediaByMalId': media(),
          },
        }),
        200,
      );
    });
    final service = AnimeService(
      metadataProvider: MetadataProvider.aniList,
      client: special,
    );
    final anime = await service.getAnimeById('ani:1');
    expect(anime?.id, 'ani:1');
    expect(anime?.malId, isNull);
    expect(anime?.aniListId, '1');
  });

  test(
    'completed AniList titles get all numbered episodes without streaming entries',
    () async {
      final completed = media()
        ..['status'] = 'FINISHED'
        ..['episodes'] = 28
        ..['streamingEpisodes'] = []
        ..['airingSchedule'] = {'nodes': []}
        ..['nextAiringEpisode'] = null;
      final service = AnimeService(
        metadataProvider: MetadataProvider.aniList,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {'mediaByMalId': completed},
            }),
            200,
          ),
        ),
      );
      final episodes = await service.getEpisodesForAnime('1');
      expect(episodes.length, 28);
      expect(episodes.last.episodeNumber, 28);
      expect(episodes.last.animeId, '1');
    },
  );

  test(
    'an unavailable AniList catalog never sends fallback metadata requests to MAL',
    () async {
      final calls = <Uri>[];
      final service = AnimeService(
        metadataProvider: MetadataProvider.aniList,
        client: MockClient((request) async {
          calls.add(request.url);
          return http.Response('{}', 503);
        }),
      );
      await Future.wait([
        service.getTrendingAnime(),
        service.getHotRightNow(),
        service.getEveryonesWatching(),
        service.getRecentlyUpdated(),
        service.getTopPicks(),
        service.getTopMovies(),
        service.getCuratedForYou(),
        service.getRecommended(),
        service.getUpcomingAnime(),
        service.getSchedule(),
      ]);
      expect(calls.isNotEmpty, isTrue);
      expect(calls.every((url) => url.host == 'graphql.anilist.co'), isTrue);
    },
  );

  for (final viewport in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets('complete metadata keyboard navigation at $viewport', (
      tester,
    ) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const DesktopSettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Category-5');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('MyAnimeList'), findsOneWidget);
      expect(find.text('AniList'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Metadata-AniList',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(prefs.getString('metadata_provider'), 'myAnimeList');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Metadata-MyAnimeList',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Metadata-AniList',
      );
      expect(
        tester.getRect(find.text('AniList')).bottom,
        lessThan(viewport.height),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(prefs.getString('metadata_provider'), 'aniList');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Category-5');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'AccountAction');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Metadata-AniList',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
