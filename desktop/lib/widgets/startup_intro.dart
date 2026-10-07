import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

const startupIntroAsset = 'assets/videos/intro_startup.mp4';
const startupPreviewIntroAsset = 'assets/videos/intro_preview.mp4';
final startupIntroSurfaceOwnedProvider = Provider<bool>((ref) => false);
const startupIntroThumbnail = 'assets/videos/intro_startup_thumb.jpg';

final startupIntroProvider = Provider<StartupIntro>((ref) {
  final intro = StartupIntro();
  ref.onDispose(intro.dispose);
  return intro;
});

/// Owns one intro playback across the bootstrap-to-router handoff.
class StartupIntro {
  final VideoPlayerController controller;
  final _started = Completer<void>();
  final _finished = Completer<void>();
  Timer? _deadline;
  bool _disposed = false;

  StartupIntro({VideoPlayerController? controller})
    : controller =
          controller ??
          VideoPlayerController.asset(
            defaultTargetPlatform == TargetPlatform.android
                ? startupPreviewIntroAsset
                : startupIntroAsset,
          ) {
    unawaited(_prepare());
  }

  Future<void> get started => _started.future;
  Future<void> get finished => _finished.future;
  bool get isFinished => _finished.isCompleted;

  Future<void> _prepare() async {
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      if (_disposed) return;
      await controller.setVolume(0);
      if (_disposed) return;
      controller.addListener(_observe);
      if (_disposed) return;
      await controller.play();
      if (_disposed) return;
      _started.complete();
      _deadline = Timer(
        controller.value.duration + const Duration(milliseconds: 50),
        _complete,
      );
    } catch (error) {
      debugPrint('Startup intro unavailable: $error');
      if (!_started.isCompleted) _started.complete();
      _complete();
    }
  }

  void _observe() {
    final value = controller.value;
    if (value.hasError) {
      _complete();
      return;
    }
    final duration = value.duration;
    final position = value.position;
    if (duration > Duration.zero) {
      if (position >= duration - const Duration(milliseconds: 80) ||
          (!value.isPlaying &&
              position >= duration - const Duration(milliseconds: 300))) {
        _complete();
      }
    }
  }

  void _complete() {
    _deadline?.cancel();
    if (!_finished.isCompleted) _finished.complete();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _deadline?.cancel();
    if (!_started.isCompleted) _started.complete();
    _complete();
    controller.removeListener(_observe);
    unawaited(controller.dispose());
  }
}

class StartupIntroSurface extends StatelessWidget {
  final StartupIntro intro;
  const StartupIntroSurface({super.key, required this.intro});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                startupIntroThumbnail,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
              ),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: intro.controller,
                builder: (context, value, child) =>
                    value.isInitialized ? child! : const SizedBox.shrink(),
                child: VideoPlayer(intro.controller),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
