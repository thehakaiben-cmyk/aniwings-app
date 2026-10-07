import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:aniwings/main.dart';
import 'package:aniwings/widgets/startup_intro.dart';

void main() {
  late _MockVideoPlayerPlatform platform;
  setUp(() {
    platform = _MockVideoPlayerPlatform();
    final previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
  });

  testWidgets('intro starts while preferences are still pending', (
    tester,
  ) async {
    final preferences = Completer<SharedPreferences>();
    await tester.pumpWidget(
      AppBootstrap(preferencesLoader: () => preferences.future),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(preferences.isCompleted, isFalse);
    expect(platform.played, isTrue);
    expect(platform.dataSources.single.asset, startupPreviewIntroAsset);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('router preparation does not remount the foreground video', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final preferences = Completer<SharedPreferences>();
    await tester.pumpWidget(
      AppBootstrap(preferencesLoader: () => preferences.future),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final surface = tester.element(find.byType(StartupIntroSurface));
    preferences.complete(prefs);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.element(find.byType(StartupIntroSurface)), same(surface));
    expect(find.byType(VideoPlayer, skipOffstage: false), findsOneWidget);
    expect(platform.dataSources.length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'bootstrap surface handoff retains the same decoder and playback',
    (tester) async {
      final intro = StartupIntro();
      Widget page(String key) => MaterialApp(
        home: StartupIntroSurface(key: ValueKey(key), intro: intro),
      );
      await tester.pumpWidget(page('bootstrap'));
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await intro.started;
      await tester.pumpWidget(page('splash'));
      await tester.pump();
      expect(platform.dataSources.length, 1);
      expect(platform.seeks, isEmpty);
      expect(intro.controller.value.isPlaying, isTrue);
      platform.position = const Duration(minutes: 24);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(intro.isFinished, isTrue);
      await tester.pumpWidget(const SizedBox());
      intro.dispose();
      await tester.pump();
    },
  );
}

class _MockVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextId = 0;
  Size initialSize = const Size(1920, 1080);
  Duration position = Duration.zero;
  final List<Duration> seeks = [];
  double? volume;
  bool played = false;
  int pauses = 0;
  double? speed;
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
  Future<void> pause(int textureId) async {
    pauses++;
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    this.speed = speed;
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    seeks.add(position);
    this.position = position;
  }

  @override
  Future<Duration> getPosition(int textureId) async => position;
}
