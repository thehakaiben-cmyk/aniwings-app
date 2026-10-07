import 'dart:convert';

import 'package:aniwings/models/anime.dart';
import 'package:aniwings/models/watch_entry.dart';
import 'package:aniwings/services/list_sync_service.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> createStorage() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  group('ListSyncService', () {
    Anime testAnime({
      String id = '52991',
      String title = 'Frieren: Beyond Journey\'s End',
      int totalEpisodes = 28,
    }) {
      return Anime(
        id: id,
        title: title,
        description: 'Test anime',
        posterUrl: 'https://example.test/poster.jpg',
        backdropUrl: 'https://example.test/backdrop.jpg',
        rating: 4.8,
        status: 'Completed',
        genres: const ['Fantasy'],
        totalEpisodes: totalEpisodes,
        year: '2023',
      );
    }

    WatchEntry completedEntry({String animeId = '52991', int episode = 28}) {
      return WatchEntry(
        id: '${animeId}_history',
        userId: 'u1',
        animeId: animeId,
        lastWatchedEpisode: episode,
        watchedDuration: const Duration(minutes: 24),
        lastWatchedAt: DateTime(2026, 8, 27),
        isCompleted: true,
      );
    }

    ExternalListConnection connection(
      ExternalListProvider provider, {
      String username = 'viewer',
    }) {
      return ExternalListConnection(
        provider: provider,
        username: username,
        accessToken: '${provider.key}-access',
        refreshToken: null,
        expiresAt: null,
        connectedAt: DateTime(2026, 8, 27),
      );
    }

    test(
      'imports AniList rows into watchlist and sync progress metadata',
      () async {
        final storage = await createStorage();
        final service = ListSyncService(
          storage: storage,
          client: MockClient((request) async {
            expect(request.method, 'POST');

            return http.Response(
              jsonEncode({
                'data': {
                  'MediaListCollection': {
                    'lists': [
                      {
                        'status': 'COMPLETED',
                        'entries': [
                          {
                            'status': 'COMPLETED',
                            'progress': 220,
                            'updatedAt': 1700000000,
                            'media': {
                              'id': 20,
                              'idMal': 20,
                              'episodes': 220,
                              'coverImage': {
                                'large': 'https://example.test/naruto.jpg',
                              },
                              'averageScore': 82,
                              'status': 'FINISHED',
                              'genres': ['Action'],
                              'seasonYear': 2002,
                              'title': {
                                'english': 'Naruto',
                                'romaji': 'NARUTO',
                                'userPreferred': 'NARUTO',
                              },
                            },
                          },
                          {
                            'status': 'PLANNING',
                            'progress': 0,
                            'updatedAt': 1700000001,
                            'media': {
                              'id': 30,
                              'idMal': 30,
                              'episodes': 26,
                              'status': 'FINISHED',
                              'title': {'english': 'Planning Only'},
                            },
                          },
                        ],
                      },
                    ],
                  },
                },
              }),
              200,
            );
          }),
        );
        addTearDown(service.dispose);

        final result = await service.importWatchProgress(
          provider: ExternalListProvider.aniList,
          username: 'shinji',
          userId: 'u1',
        );

        expect(result.scannedCount, 2);
        expect(result.importedCount, 2);
        expect(result.skippedCount, 0);

        final watchlist = storage.getWatchlistAnime();
        expect(watchlist.map((anime) => anime.id), containsAll(['20', '30']));
        expect(
          watchlist.firstWhere((anime) => anime.id == '20').posterUrl,
          'https://example.test/naruto.jpg',
        );

        final entry = storage.getWatchEntryForAnime('20', userId: 'u1');
        expect(entry, isNotNull);
        expect(entry!.lastWatchedEpisode, 220);
        expect(entry.isCompleted, true);
        expect(entry.isExternalSync, true);
        expect(entry.externalListStatus, 'COMPLETED');
        expect(entry.lastWatchedAt.millisecondsSinceEpoch, 1700000000000);
        final planning = storage.getWatchEntryForAnime('30', userId: 'u1');
        expect(planning, isNotNull);
        expect(planning!.externalListStatus, 'PLANNING');
        expect(planning.watchlistCategory, WatchlistCategory.planToWatch);
      },
    );

    test(
      'imports dropped AniList entries into the Dropped list category',
      () async {
        final storage = await createStorage();
        final service = ListSyncService(
          storage: storage,
          client: MockClient((_) async {
            return http.Response(
              jsonEncode({
                'data': {
                  'MediaListCollection': {
                    'lists': [
                      {
                        'status': 'DROPPED',
                        'entries': [
                          {
                            'status': 'DROPPED',
                            'progress': 4,
                            'updatedAt': 1700000000,
                            'media': {
                              'id': 999,
                              'idMal': 999,
                              'episodes': 12,
                              'title': {'english': 'Dropped Title'},
                            },
                          },
                        ],
                      },
                    ],
                  },
                },
              }),
              200,
            );
          }),
        );
        addTearDown(service.dispose);

        await service.importWatchProgress(
          provider: ExternalListProvider.aniList,
          username: 'shinji',
          userId: 'u1',
        );

        expect(storage.isInWatchlist('999'), true);
        expect(
          storage.getWatchEntryForAnime('999', userId: 'u1')!.watchlistCategory,
          WatchlistCategory.dropped,
        );
      },
    );

    test(
      'preserves newer local progress while applying AniList paused status',
      () async {
        final storage = await createStorage();
        await storage.saveWatchEntry(
          WatchEntry(
            id: '1_history',
            userId: 'u1',
            animeId: '1',
            lastWatchedEpisode: 10,
            watchedDuration: Duration.zero,
            lastWatchedAt: DateTime(2026, 1, 1),
            isCompleted: false,
          ),
        );

        final service = ListSyncService(
          storage: storage,
          client: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'data': {
                  'MediaListCollection': {
                    'lists': [
                      {
                        'status': 'PAUSED',
                        'entries': [
                          {
                            'status': 'PAUSED',
                            'progress': 3,
                            'updatedAt': 1893456000,
                            'media': {
                              'id': 1,
                              'idMal': 1,
                              'episodes': 26,
                              'title': {'english': 'Cowboy Bebop'},
                            },
                          },
                        ],
                      },
                    ],
                  },
                },
              }),
              200,
            );
          }),
        );
        addTearDown(service.dispose);

        final result = await service.importWatchProgress(
          provider: ExternalListProvider.aniList,
          username: 'local-first',
          userId: 'u1',
        );

        expect(result.importedCount, 1);

        final entry = storage.getWatchEntryForAnime('1', userId: 'u1');
        expect(entry!.lastWatchedEpisode, 10);
        expect(entry.externalListStatus, 'PAUSED');
        expect(entry.watchlistCategory, WatchlistCategory.onHold);
      },
    );

    test('imports MyAnimeList progress from Jikan-shaped data', () async {
      final storage = await createStorage();
      final service = ListSyncService(
        storage: storage,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/v4/users/someone/animelist');

          return http.Response(
            jsonEncode({
              'data': [
                {
                  'mal_id': 16498,
                  'title': 'Attack on Titan',
                  'episodes': 25,
                  'watched_episodes': 25,
                  'status': 'completed',
                  'updated_at': '2024-02-01T00:00:00Z',
                },
                {
                  'anime': {
                    'mal_id': 38000,
                    'title': 'Demon Slayer: Kimetsu no Yaiba',
                    'episodes': 26,
                  },
                  'watching_status': 1,
                  'watched_episodes': 14,
                },
              ],
              'pagination': {'has_next_page': false},
            }),
            200,
          );
        }),
      );
      addTearDown(service.dispose);

      final result = await service.importWatchProgress(
        provider: ExternalListProvider.myAnimeList,
        username: 'someone',
        userId: 'u1',
      );

      expect(result.importedCount, 2);
      expect(storage.getWatchlist(), containsAll(['16498', '38000']));

      final completed = storage.getWatchEntryForAnime('16498', userId: 'u1');
      expect(completed, isNotNull);
      expect(completed!.isCompleted, true);
      expect(completed.isExternalSync, true);

      final watching = storage.getWatchEntryForAnime('38000', userId: 'u1');
      expect(watching, isNotNull);
      expect(watching!.lastWatchedEpisode, 14);
      expect(watching.isCompleted, false);
    });

    test(
      'imports string-coded MyAnimeList on-hold entries correctly',
      () async {
        final storage = await createStorage();
        final service = ListSyncService(
          storage: storage,
          client: MockClient((_) async {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'mal_id': 12345,
                    'title': 'Paused Title',
                    'episodes': 24,
                    'watched_episodes': 9,
                    'status': '3',
                    'updated_at': '2026-08-27T00:00:00Z',
                  },
                ],
                'pagination': {'has_next_page': false},
              }),
              200,
            );
          }),
        );
        addTearDown(service.dispose);

        await service.importWatchProgress(
          provider: ExternalListProvider.myAnimeList,
          username: 'someone',
          userId: 'u1',
        );

        final entry = storage.getWatchEntryForAnime('12345', userId: 'u1');
        expect(entry, isNotNull);
        expect(entry!.externalListStatus, 'ON_HOLD');
        expect(entry.watchlistCategory, WatchlistCategory.onHold);
      },
    );

    test('retries MyAnimeList code exchange without redirect URI', () async {
      final storage = await createStorage();
      await storage.saveExternalListPendingAuthorization(
        ExternalListPendingAuthorization(
          provider: ExternalListProvider.myAnimeList,
          state: 'state-1',
          codeVerifier: 'verifier-1',
          responseMode: ExternalListAuthResponseMode.code,
          startedAt: DateTime(2026, 1, 1),
        ),
      );
      var tokenAttempts = 0;

      final service = ListSyncService(
        storage: storage,
        client: MockClient((request) async {
          if (request.url.host == 'myanimelist.net' &&
              request.url.path == '/v1/oauth2/token') {
            tokenAttempts++;
            expect(request.method, 'POST');
            expect(request.body, contains('code=code-1'));
            expect(request.body, contains('code_verifier=verifier-1'));

            if (tokenAttempts == 1) {
              expect(request.body, contains('redirect_uri='));
              return http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
            }

            expect(request.body, isNot(contains('redirect_uri=')));
            return http.Response(
              jsonEncode({
                'access_token': 'access-1',
                'refresh_token': 'refresh-1',
                'expires_in': 2678400,
              }),
              200,
            );
          }

          if (request.url.host == 'api.myanimelist.net' &&
              request.url.path == '/v2/users/@me') {
            expect(request.headers['Authorization'], 'Bearer access-1');
            return http.Response(jsonEncode({'name': 'HakaiBen'}), 200);
          }

          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );
      addTearDown(service.dispose);

      final connection = await service.completeAuthorization(
        provider: ExternalListProvider.myAnimeList,
        callbackOrCode: 'aniwings://oauth/mal?code=code-1&state=state-1',
      );

      expect(tokenAttempts, 2);
      expect(connection.username, 'HakaiBen');
      expect(connection.accessToken, 'access-1');
      expect(
        storage.getExternalListConnection(ExternalListProvider.myAnimeList),
        isNotNull,
      );
      expect(
        storage.getExternalListPendingAuthorization(
          ExternalListProvider.myAnimeList,
        ),
        isNull,
      );
    });

    test(
      'starts AniList authorization with the implicit token grant',
      () async {
        final storage = await createStorage();
        final service = ListSyncService(
          storage: storage,
          client: MockClient((_) async {
            fail('No HTTP request should be made.');
          }),
        );
        addTearDown(service.dispose);

        final start = await service.beginAuthorization(
          ExternalListProvider.aniList,
        );

        expect(start.responseMode, ExternalListAuthResponseMode.token);
        expect(
          start.authorizationUri.toString(),
          contains('https://anilist.co/api/v2/oauth/authorize'),
        );
        expect(
          start.authorizationUri.queryParameters['response_type'],
          'token',
        );
        expect(start.authorizationUri.queryParameters['redirect_uri'], isNull);
        expect(
          storage.getExternalListPendingAuthorization(
            ExternalListProvider.aniList,
          ),
          isNotNull,
        );
      },
    );

    test('completes AniList authorization from raw pin-page token', () async {
      final storage = await createStorage();
      await storage.saveExternalListPendingAuthorization(
        ExternalListPendingAuthorization(
          provider: ExternalListProvider.aniList,
          state: 'state-1',
          codeVerifier: null,
          responseMode: ExternalListAuthResponseMode.token,
          startedAt: DateTime(2026, 1, 1),
        ),
      );

      final service = ListSyncService(
        storage: storage,
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.toString(), 'https://graphql.anilist.co');
          expect(request.headers['Authorization'], 'Bearer raw-token-1');

          return http.Response(
            jsonEncode({
              'data': {
                'Viewer': {'name': 'AniUser'},
              },
            }),
            200,
          );
        }),
      );
      addTearDown(service.dispose);

      final connection = await service.completeAuthorization(
        provider: ExternalListProvider.aniList,
        callbackOrCode: 'access_token=raw-token-1',
      );

      expect(connection.provider, ExternalListProvider.aniList);
      expect(connection.username, 'AniUser');
      expect(connection.accessToken, 'raw-token-1');
      expect(
        storage.getExternalListConnection(ExternalListProvider.aniList),
        isNotNull,
      );
    });

    test(
      'completes AniList authorization from the automatic PIN redirect',
      () async {
        final storage = await createStorage();
        await storage.saveExternalListPendingAuthorization(
          ExternalListPendingAuthorization(
            provider: ExternalListProvider.aniList,
            state: 'state-1',
            codeVerifier: null,
            responseMode: ExternalListAuthResponseMode.token,
            startedAt: DateTime(2026, 1, 1),
          ),
        );

        final service = ListSyncService(
          storage: storage,
          client: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer automatic-token');
            return http.Response(
              jsonEncode({
                'data': {
                  'Viewer': {'name': 'AniUser'},
                },
              }),
              200,
            );
          }),
        );
        addTearDown(service.dispose);

        final connection = await service.completeAuthorization(
          provider: ExternalListProvider.aniList,
          callbackOrCode:
              'https://anilist.co/api/v2/oauth/pin#access_token=automatic-token&state=state-1',
        );

        expect(connection.username, 'AniUser');
        expect(connection.accessToken, 'automatic-token');
      },
    );

    test('reports an AniList authorization denial clearly', () async {
      final storage = await createStorage();
      await storage.saveExternalListPendingAuthorization(
        ExternalListPendingAuthorization(
          provider: ExternalListProvider.aniList,
          state: 'state-1',
          codeVerifier: null,
          responseMode: ExternalListAuthResponseMode.token,
          startedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = ListSyncService(
        storage: storage,
        client: MockClient((_) async {
          fail('A rejected authorization must not call the API.');
        }),
      );
      addTearDown(service.dispose);

      expect(
        service.completeAuthorization(
          provider: ExternalListProvider.aniList,
          callbackOrCode:
              'https://anilist.co/api/v2/oauth/pin#error=access_denied&error_description=Login%20cancelled&state=state-1',
        ),
        throwsA(
          isA<ExternalListSyncException>().having(
            (error) => error.message,
            'message',
            'Login cancelled',
          ),
        ),
      );
    });

    test('treats an empty AniList list as an in-sync account', () async {
      final storage = await createStorage();
      final service = ListSyncService(
        storage: storage,
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'data': {
                'MediaListCollection': {'lists': []},
              },
            }),
            200,
          );
        }),
      );
      addTearDown(service.dispose);

      final result = await service.importWatchProgress(
        provider: ExternalListProvider.aniList,
        username: 'new-user',
        userId: 'u1',
      );

      expect(result.scannedCount, 0);
      expect(result.importedCount, 0);
      expect(result.unchangedCount, 0);
    });

    test('keeps only one active external list connection', () async {
      final storage = await createStorage();
      await storage.saveExternalListConnection(
        connection(ExternalListProvider.myAnimeList, username: 'mal-user'),
      );
      await storage.saveExternalListConnection(
        connection(ExternalListProvider.aniList, username: 'ani-user'),
      );

      expect(
        storage.getActiveExternalListProvider(),
        ExternalListProvider.aniList,
      );
      expect(
        storage.getExternalListConnection(ExternalListProvider.aniList),
        isNotNull,
      );
      expect(
        storage.getExternalListConnection(ExternalListProvider.myAnimeList),
        isNull,
      );
      expect(storage.getExternalListConnections().keys, [
        ExternalListProvider.aniList,
      ]);
    });

    test('blocks starting a second external list provider', () async {
      final storage = await createStorage();
      await storage.saveExternalListConnection(
        connection(ExternalListProvider.myAnimeList),
      );

      final service = ListSyncService(
        storage: storage,
        client: MockClient((_) async {
          fail('No HTTP request should be made.');
        }),
      );
      addTearDown(service.dispose);

      expect(
        service.beginAuthorization(ExternalListProvider.aniList),
        throwsA(isA<ExternalListSyncException>()),
      );
    });

    test('cancels a pending MyAnimeList authorization', () async {
      final storage = await createStorage();
      final service = ListSyncService(storage: storage);
      addTearDown(service.dispose);

      await service.beginAuthorization(ExternalListProvider.myAnimeList);
      expect(
        storage.getExternalListPendingAuthorization(
          ExternalListProvider.myAnimeList,
        ),
        isNotNull,
      );

      await service.cancelAuthorization(ExternalListProvider.myAnimeList);

      expect(
        storage.getExternalListPendingAuthorization(
          ExternalListProvider.myAnimeList,
        ),
        isNull,
      );
    });

    test(
      'pushes completed episode progress to active AniList connection',
      () async {
        final storage = await createStorage();
        await storage.saveExternalListConnection(
          connection(ExternalListProvider.aniList, username: 'ani-user'),
        );
        var lookupCount = 0;
        var mutationCount = 0;

        final service = ListSyncService(
          storage: storage,
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.toString(), 'https://graphql.anilist.co');

            final decoded = jsonDecode(request.body) as Map<String, dynamic>;
            final query = decoded['query'] as String;
            final variables = decoded['variables'] as Map<String, dynamic>;

            if (query.contains('Media(idMal:')) {
              lookupCount++;
              expect(variables['id'], 52991);
              return http.Response(
                jsonEncode({
                  'data': {
                    'Media': {'id': 154587, 'idMal': 52991},
                  },
                }),
                200,
              );
            }

            if (query.contains('SaveMediaListEntry')) {
              mutationCount++;
              expect(request.headers['Authorization'], 'Bearer anilist-access');
              expect(variables['mediaId'], 154587);
              expect(variables['status'], 'COMPLETED');
              expect(variables['progress'], 28);
              return http.Response(
                jsonEncode({
                  'data': {
                    'SaveMediaListEntry': {
                      'id': 1,
                      'status': 'COMPLETED',
                      'progress': 28,
                    },
                  },
                }),
                200,
              );
            }

            fail('Unexpected AniList request: ${request.body}');
          }),
        );
        addTearDown(service.dispose);

        final result = await service.syncCompletedWatchProgress(
          anime: testAnime(),
          entry: completedEntry(),
        );

        expect(result, isNotNull);
        expect(result!.provider, ExternalListProvider.aniList);
        expect(result.progress, 28);
        expect(result.isCompleted, true);
        expect(lookupCount, 1);
        expect(mutationCount, 1);
      },
    );

    test(
      'pushes completed episode progress to active MyAnimeList connection',
      () async {
        final storage = await createStorage();
        await storage.saveExternalListConnection(
          connection(ExternalListProvider.myAnimeList, username: 'mal-user'),
        );
        var patchCount = 0;

        final service = ListSyncService(
          storage: storage,
          client: MockClient((request) async {
            if (request.url.toString() == 'https://graphql.anilist.co') {
              return http.Response(
                jsonEncode({
                  'data': {
                    'Media': {'id': 16498, 'idMal': 16498},
                  },
                }),
                200,
              );
            }

            expect(request.method, 'PATCH');
            expect(
              request.url.toString(),
              'https://api.myanimelist.net/v2/anime/16498/my_list_status',
            );
            expect(
              request.headers['Authorization'],
              'Bearer myanimelist-access',
            );
            final fields = Uri.splitQueryString(request.body);
            expect(fields['status'], 'completed');
            expect(fields['num_watched_episodes'], '25');
            expect(fields['finish_date'], '2026-08-27');
            patchCount++;

            return http.Response(
              jsonEncode({'status': 'completed', 'num_episodes_watched': 25}),
              200,
            );
          }),
        );
        addTearDown(service.dispose);

        final result = await service.syncCompletedWatchProgress(
          anime: testAnime(
            id: '16498',
            title: 'Attack on Titan',
            totalEpisodes: 25,
          ),
          entry: completedEntry(animeId: '16498', episode: 25),
        );

        expect(result, isNotNull);
        expect(result!.provider, ExternalListProvider.myAnimeList);
        expect(result.progress, 25);
        expect(result.isCompleted, true);
        expect(patchCount, 1);
      },
    );
  });
}
