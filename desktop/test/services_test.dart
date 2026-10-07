import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:aniwings/services/auth_service.dart';
import 'package:aniwings/models/watch_entry.dart';
import 'package:aniwings/models/user.dart';
import 'package:aniwings/models/anime.dart';
import 'package:aniwings/models/episode.dart';
import 'package:aniwings/models/video_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnimeService Tests', () {
    late AnimeService service;

    setUp(() => service = AnimeService());

    test('Zoko encoded player resolves HLS and English subtitles', () {
      final payload = utf8.encode(
        jsonEncode({
          'src': 'https://cdn.example.com/hell-mode/master.m3u8',
          'skip': {
            'intro': {'start': 10, 'end': 100},
          },
          'subtitles': [
            {'src': '/subs/en.vtt', 'lang': 'en', 'label': 'English'},
          ],
        }),
      );
      final key = utf8.encode('otaku-embed-v1');
      final encoded = base64.encode(
        List<int>.generate(
          payload.length,
          (i) => payload[i] ^ key[i % key.length],
        ),
      );
      const pageUrl = 'https://zokoanime.video/stream/mal/60460/1/sub';
      final result = service.parseZokoPlayerPageForTesting(
        '<script>window.__P="$encoded"</script>',
        pageUrl,
      );
      expect(result, isNotNull);
      expect(result!.isEmbed, isFalse);
      expect(
        result.videoUrls.single,
        'https://cdn.example.com/hell-mode/master.m3u8',
      );
      expect(result.subtitleTracks!.single.language, 'en');
      expect(result.subtitleUrl, 'https://zokoanime.video/subs/en.vtt');
      expect(result.headers!['Referer'], pageUrl);
      expect(result.skipTimes.intro?.start, const Duration(seconds: 10));
      expect(result.skipTimes.intro?.end, const Duration(seconds: 100));
    });

    test('Zoko parser rejects malformed payloads and unsafe sources', () {
      const pageUrl = 'https://zokoanime.video/stream/mal/60460/1/sub';
      expect(
        service.parseZokoPlayerPageForTesting('window.__P="broken"', pageUrl),
        isNull,
      );
      final bytes = utf8.encode('{"src":"file:///private/video.mp4"}');
      final key = utf8.encode('otaku-embed-v1');
      final encoded = base64.encode(
        List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length]),
      );
      expect(
        service.parseZokoPlayerPageForTesting('window.__P="$encoded"', pageUrl),
        isNull,
      );
      expect(
        service.parseZokoPlayerPageForTesting(
          'window.__P="$encoded"',
          'https://example.com/',
        ),
        isNull,
      );
    });

    test('getTrendingAnime returns list sorted by rating desc', () async {
      final trending = await service.getTrendingAnime();
      expect(trending.isNotEmpty, true);
      for (int i = 0; i < trending.length - 1; i++) {
        expect(trending[i].rating >= trending[i + 1].rating, true);
      }
    });

    test(
      'queryAnime search matches title or description case-insensitively',
      () async {
        final results = await service.queryAnime(
          query: 'frieren',
          genre: 'All',
          sortBy: 'Trending',
        );
        expect(
          results.any((anime) => anime.title.toLowerCase().contains('frieren')),
          true,
        );
      },
    );

    test('queryAnime genre filter filters correctly', () async {
      final results = await service.queryAnime(
        query: '',
        genre: 'Fantasy',
        sortBy: 'Trending',
      );
      expect(results.every((anime) => anime.genres.contains('Fantasy')), true);
    });

    test('getEpisodesForAnime returns dynamic episode list', () async {
      final episodes = await service.getEpisodesForAnime('52991');
      expect(episodes.length, 28); // Frieren has 28 episodes
      expect(episodes.first.episodeNumber, 1);
      expect(episodes.last.episodeNumber, 28);
    });

    test(
      'anime metadata is returned without a video-availability check',
      () async {
        final anime = Anime(
          id: 'metadata-only',
          malId: '999999',
          title: 'Metadata Only',
          description: 'Returned directly from the metadata cache.',
          posterUrl: 'https://example.com/poster.jpg',
          backdropUrl: 'https://example.com/backdrop.jpg',
          rating: 4.0,
          status: 'Completed',
          genres: const ['Drama'],
          totalEpisodes: 12,
          year: '2024',
        );
        service.addAnimeToMemoryCache(anime);

        expect((await service.getAnimeById(anime.id))?.id, anime.id);
      },
    );

    test('video provider sorting keeps Gojo before Kakashi native', () {
      final providers = service.sortVideoProvidersForTesting([
        VideoProviderSource(
          name: 'Kakashi',
          description: 'Anime Player Native',
          languageType: 'SUB',
          videoUrls: const ['https://example.com/kakashi.m3u8'],
          speedStatus: 'Stable',
        ),
        VideoProviderSource(
          name: 'Gojo',
          description: 'MegaPlay Buzz',
          languageType: 'SUB',
          videoUrls: const ['https://example.com/gojo'],
          speedStatus: 'Stable',
          isEmbed: true,
        ),
        VideoProviderSource(
          name: 'Kakashi',
          description: 'Anime Player Embed',
          languageType: 'SUB',
          videoUrls: const ['https://example.com/kakashi'],
          speedStatus: 'Stable',
          isEmbed: true,
        ),
      ]);

      final subProviders = providers
          .where((provider) => provider.languageType == 'SUB')
          .toList();

      expect(subProviders.map((provider) => provider.name).toList(), [
        'Gojo',
        'Kakashi',
      ]);
      expect(
        subProviders
            .firstWhere((provider) => provider.name == 'Kakashi')
            .isEmbed,
        false,
      );
    });

    test('video provider sorting keeps unavailable-prone Levi last', () {
      final providers = service.sortVideoProvidersForTesting([
        VideoProviderSource(
          name: 'Tanjiro',
          description: 'VidHawk Embed',
          languageType: 'SUB',
          videoUrls: const [
            'https://vidhawk.buzz/embed/mal/1/1/sub?server=zuri',
          ],
          speedStatus: 'Stable',
          isEmbed: true,
        ),
        VideoProviderSource(
          name: 'Levi',
          description: 'VidLink Embed',
          languageType: 'SUB',
          videoUrls: const ['https://vidlink.pro/anime/1/1/sub'],
          speedStatus: 'Stable',
          isEmbed: true,
        ),
        VideoProviderSource(
          name: 'Luffy',
          description: 'ZokoAnime Embed',
          languageType: 'SUB',
          videoUrls: const ['https://zokoanime.video/stream/mal/1/1/sub'],
          speedStatus: 'Stable',
          isEmbed: true,
        ),
        VideoProviderSource(
          name: 'Kakashi',
          description: 'Anime Player Embed',
          languageType: 'SUB',
          videoUrls: const ['https://ani.megaplay.su/mal/1/1/sub'],
          speedStatus: 'Stable',
          isEmbed: true,
        ),
        VideoProviderSource(
          name: 'Gojo',
          description: 'MegaPlay Buzz',
          languageType: 'SUB',
          videoUrls: const [
            'https://megaplay.buzz/stream/mal/1/1/sub?server=gojo',
          ],
          speedStatus: 'Stable',
          isEmbed: true,
        ),
      ]);

      final names = providers.map((p) => p.name).toList();
      expect(names, ['Gojo', 'Kakashi', 'Luffy', 'Tanjiro', 'Levi']);
    });

    test('embed providers use current source-aware anime routes', () {
      final malProviders = service.buildMegaPlayEmbedProvidersForTesting(
        idType: 'mal',
        id: '61169',
        episodeNumber: 1,
      );

      expect(
        malProviders
            .firstWhere((provider) => provider.name == 'Luffy')
            .videoUrls,
        ['https://zokoanime.video/stream/mal/61169/1/sub'],
      );
      expect(
        malProviders
            .firstWhere((provider) => provider.name == 'Tanjiro')
            .videoUrls,
        ['https://vidhawk.buzz/embed/mal/61169/1/sub?server=zuri'],
      );
      expect(
        malProviders
            .firstWhere((provider) => provider.name == 'Levi')
            .speedStatus,
        'Fallback',
      );

      final aniProviders = service.buildMegaPlayEmbedProvidersForTesting(
        idType: 'ani',
        id: '187538',
        episodeNumber: 1,
      );

      expect(
        aniProviders
            .firstWhere((provider) => provider.name == 'Luffy')
            .videoUrls,
        ['https://zokoanime.video/stream/ani/187538/1/sub'],
      );
      expect(
        aniProviders
            .firstWhere((provider) => provider.name == 'Tanjiro')
            .videoUrls,
        ['https://vidhawk.buzz/embed/ani/187538/1/sub?server=zuri'],
      );
      expect(aniProviders.any((provider) => provider.name == 'Levi'), isFalse);
    });

    test(
      'video provider stream yields embeds without waiting for probes',
      () async {
        final anime = Anime(
          id: '61169',
          malId: '61169',
          aniListId: '187538',
          title: 'BLACK TORCH',
          description: 'Performance regression fixture.',
          posterUrl: 'https://example.com/poster.jpg',
          backdropUrl: 'https://example.com/backdrop.jpg',
          rating: 4.0,
          status: 'Releasing',
          genres: const ['Action'],
          totalEpisodes: 9,
          year: '2026',
        );
        service.addAnimeToMemoryCache(anime);

        final providers = await service
            .streamVideoProvidersForEpisode(anime.id, 1)
            .first
            .timeout(const Duration(seconds: 1));

        expect(providers.map((provider) => provider.name), contains('Gojo'));
        expect(providers.map((provider) => provider.name), contains('Luffy'));
        expect(providers.map((provider) => provider.name), contains('Tanjiro'));
      },
    );

    test(
      'VideoProviderSource with subtitleTracks properly carries native subtitle data',
      () {
        final provider = VideoProviderSource(
          name: 'Luffy',
          description: 'ZokoAnime Direct',
          languageType: 'SUB',
          videoUrls: const ['https://zokoanime.video/stream.m3u8'],
          speedStatus: 'Fast',
          isEmbed: false,
          subtitleUrl: 'https://zokoanime.video/subtitles/en.vtt',
          subtitleTracks: const [
            SubtitleTrack(
              label: 'English',
              language: 'en',
              url: 'https://zokoanime.video/subtitles/en.vtt',
            ),
            SubtitleTrack(
              label: 'Spanish',
              language: 'es',
              url: 'https://zokoanime.video/subtitles/es.vtt',
            ),
          ],
        );

        expect(provider.isEmbed, false);
        expect(provider.videoUrls.first, endsWith('.m3u8'));
        expect(provider.subtitleTracks?.length, 2);
        expect(provider.subtitleTracks?.first.language, 'en');
      },
    );
  });

  group('StorageService Tests', () {
    late StorageService storageService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
    });

    test(
      'ignores category data cached by the old availability-gated version',
      () async {
        final oldCacheAnime = Anime(
          id: 'old-category-item',
          title: 'Previously Filtered Item',
          description: 'A valid pre-v2 cache record.',
          posterUrl: 'https://example.com/poster.jpg',
          backdropUrl: 'https://example.com/backdrop.jpg',
          rating: 4.0,
          status: 'Completed',
          genres: const ['Drama'],
          totalEpisodes: 12,
          year: '2024',
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('cached_category_list_trending', [
          jsonEncode(oldCacheAnime.toJson()),
        ]);

        expect(storageService.getCachedCategoryList('trending'), isNull);
      },
    );

    test(
      'episode cache restores playback rows without a network request',
      () async {
        final episodes = [
          Episode(
            id: '61169_ep_1',
            animeId: '61169',
            episodeNumber: 1,
            title: 'The Future Is In Our Hands',
            airDate: DateTime(2026, 7, 4),
            duration: const Duration(minutes: 24),
            videoUrls: const [],
          ),
        ];

        await storageService.saveEpisodesToCache('61169', episodes);
        final restored = storageService.getCachedEpisodes('61169');

        expect(restored, isNotNull);
        expect(restored!.single.title, episodes.single.title);
        expect(restored.single.episodeNumber, 1);
      },
    );

    test('Watchlist toggle adds and removes items', () async {
      final dummyAnime = Anime(
        id: '1',
        title: 'Test Anime',
        description: 'Test Description',
        posterUrl: 'http://test.com/image.jpg',
        backdropUrl: 'http://test.com/banner.jpg',
        rating: 4.5,
        status: 'Finished Airing',
        genres: ['Action'],
        totalEpisodes: 12,
        year: '2022',
        episodeDurationMinutes: 24,
      );

      expect(storageService.isInWatchlist('1'), false);

      await storageService.toggleWatchlist(dummyAnime);
      expect(storageService.isInWatchlist('1'), true);
      expect(storageService.getWatchlist(), ['1']);

      await storageService.toggleWatchlist(dummyAnime);
      expect(storageService.isInWatchlist('1'), false);
    });

    test('Save and retrieve Watch History', () async {
      final entry = WatchEntry(
        id: '1_history',
        userId: 'u1',
        animeId: '1',
        lastWatchedEpisode: 3,
        watchedDuration: const Duration(minutes: 10),
        lastWatchedAt: DateTime.now(),
        isCompleted: false,
      );

      await storageService.saveWatchEntry(entry);
      final fetched = storageService.getWatchEntryForAnime('1');

      expect(fetched, isNotNull);
      expect(fetched!.lastWatchedEpisode, 3);
      expect(fetched.watchedDuration.inMinutes, 10);
    });

    test('Watch history classifies external list statuses for My List', () {
      WatchEntry entryFor(String status) {
        return WatchEntry(
          id: '1_history',
          userId: 'u1',
          animeId: '1',
          lastWatchedEpisode: 0,
          watchedDuration: Duration.zero,
          lastWatchedAt: DateTime.now(),
          isCompleted: false,
          isExternalSync: true,
          externalListStatus: status,
        );
      }

      expect(entryFor('CURRENT').watchlistCategory, WatchlistCategory.watching);
      expect(
        entryFor('PLAN_TO_WATCH').watchlistCategory,
        WatchlistCategory.planToWatch,
      );
      expect(
        entryFor('COMPLETED').watchlistCategory,
        WatchlistCategory.completed,
      );
      expect(entryFor('ON_HOLD').watchlistCategory, WatchlistCategory.onHold);
      expect(entryFor('DROPPED').watchlistCategory, WatchlistCategory.dropped);
    });

    test('Player and subtitle appearance preferences persist', () async {
      await storageService.setAutoPlayNext(false);
      await storageService.setDefaultAudioPreference('DUB');
      await storageService.setSubtitlePreference('Spanish');
      await storageService.setSubtitleSizePreference(22.0);
      await storageService.setSubtitleTextStylePreference('italic');
      await storageService.setSubtitleTextColorValue(0xFFFFEB3B);
      await storageService.setSubtitleBackgroundColorValue(null);
      await storageService.setSubtitleBottomPosition(0.4);
      await storageService.setSubtitleTextShadow(0.8);
      await storageService.setSubtitleBackgroundOpacity(0.5);
      expect(storageService.getVideoDisplayModePreference(), 'fit_16_9');
      await storageService.setVideoDisplayModePreference('zoom');

      expect(storageService.getAutoPlayNext(), false);
      expect(storageService.getDefaultAudioPreference(), 'DUB');
      expect(storageService.getVideoDisplayModePreference(), 'zoom');
      expect(storageService.getSubtitlePreference(), 'Spanish');
      expect(storageService.getSubtitleSizePreference(), 22.0);
      expect(storageService.getSubtitleTextStylePreference(), 'italic');
      expect(storageService.getSubtitleTextColorValue(), 0xFFFFEB3B);
      expect(storageService.getSubtitleBackgroundColorValue(), isNull);
      expect(storageService.getSubtitleBottomPosition(), 0.4);
      expect(storageService.getSubtitleTextShadow(), 0.8);
      expect(storageService.getSubtitleBackgroundOpacity(), 0.5);

      await storageService.resetSubtitleAppearancePreferences();
      expect(storageService.getSubtitlePreference(), 'English');
      expect(storageService.getSubtitleSizePreference(), 14.0);
      expect(storageService.getSubtitleTextStylePreference(), 'normal');
      expect(storageService.getSubtitleBackgroundColorValue(), 0xFF000000);
    });

    test('Server selection preference persists across sessions', () async {
      expect(storageService.getDefaultServerPreference(), 'Gojo');
      await storageService.setDefaultServerPreference('Kakashi');
      expect(storageService.getDefaultServerPreference(), 'Kakashi');
      await storageService.setDefaultServerPreference('Tanjiro');
      expect(storageService.getDefaultServerPreference(), 'Tanjiro');
      await storageService.setDefaultServerPreference('Gojo');
      expect(storageService.getDefaultServerPreference(), 'Gojo');
    });
  });

  group('AuthService Tests', () {
    late AuthService authService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      authService = AuthService(prefs);
    });

    test('Registration and Login flows', () async {
      // 1. Sign Up
      final registerResult = await authService.register(
        'testuser',
        'test@test.com',
        'password123',
      );
      expect(registerResult.user, isNotNull);
      expect(registerResult.user!.username, 'testuser');
      expect(registerResult.errorMessage, isNull);

      // Verify session cached
      final current = authService.getCurrentUser();
      expect(current, isNotNull);
      expect(current!.username, 'testuser');

      // 2. Logout
      await authService.logout();
      expect(authService.getCurrentUser(), isNull);

      // 3. Login
      final loginResult = await authService.login(
        'test@test.com',
        'password123',
      );
      expect(loginResult.user, isNotNull);
      expect(loginResult.user!.username, 'testuser');
      expect(loginResult.errorMessage, isNull);
    });

    test('Login fails for incorrect credentials', () async {
      await authService.register('testuser', 'test@test.com', 'password123');

      final wrongPass = await authService.login(
        'test@test.com',
        'wrongpassword',
      );
      expect(wrongPass.user, isNull);
      expect(wrongPass.errorMessage, contains('Invalid email or password'));

      final nonExistent = await authService.login(
        'no@account.com',
        'password123',
      );
      expect(nonExistent.user, isNull);
      expect(nonExistent.errorMessage, contains('Invalid email or password'));
    });

    test('Google Sign-in simulation flow', () async {
      // 1. Google Sign in for new user
      final loginResult = await authService.loginWithGoogle(
        'google@test.com',
        'Google User',
      );
      expect(loginResult.user, isNotNull);
      final loggedInUser = loginResult.user!;
      expect(loggedInUser.username, 'Google User');
      expect(loggedInUser.authProvider, 'google');
      expect(loginResult.errorMessage, isNull);

      // Verify session cached
      final current = authService.getCurrentUser();
      expect(current, isNotNull);
      final currentUser = current!;
      expect(currentUser.authProvider, 'google');
      expect(currentUser.username, 'Google User');

      // 2. Logout
      await authService.logout();
      expect(authService.getCurrentUser(), isNull);

      // 3. Google Sign in for existing user should retain profile/provider
      final secondLogin = await authService.loginWithGoogle(
        'google@test.com',
        'Google User Updated',
      );
      expect(secondLogin.user, isNotNull);
      final secondUser = secondLogin.user!;
      expect(secondUser.username, 'Google User');
      expect(secondUser.authProvider, 'google');
    });

    test('Update user profile updates local DB and cached session', () async {
      final registerResult = await authService.register(
        'oldusername',
        'profile@test.com',
        'password123',
      );
      expect(registerResult.user, isNotNull);

      final updatedUser = User(
        id: registerResult.user!.id,
        email: registerResult.user!.email,
        username: registerResult.user!.username,
        avatarUrl: 'https://api.dicebear.com/7.x/adventurer/png?seed=NewSeed',
        createdAt: registerResult.user!.createdAt,
        totalHoursWatched: 10,
        favoriteGenre: 'Fantasy',
        authProvider: registerResult.user!.authProvider,
      );

      await authService.updateUser(updatedUser);

      final current = authService.getCurrentUser();
      expect(current, isNotNull);
      final currentUser = current!;
      // getCurrentUser migrates external dicebear avatar URLs to a local asset
      // (intentional behavior that avoids third-party avatar URLs).
      expect(
        currentUser.avatarUrl,
        'assets/images/avatars/jujutsukaisen_gojo.png',
      );
      expect(currentUser.totalHoursWatched, 10);
      expect(currentUser.favoriteGenre, 'Fantasy');
    });
  });
}
