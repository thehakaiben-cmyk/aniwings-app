import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// Prepared once per app scope, then reused when switching auth pages.
final authBackgroundVideoProvider =
    FutureProvider.family<VideoPlayerController, String>((ref, asset) async {
      final controller = VideoPlayerController.asset(asset);
      var disposed = false;
      ref.onDispose(() {
        disposed = true;
        unawaited(controller.dispose());
      });
      await controller.initialize();
      if (disposed) throw StateError('Auth video scope disposed');
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.setPlaybackSpeed(0.65);
      return controller;
    });

Future<void> prewarmAuthBackgrounds(
  WidgetRef ref, {
  required bool Function() isMounted,
}) async {
  // Prepare sequentially so multiple decoders do not contend during the intro.
  for (final asset in [
    'assets/videos/signin_bg.mp4',
    'assets/videos/signup_bg.mp4',
  ]) {
    if (!isMounted()) return;
    try {
      await ref.read(authBackgroundVideoProvider(asset).future);
    } catch (error) {
      debugPrint('Auth background preparation failed: $error');
    }
  }
}

class AuthVideoBackground extends ConsumerStatefulWidget {
  final String asset;
  const AuthVideoBackground({super.key, required this.asset});

  @override
  ConsumerState<AuthVideoBackground> createState() =>
      _AuthVideoBackgroundState();
}

class _AuthVideoBackgroundState extends ConsumerState<AuthVideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _foreground = true;
  bool _visible = false;
  bool? _playingRequested;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null) return;
    final play = _foreground && _visible;
    if (_playingRequested == play) return;
    _playingRequested = play;
    unawaited(
      (play ? controller.play() : controller.pause()).catchError((
        Object error,
      ) {
        debugPrint('Auth background playback failed: $error');
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) unawaited(controller.pause());
    // The provider retains the prepared controller for the next visit.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prepared = ref.watch(authBackgroundVideoProvider(widget.asset));
    final controller = prepared.asData?.value;
    if (_controller != controller) {
      _controller = controller;
      _playingRequested = null;
    }
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPlayback();
    });
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            widget.asset.replaceFirst('.mp4', '_thumb.jpg'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF0B0B10)),
          ),
          if (controller != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
