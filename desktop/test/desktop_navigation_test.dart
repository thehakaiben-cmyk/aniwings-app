import 'package:aniwings/core/focus/desktop_focus_manager.dart';
import 'package:aniwings/core/focus/desktop_navigation_controller.dart';
import 'package:aniwings/core/focus/desktop_focus_node_registry.dart';
import 'package:aniwings/core/services/device_service.dart';
import 'package:aniwings/core/theme/app_theme.dart';
import 'package:aniwings/features/account/player_settings_screen.dart';
import 'package:aniwings/features/account/profile_screen.dart';
import 'package:aniwings/features/home/home_screen.dart';
import 'package:aniwings/features/search/search_screen.dart';
import 'package:aniwings/features/watch/watch_screen.dart';
import 'package:aniwings/models/anime.dart';
import 'package:aniwings/models/episode.dart';
import 'package:aniwings/models/episode_skip_times.dart';
import 'package:aniwings/models/video_provider.dart';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:aniwings/widgets/anime_card.dart';
import 'package:aniwings/widgets/custom_video_player.dart';
import 'package:aniwings/widgets/desktop_focus_wrapper.dart';
import 'package:aniwings/widgets/desktop_page_shell.dart';
import 'package:aniwings/widgets/desktop_side_nav.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SearchFixtureService extends AnimeService {
  @override
  Future<List<Anime>> queryAnime({
    required String query,
    required String genre,
    required String sortBy,
  }) async {
    return [
      Anime(
        id: 'search-one',
        title: 'Search Result One',
        description: 'A search result fixture.',
        posterUrl: 'https://example.com/poster.jpg',
        backdropUrl: 'https://example.com/backdrop.jpg',
        rating: 8.4,
        status: 'Completed',
        genres: const ['Action'],
        totalEpisodes: 12,
        year: '2026',
      ),
    ];
  }
}

