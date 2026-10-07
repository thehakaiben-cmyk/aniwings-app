import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:aniwings/widgets/auth_video_background.dart';

void main() {
  testWidgets(
    'auth background is slowed, muted, reused and paused while hidden',
    (tester) async {
      final original = VideoPlayerPlatform.instance;
      final platform = _MockVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const asset = 'assets/videos/signin_bg.mp4';
      final ready = await container.read(
        authBackgroundVideoProvider(asset).future,
      );
      expect(ready.value.playbackSpeed, 0.65);
      expect(platform.volume, 0);
      expect(platform.played, isFalse);
      Widget page(bool visible) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: TickerMode(
            enabled: visible,
            child: const AuthVideoBackground(asset: asset),
          ),
        ),
      );
      await tester.pumpWidget(page(true));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(platform.played, isTrue);
      expect(platform.speed, 0.65);
      await tester.pumpWidget(page(false));
      await tester.pump();
      expect(platform.pauses, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      expect(
        await container.read(authBackgroundVideoProvider(asset).future),
        same(ready),
      );
      expect(platform.dataSources.length, 1);
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