Anime _fixtureAnime({
  String id = 'fixture-anime',
  String title = 'Fixture Anime',
  int totalEpisodes = 12,
}) {
  return Anime(
    id: id,
    title: title,
    description: 'A remote-navigation anime fixture.',
    posterUrl: 'https://example.com/poster.jpg',
    backdropUrl: 'https://example.com/backdrop.jpg',
    rating: 8.6,
    status: 'Completed',
    genres: const ['Action', 'Adventure'],
    totalEpisodes: totalEpisodes,
    year: '2026',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DesktopFocusManager.instance.reset();
  });

  testWidgets(
    'shared desktop actions activate once with the remote select key',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopFocusWrapper(
              debugLabel: 'Test TV action',
              autofocus: true,
              onTap: () => activations++,
              child: const SizedBox(width: 120, height: 60),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Test TV action');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(activations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('side navigation hands Right focus to the search field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final searchFocusNode = FocusNode(debugLabel: 'Search field');
    addTearDown(searchFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: DesktopSideNav(
            currentIndex: 2,
            child: Focus(
              focusNode: searchFocusNode,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('Search'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(searchFocusNode.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('Search'));
    expect(searchFocusNode.hasPrimaryFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('side navigation moves and activates with a D-pad', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: DesktopSideNav(
            currentIndex: 0,
            onDestinationSelected: (index) => selectedIndex = index,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('Discover'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selectedIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home page hands D-pad focus between navbar and search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final anime = _fixtureAnime(title: 'Home Hero Fixture');
    int? selectedIndex;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          trendingAnimeProvider.overrideWith((ref) async => [anime]),
          hotRightNowProvider.overrideWith((ref) async => const <Anime>[]),
          upcomingAnimeProvider.overrideWith((ref) async => const <Anime>[]),
          everyonesWatchingProvider.overrideWith(
            (ref) async => const <Anime>[],
          ),
          recentlyUpdatedProvider.overrideWith((ref) async => const <Anime>[]),
          topPicksProvider.overrideWith((ref) async => const <Anime>[]),
          topMoviesProvider.overrideWith((ref) async => const <Anime>[]),
          curatedForYouProvider.overrideWith((ref) async => const <Anime>[]),
          recommendedProvider.overrideWith((ref) async => const <Anime>[]),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DesktopSideNav(
              currentIndex: 0,
              onDestinationSelected: (index) => selectedIndex = index,
              child: const HomeScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('Home'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 100));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Home Hero Slider');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('DesktopSideNav Home'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('DesktopSideNav Search'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selectedIndex, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nav bar opens on Home focus and hover expands rail without selecting browser',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      final testAnime = Anime(
        id: 'test-1',
        title: 'Test Anime',
        description: 'A test anime description',
        posterUrl: 'https://example.com/poster-one.jpg',
        backdropUrl: 'https://example.com/backdrop-one.jpg',
        rating: 8.5,
        status: 'Ongoing',
        genres: const ['Action'],
        totalEpisodes: 12,
        year: '2024',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            trendingAnimeProvider.overrideWith((ref) async => [testAnime]),
            hotRightNowProvider.overrideWith((ref) async => [testAnime]),
            upcomingAnimeProvider.overrideWith((ref) async => const <Anime>[]),
            everyonesWatchingProvider.overrideWith(
              (ref) async => const <Anime>[],
            ),
            recentlyUpdatedProvider.overrideWith(
              (ref) async => const <Anime>[],
            ),
            topPicksProvider.overrideWith((ref) async => const <Anime>[]),
            topMoviesProvider.overrideWith((ref) async => const <Anime>[]),
            curatedForYouProvider.overrideWith((ref) async => const <Anime>[]),
            recommendedProvider.overrideWith((ref) async => const <Anime>[]),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: DesktopSideNav(
                currentIndex: 0,
                onDestinationSelected: (_) {},
                child: const HomeScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Nav starts on Home
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('DesktopSideNav Home'),
      );

      // Move to content
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Home Hero Slider',
      );

      // Move through the hero actions into the first category row.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 100));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Hero Watch Now');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('Hot Right Now Row'),
      );

      // Move Left from category row to open nav bar: MUST select Home, NEVER Browse
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('DesktopSideNav Home'),
      );
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot(contains('Browse')),
      );

      // Mouse hover over the nav rail expands it
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      // Hover over nav rail at (35, 300)
      await gesture.moveTo(const Offset(35, 300));
      await tester.pump(const Duration(milliseconds: 300));

      // The desktop nav rail maintains persistent 224.0 width
      final railFinder = find.byKey(const ValueKey('desktop-nav-rail'));
      final animatedContainer = tester.widget<AnimatedContainer>(
        railFinder.first,
      );
      expect(animatedContainer.constraints?.maxWidth ?? 224.0, 224.0);
    },
  );

  testWidgets('Backspace stays in search and scrolling survives text edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var backCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          searchAnimeProvider.overrideWith(
            (ref) async => List.generate(
              40,
              (i) => _fixtureAnime(id: 'result-$i', title: 'Result $i'),
            ),
          ),
        ],
        child: MaterialApp(
          home: DesktopPageShell(
            onRootBack: () => backCount++,
            child: const SearchScreen(),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'anime');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(DesktopNavigationController.isTextInputActive(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(backCount, 0);
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    final offset = scrollView.controller!.offset;
    expect(offset, greaterThan(0));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(CustomScrollView)),
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pumpAndSettle();
    final wheelOffset = scrollView.controller!.offset;
    expect(wheelOffset, greaterThan(offset));
    await tester.enterText(find.byType(TextField), 'anime edited');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(scrollView.controller!.offset, closeTo(wheelOffset, 1));
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar).first);
    expect(scrollbar.controller, same(scrollView.controller));
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed sidebar centers brand and destination icons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopSideNav(currentIndex: 0, child: Text('Content')),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();
    final rail = find.byKey(const ValueKey('desktop-nav-rail'));
    final center = tester.getCenter(rail).dx;
    expect(tester.getSize(rail).width, 64);
    final brand = find.descendant(of: rail, matching: find.byType(Image));
    expect(tester.getCenter(brand).dx, closeTo(center, 0.5));
    for (final icon in [
      Icons.home_rounded,
      Icons.search_rounded,
      Icons.settings_outlined,
      Icons.person_outline_rounded,
      Icons.chevron_right_rounded,
      Icons.system_update_rounded,
    ]) {
      expect(tester.getCenter(find.byIcon(icon)).dx, closeTo(center, 0.5));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Expand sidebar'));
    await tester.pumpAndSettle();
    expect(tester.getSize(rail).width, 224);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search results render as desktop poster cards with filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          animeServiceProvider.overrideWithValue(_SearchFixtureService()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const SearchScreen(),
        ),
      ),
    );

    await tester.pump();
    expect(find.byKey(const ValueKey('search-landing')), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Ctrl + K to focus'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'search');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.byKey(const ValueKey('search-results-grid')), findsOneWidget);
    expect(find.text('Search Result One'), findsOneWidget);
    expect(find.text('8.4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home has one focused action and moves through offscreen and empty rows',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final cards = List.generate(
        12,
        (i) => _fixtureAnime(id: 'card-$i', title: 'Card $i'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            trendingAnimeProvider.overrideWith((ref) async => cards),
            hotRightNowProvider.overrideWith((ref) async => cards),
            recentlyUpdatedProvider.overrideWith((ref) async => cards),
            upcomingAnimeProvider.overrideWith((ref) async => const <Anime>[]),
            everyonesWatchingProvider.overrideWith(
              (ref) async => const <Anime>[],
            ),
            topPicksProvider.overrideWith((ref) async => const <Anime>[]),
            topMoviesProvider.overrideWith((ref) async => const <Anime>[]),
            curatedForYouProvider.overrideWith((ref) async => cards),
            recommendedProvider.overrideWith((ref) async => cards),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final registry = DesktopFocusNodeRegistry.instance;
      registry.getNode('hero_watch_now')!.requestFocus();
      await tester.pump();
      final hero = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('home-hero-frame')),
      );
      expect(
        (hero.decoration! as BoxDecoration).border!.top.color,
        isNot(Colors.white),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.focused == true &&
              widget.properties.button == true,
        ),
        findsOneWidget,
      );
      registry.getNode('hero_watchlist')!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DesktopFocusWrapper &&
              widget.registryKey == 'hero_watchlist',
        ),
        findsOneWidget,
      );
      expect(
        FocusManager.instance.primaryFocus,
        registry.getNode('hero_watchlist'),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.focused == true &&
              widget.properties.button == true,
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        FocusManager.instance.primaryFocus,
        registry.getNode('home_row_trending_0'),
      );
      for (var i = 0; i < 9; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 140));
      }
      expect(
        FocusManager.instance.primaryFocus,
        registry.getNode('home_row_trending_9'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        FocusManager.instance.primaryFocus,
        registry.getNode('home_row_recently_updated_9'),
      );
      final focusBox =
          FocusManager.instance.primaryFocus!.context!.findRenderObject()
              as RenderBox;
      final top = focusBox.localToGlobal(Offset.zero).dy;
      expect(top, greaterThanOrEqualTo(0));
      expect(top + focusBox.size.height, lessThanOrEqualTo(540));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        FocusManager.instance.primaryFocus,
        registry.getNode('home_row_recommended_9'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        FocusManager.instance.primaryFocus,
        registry.getNode('home_row_recently_updated_9'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('guest account page only exposes mobile profile connection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Mobile QR Connect'), findsNothing);
    expect(find.text('Player Settings'), findsNothing);
    expect(find.text('Subtitle Settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player settings include a workable update-json section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const PlayerSettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('player-update-settings')),
      findsOneWidget,
    );
    expect(find.text('Application Updates'), findsOneWidget);
    expect(find.text('Check for Updates'), findsOneWidget);
    expect(find.text('Streaming Server'), findsOneWidget);
    expect(find.text('Gojo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'watch route opens fullscreen and Back reveals the desktop controls',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final anime = Anime(
        id: 'tv-watch-test',
        title: 'TV Watch Test',
        description: 'A playback layout fixture.',
        posterUrl: '',
        backdropUrl: '',
        rating: 8,
        status: 'Current',
        genres: const ['Action'],
        totalEpisodes: 1,
        year: '2026',
      );
      final episode = Episode(
        id: 'tv-watch-test_ep_1',
        animeId: anime.id,
        episodeNumber: 1,
        title: 'Pilot',
        airDate: DateTime(2026),
        duration: const Duration(minutes: 24),
        videoUrls: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            animeDetailsProvider.overrideWith((ref, id) => anime),
            animeEpisodesProvider.overrideWith((ref, id) => [episode]),
            videoProvidersProvider.overrideWith(
              (ref, params) => Stream.value(
                const <VideoProviderSource>[],
              ).asBroadcastStream(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: WatchScreen(
                animeId: 'fixture-anime',
                episodeId: 'fixture-anime_ep_1',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('No SUB stream available'), findsOneWidget);
      expect(find.text('Open episodes'), findsOneWidget);
      expect(find.text('Switch server'), findsOneWidget);
      expect(find.text('SUB'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Back');
      await tester.tap(find.text('Open episodes'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Episodes'), findsOneWidget);
      expect(find.text('Pilot'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Episodes'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline video uses a file source and local subtitles', (
    tester,
  ) async {
    final directory = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'aniwings-offline-test-',
      );
      await File(
        '${directory.path}/episode.mp4',
      ).writeAsBytes([0, 0, 0, 24, ...'ftypisom'.codeUnits]);
      await File('${directory.path}/episode.vtt').writeAsString(
        'WEBVTT\n\n00:00:00.000 --> 00:00:30.000\nOffline subtitles\n',
      );
      return directory;
    }))!;
    final video = File('${directory.path}/episode.mp4');
    final subtitles = File('${directory.path}/episode.vtt');
    final previous = VideoPlayerPlatform.instance;
    final platform = _MockVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomVideoPlayer(
              videoUrls: [video.uri.toString()],
              subtitleUrl: subtitles.uri.toString(),
              animeTitle: 'Offline',
              episodeTitle: 'Episode 1',
              autoPlayNext: false,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    platform.position = const Duration(seconds: 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(platform.dataSources.single.sourceType, DataSourceType.file);
    expect(find.text('Offline subtitles'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed default server falls back to another provider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _MockVideoPlayerPlatform();
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final anime = _fixtureAnime();
    final episode = Episode(
      id: '${anime.id}_ep_1',
      animeId: anime.id,
      episodeNumber: 1,
      title: 'Pilot',
      airDate: DateTime(2026),
      duration: const Duration(minutes: 24),
      videoUrls: const [],
    );
    final providers = [
      VideoProviderSource(
        name: 'Gojo',
        description: 'Default',
        languageType: 'SUB',
        videoUrls: ['https://example.com/gojo.m3u8'],
        speedStatus: 'Fast',
        isEmbed: false,
      ),
      VideoProviderSource(
        name: 'Luffy',
        description: 'Fallback',
        languageType: 'SUB',
        videoUrls: ['https://example.com/luffy.m3u8'],
        speedStatus: 'Fast',
        isEmbed: false,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          animeDetailsProvider.overrideWith((ref, id) => anime),
          animeEpisodesProvider.overrideWith((ref, id) => [episode]),
          videoProvidersProvider.overrideWith(
            (ref, params) => Stream.value(providers),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: WatchScreen(animeId: anime.id, episodeId: episode.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final first = tester.widget<CustomVideoPlayer>(
      find.byType(CustomVideoPlayer),
    );
    expect(first.serverLabel, 'Gojo');
    expect(first.initialVideoDisplayMode, 'fit_16_9');
    expect(first.autoPlayNext, isTrue);
    await tester.ensureVisible(find.byType(Switch).first);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(preferences.getBool('settings_auto_play_next'), isFalse);
    expect(
      tester
          .widget<CustomVideoPlayer>(find.byType(CustomVideoPlayer))
          .autoPlayNext,
      isFalse,
    );

    final playerState = tester.state(find.byType(CustomVideoPlayer));
    final platform = VideoPlayerPlatform.instance as _MockVideoPlayerPlatform;
    final created = platform.viewTypes.length;
    platform.position = const Duration(minutes: 3);
    for (final size in [
      const Size(1280, 720),
      const Size(1280, 480),
      const Size(900, 720),
      const Size(1280, 480),
      const Size(1280, 720),
    ]) {
      tester
          .widget<CustomVideoPlayer>(find.byType(CustomVideoPlayer))
          .onToggleFullscreen!();
      await tester.pump();
      tester.view.physicalSize = size;
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state(find.byType(CustomVideoPlayer)), same(playerState));
      expect(
        platform.viewTypes.length,
        created,
        reason: 'Fullscreen and window resizing must not reopen the stream',
      );
      expect(platform.position, const Duration(minutes: 3));
      expect(tester.takeException(), isNull);
    }
    tester
        .widget<CustomVideoPlayer>(find.byType(CustomVideoPlayer))
        .onToggleFullscreen!();
    await tester.pump();
    await tester.ensureVisible(find.text('DNS: Off').first);
    await tester.tap(find.text('DNS: Off').first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byWidgetPredicate(
              (widget) => widget is SizedBox && widget.width == 560,
            ),
          )
          .height,
      lessThan(500),
    );
    expect(find.text('System Default'), findsOneWidget);
    await tester.tap(find.text('System Default'));
    await tester.pumpAndSettle();
    expect(preferences.getString('settings_dns_mode'), 'Off');
    expect(tester.takeException(), isNull);
    first.onPlaybackFailed!();
    await tester.pump();
    expect(
      tester
          .widget<CustomVideoPlayer>(find.byType(CustomVideoPlayer))
          .serverLabel,
      'Luffy',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('watch screen explains an incorrect playback clock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _MockVideoPlayerPlatform();
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final anime = _fixtureAnime();
    final episode = Episode(
      id: '${anime.id}_ep_1',
      animeId: anime.id,
      episodeNumber: 1,
      title: 'Pilot',
      airDate: DateTime(2026),
      duration: const Duration(minutes: 24),
      videoUrls: const [],
    );
    final providers = [
      VideoProviderSource(
        name: 'Gojo',
        description: 'Default',
        languageType: 'SUB',
        videoUrls: ['https://example.com/gojo.m3u8'],
        speedStatus: 'Fast',
        isEmbed: false,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          animeDetailsProvider.overrideWith((ref, id) => anime),
          animeEpisodesProvider.overrideWith((ref, id) => [episode]),
          videoProvidersProvider.overrideWith(
            (ref, params) => Stream.value(providers),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: WatchScreen(animeId: anime.id, episodeId: episode.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final first = tester.widget<CustomVideoPlayer>(
      find.byType(CustomVideoPlayer),
    );
    first.onPlaybackError!(
      'Your device date/time is incorrect. Correct it in system Date & time settings, then retry playback.',
    );
    first.onPlaybackFailed!();
    await tester.pump();
    expect(
      find.textContaining('Your device date/time is incorrect'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('native stream is preferred over unresolved default embed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _MockVideoPlayerPlatform();
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final anime = _fixtureAnime();
    final episode = Episode(
      id: '${anime.id}_ep_1',
      animeId: anime.id,
      episodeNumber: 1,
      title: 'Pilot',
      airDate: DateTime(2026),
      duration: const Duration(minutes: 24),
      videoUrls: const [],
    );
    final providers = [
      VideoProviderSource(
        name: 'Gojo',
        description: 'Default',
        languageType: 'SUB',
        videoUrls: ['https://example.com/embed'],
        speedStatus: 'Fast',
        isEmbed: true,
      ),
      VideoProviderSource(
        name: 'Luffy',
        description: 'Fallback',
        languageType: 'SUB',
        videoUrls: ['https://example.com/luffy.m3u8'],
        speedStatus: 'Fast',
        isEmbed: false,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          animeDetailsProvider.overrideWith((ref, id) => anime),
          animeEpisodesProvider.overrideWith((ref, id) => [episode]),
          videoProvidersProvider.overrideWith(
            (ref, params) => Stream.value(providers),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: WatchScreen(animeId: anime.id, episodeId: episode.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final first = tester.widget<CustomVideoPlayer>(
      find.byType(CustomVideoPlayer),
    );
    expect(first.serverLabel, 'Luffy');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'skip button follows actual interval, seeks to its end and audio starts unmuted',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _MockVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomVideoPlayer(
              videoUrls: ['https://example.com/episode.mp4'],
              animeTitle: 'Fixture',
              episodeTitle: 'Episode 2',
              skipTimes: EpisodeSkipTimes(
                intro: SkipInterval(
                  start: Duration(seconds: 10),
                  end: Duration(seconds: 100),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(platform.volume, 1.0);
      expect(platform.played, true);
      platform.position = const Duration(seconds: 9);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('skip-intro')), findsNothing);
      platform.position = const Duration(seconds: 10);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('skip-intro')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      platform.position = const Duration(seconds: 100);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('skip-intro')), findsNothing);
      platform.position = const Duration(seconds: 70);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('skip-intro')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Skip Intro');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Play or pause');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Skip Intro');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(platform.seeks.last, const Duration(seconds: 100));
      expect(find.byKey(const ValueKey('skip-intro')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'video stays uncropped through adaptive resolution and parent rebuilds',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _MockVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
      Widget player(String initialMode) => MaterialApp(
        home: Scaffold(
          body: CustomVideoPlayer(
            videoUrls: const ['https://example.com/adaptive.m3u8'],
            animeTitle: 'Fixture',
            episodeTitle: 'Episode 1',
            isFullscreen: true,
            initialVideoDisplayMode: initialMode,
          ),
        ),
      );
      await tester.pumpWidget(player('fit_16_9'));
      await tester.pumpAndSettle();
      expect(platform.viewTypes, [VideoViewType.textureView]);
      final image = find.byKey(const ValueKey('player-video-image'));
      expect(tester.getSize(image), const Size(1280, 720));
      final initialRect = tester.getRect(image);
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      controller.value = controller.value.copyWith(size: const Size(1280, 720));
      platform.position = const Duration(minutes: 5);
      await tester.pump(const Duration(seconds: 8));
      expect(tester.getRect(image), initialRect);
      // A preference refresh is not an explicit request to crop the playing video.
      await tester.pumpWidget(player('zoom'));
      await tester.pumpAndSettle();
      expect(tester.getRect(image), initialRect);
      controller.value = controller.value.copyWith(size: const Size(854, 480));
      await tester.pump(const Duration(seconds: 1));
      final adaptiveRect = tester.getRect(image);
      expect(adaptiveRect.width, lessThanOrEqualTo(1280));
      expect(adaptiveRect.height, lessThanOrEqualTo(720));
      expect(
        (adaptiveRect.center - initialRect.center).distance,
        lessThan(0.01),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('auto skip ignores seeks and only skips a boundary once', (
    tester,
  ) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _MockVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomVideoPlayer(
            videoUrls: ['https://example.com/episode.mp4'],
            animeTitle: 'Fixture',
            episodeTitle: 'Episode 1',
            autoSkipIntroOutro: true,
            skipTimes: EpisodeSkipTimes(
              intro: SkipInterval(
                start: Duration(seconds: 10),
                end: Duration(seconds: 100),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    platform.position = const Duration(seconds: 50);
    await tester.pump(const Duration(seconds: 1));
    expect(platform.seeks, isEmpty);
    platform.position = const Duration(seconds: 9);
    await tester.pump(const Duration(seconds: 1));
    platform.position = const Duration(seconds: 10);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(platform.seeks, [const Duration(seconds: 100)]);
    platform.position = const Duration(seconds: 9);
    await tester.pump(const Duration(seconds: 1));
    platform.position = const Duration(seconds: 10);
    await tester.pump(const Duration(seconds: 1));
    expect(platform.seeks.length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('skip buttons stay hidden without episode timing data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _MockVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomVideoPlayer(
            videoUrls: ['https://example.com/episode.mp4'],
            animeTitle: 'Fixture',
            episodeTitle: 'Episode 1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    platform.position = const Duration(seconds: 30);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('skip-intro')), findsNothing);
    platform.position = const Duration(seconds: 1350);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('skip-outro')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'custom video player renders with 16:9 aspect ratio containment for TV display',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final previousPlatform = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = _MockVideoPlayerPlatform();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        VideoPlayerPlatform.instance = previousPlatform;
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SizedBox.expand(
              child: CustomVideoPlayer(
                videoUrls: const ['https://example.com/test.m3u8'],
                animeTitle: 'Mushoku Tensei',
                episodeTitle: 'Episode 1',
                initialVideoDisplayMode: 'fit_16_9',
                autofocus: true,
                isFullscreen: true,
                alwaysShowControls: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify AspectRatio and FittedBox widgets are rendered for containment
      final aspectRatioFinder = find.byType(AspectRatio);
      expect(aspectRatioFinder, findsWidgets);

      final viewportFinder = find.byKey(
        const ValueKey('player-video-viewport'),
      );
      expect(viewportFinder, findsWidgets);

      // Verify the settings button exists and opens settings sheet via desktop remote
      final settingsFinder = find.byIcon(Icons.settings_rounded);
      expect(settingsFinder, findsOneWidget);

      final focusFinder = find
          .ancestor(of: settingsFinder, matching: find.byType(Focus))
          .first;
      final focusWidget = tester.widget<Focus>(focusFinder);
      focusWidget.focusNode?.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.text('Player Settings'), findsOneWidget);
      expect(find.text('Aspect Ratio / Display'), findsOneWidget);
      expect(find.text('Fit 16:9'), findsOneWidget);
      final popupScope = FocusManager.instance.primaryFocus!.nearestScope;
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus!.nearestScope, popupScope);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Player Settings'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player settings');
      final subtitles = tester.widget<DesktopFocusWrapper>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DesktopFocusWrapper &&
              widget.focusNode?.debugLabel == 'Player subtitles',
        ),
      );
      subtitles.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-subtitles')), findsOneWidget);
      final close = tester.widget<DesktopFocusWrapper>(
        find.byKey(const ValueKey('close-subtitles')),
      );
      // Focus the mounted close action through its Focus widget.
      final closeFocus = tester.widget<Focus>(
        find
            .descendant(
              of: find.byKey(const ValueKey('close-subtitles')),
              matching: find.byType(Focus),
            )
            .first,
      );
      closeFocus.focusNode!.requestFocus();
      await tester.pump();
      expect(close.debugLabel, 'Close subtitles');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Subtitles / Captions'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Player subtitles',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('player-video-viewport'))),
        const Size(1920, 1080),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 1000,
                height: 600,
                child: CustomVideoPlayer(
                  videoUrls: ['https://example.com/test.m3u8'],
                  animeTitle: 'Fixture',
                  episodeTitle: 'Episode 1',
                  initialVideoDisplayMode: 'zoom',
                  isFullscreen: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('player-video-viewport'))),
        const Size(1000, 600),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AnimeCard triggers onTap immediately on remote LogicalKeyboardKey.select without focus escaping',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var tapped = false;
      final anime = _fixtureAnime(id: 'test-card-1', title: 'One-Punch Man');
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: AnimeCard(
                anime: anime,
                focusNode: focusNode,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);

      // Activate a focused keyboard control
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    },
  );

  testWidgets('Side nav item does not consume back key, propagating to shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var backPressedOnParent = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.escape ||
                      event.logicalKey == LogicalKeyboardKey.goBack)) {
                backPressedOnParent = true;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: const DesktopSideNav(
              currentIndex: 0,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find the first nav item and focus it
    final navItemFinder = find.byType(DesktopSideNav);
    expect(navItemFinder, findsOneWidget);

    // Press Back key
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(backPressedOnParent, isTrue);
  });

  testWidgets(
    'DesktopPageShell responds to PageDown and PageUp keys by scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ScrollController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DesktopPageShell(
            child: Scaffold(
              body: ListView.builder(
                controller: controller,
                itemCount: 50,
                itemBuilder: (context, index) {
                  return DesktopFocusWrapper(
                    focusNode: index == 0 ? focusNode : null,
                    autofocus: index == 0,
                    child: SizedBox(height: 100, child: Text('Item $index')),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.offset, 0.0);
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0.0));

      final offsetAfterPageDown = controller.offset;
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(offsetAfterPageDown));
    },
  );

  testWidgets(
    'D-pad right at the end of a row stays on the last item without escaping',
    (tester) async {
      final firstNode = FocusNode(debugLabel: 'First item');
      final lastNode = FocusNode(debugLabel: 'Last item');
      addTearDown(firstNode.dispose);
      addTearDown(lastNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Row(
              children: [
                DesktopFocusWrapper(
                  focusNode: firstNode,
                  autofocus: false,
                  debugLabel: 'First item',
                  directionalKeyHandlers: {
                    LogicalKeyboardKey.arrowLeft: () {},
                    LogicalKeyboardKey.arrowRight: () =>
                        lastNode.requestFocus(),
                  },
                  child: const SizedBox(width: 100, height: 100),
                ),
                DesktopFocusWrapper(
                  focusNode: lastNode,
                  autofocus: true,
                  debugLabel: 'Last item',
                  directionalKeyHandlers: {
                    LogicalKeyboardKey.arrowLeft: () =>
                        firstNode.requestFocus(),
                    LogicalKeyboardKey.arrowRight: () {},
                  },
                  child: const SizedBox(width: 100, height: 100),
                ),
              ],
            ),
          ),
        ),
      );
      lastNode.requestFocus();
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Last item');

      // Press ArrowRight: must remain on 'Last item', not escape
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Last item');

      // Move left
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'First item');

      // Press ArrowLeft: must remain on 'First item', not escape
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'First item');
    },
  );

  testWidgets(
    'DesktopFocusManager.ensureFocusedVisible scrolls vertical scrollable to reveal focused child in horizontal row',
    (tester) async {
      final verticalController = ScrollController();
      final node1 = FocusNode(debugLabel: 'Card 1');
      final node2 = FocusNode(debugLabel: 'Card 2 (Row 2)');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 720,
              child: SingleChildScrollView(
                controller: verticalController,
                child: Column(
                  children: [
                    SizedBox(
                      height: 300,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          DesktopFocusWrapper(
                            focusNode: node1,
                            autofocus: true,
                            child: const SizedBox(width: 200, height: 200),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 600),
                    SizedBox(
                      height: 300,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          DesktopFocusWrapper(
                            focusNode: node2,
                            child: const SizedBox(width: 200, height: 200),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(verticalController.offset, 0.0);

      // Focus node2 in row 2 (which is offscreen below 720px)
      node2.requestFocus();
      await tester.pumpAndSettle();

      // Vertical controller must have scrolled down to reveal row 2
      expect(verticalController.offset, greaterThan(100.0));

      // Focus node1 in row 1
      node1.requestFocus();
      await tester.pumpAndSettle();

      // Vertical controller must have scrolled back up to reveal row 1
      expect(verticalController.offset, lessThan(300.0));
    },
  );

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'TV viewport handles late metadata, popups and episode changes at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previousPlatform = VideoPlayerPlatform.instance;
        final platform = _MockVideoPlayerPlatform()..initialSize = Size.zero;
        VideoPlayerPlatform.instance = platform;
        addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
        Widget player(String url) => RepaintBoundary(
          key: const ValueKey('player-preview'),
          child: MaterialApp(
            home: Scaffold(
              body: CustomVideoPlayer(
                videoUrls: [url],
                animeTitle: 'Fixture',
                episodeTitle: 'Episode 1',
                isFullscreen: true,
                alwaysShowControls: true,
              ),
            ),
          ),
        );
        await tester.pumpWidget(player('https://example.com/first.mp4'));
        await tester.pumpAndSettle();
        final image = find.byKey(const ValueKey('player-video-image'));
        final viewport = find.byKey(const ValueKey('player-video-viewport'));
        expect(tester.getSize(image), size);
        expect(tester.getSize(viewport), size);
        final controller = tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller;
        // Metadata alone must update the surface, without a position tick or Back.
        controller.value = controller.value.copyWith(
          size: const Size(1920, 1080),
        );
        await tester.pump();
        expect(tester.getSize(image), size);
        controller.value = controller.value.copyWith(size: Size.zero);
        await tester.pump();
        expect(tester.getSize(image), size);
        controller.value = controller.value.copyWith(
          size: const Size(640, 480),
        );
        await tester.pump();
        expect(tester.getSize(viewport), size);
        expect(tester.getSize(image).height, size.height);
        controller.value = controller.value.copyWith(
          size: const Size(1280, 720),
        );
        await tester.pump();
        expect(tester.getSize(image), size);
        for (final label in [
          'Playback speed',
          'Player subtitles',
          'Player settings',
        ]) {
          final action = tester.widget<DesktopFocusWrapper>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DesktopFocusWrapper &&
                  widget.focusNode?.debugLabel == label,
            ),
          );
          action.focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsOneWidget);
          if (const bool.fromEnvironment('CAPTURE_PLAYER_PREVIEWS') &&
              size.width == 960) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('player-preview')),
              );
              final image = await boundary.toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('build/previews')
                ..createSync(recursive: true);
              await File(
                '${directory.path}/${label.replaceAll(' ', '-').toLowerCase()}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(FocusManager.instance.primaryFocus?.debugLabel, label);
          expect(tester.getSize(image), size);
        }
        await tester.pumpWidget(player('https://example.com/second.mp4'));
        await tester.pumpAndSettle();
        expect(tester.getSize(image), size);
        expect(platform.viewTypes.length, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('DeviceService.exitApp executes safely without crashing', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async => null,
    );
    await expectLater(DeviceService.exitApp(), completes);
  });
}

class _MockVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextId = 0;
  Size initialSize = const Size(1920, 1080);
  Duration position = Duration.zero;
  final List<Duration> seeks = [];
  double? volume;
  bool played = false;
  final List<VideoViewType> viewTypes = [];
  final List<DataSource> dataSources = [];

  final Map<int, StreamController<VideoEvent>> _streams = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int textureId) async {
    await _streams[textureId]?.close();
    _streams.remove(textureId);
  }

  @override
  Future<int?> create(DataSource dataSource) => createWithOptions(
    VideoCreationOptions(
      dataSource: dataSource,
      viewType: VideoViewType.textureView,
    ),
  );

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    viewTypes.add(options.viewType);
    dataSources.add(options.dataSource);
    final id = _nextId++;
    late final StreamController<VideoEvent> stream;
    stream = StreamController<VideoEvent>.broadcast(
      onListen: () {
        scheduleMicrotask(() {
          if (!stream.isClosed) {
            stream.add(
              VideoEvent(
                eventType: VideoEventType.initialized,
                duration: const Duration(minutes: 24),
                size: initialSize,
              ),
            );
          }
        });
      },
    );
    _streams[id] = stream;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _streams[textureId]?.stream ?? const Stream.empty();
  }

  @override
  Widget buildView(int textureId) {
    return const SizedBox(width: 1920, height: 1080);
  }

  @override
  Future<void> play(int textureId) async {
    played = true;
  }

  @override
  Future<void> pause(int textureId) async {}

  @override
  Future<void> setVolume(int textureId, double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    seeks.add(position);
    this.position = position;
  }

  @override
  Future<Duration> getPosition(int textureId) async => position;
}
