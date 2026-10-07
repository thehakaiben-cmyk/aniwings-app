import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'firebase_options.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/services/desktop_device_guard.dart';
import 'core/navigation/router.dart';
import 'features/maintenance/maintenance_screen.dart';
import 'services/storage_service.dart';
import 'services/download_service.dart';
import 'services/auth_service.dart';
import 'widgets/startup_intro.dart';
import 'widgets/auth_video_background.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux) {
    VideoPlayerMediaKit.ensureInitialized(windows: true, linux: true);
  }
  // Android landscape and immersive bars are owned by the native preview host.
  // Do not delay the first Flutter frame with duplicate platform-channel calls.

  // Tune ImageCache for smooth desktop rendering
  PaintingBinding.instance.imageCache.maximumSize = 400;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      256 * 1024 * 1024; // 256 MB

  runApp(const DesktopDeviceGate(child: AppBootstrap()));
}

final firebaseInitializationProvider = FutureProvider<bool>((ref) async {
  try {
    if (!splashShownThisSession) {
      await ref.read(startupIntroProvider).finished;
      if (!ref.mounted) return false;
    }
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AuthService.firebaseInitialized = true;
    return true;
  } catch (error) {
    debugPrint('Firebase initialization failed: $error');
    return false;
  }
});

class AppBootstrap extends StatefulWidget {
  final Future<SharedPreferences> Function()? preferencesLoader;
  const AppBootstrap({super.key, this.preferencesLoader});

  @override
  State<AppBootstrap> createState() => AppBootstrapState();
}

class AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  late final StartupIntro _intro;
  late final Future<SharedPreferences> _initialization;
  bool _showIntro = true;

  @override
  void initState() {
    super.initState();
    _intro = StartupIntro();
    _initialization = _initialize();
    _intro.finished.then((_) {
      if (mounted) setState(() => _showIntro = false);
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _intro.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    debugPrint('Low memory pressure detected. Flushing image caches.');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<SharedPreferences> _initialize() async {
    final preferences =
        widget.preferencesLoader?.call() ?? SharedPreferences.getInstance();
    await _intro.started;
    return preferences;
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.fromView(
      view: View.of(context),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<SharedPreferences>(
              future: _initialization,
              builder: (context, snapshot) {
                final prefs = snapshot.data;
                if (prefs == null) {
                  return const ColoredBox(color: Colors.black);
                }
                return ProviderScope(
                  overrides: [
                    sharedPreferencesProvider.overrideWithValue(prefs),
                    startupIntroProvider.overrideWithValue(_intro),
                    startupIntroSurfaceOwnedProvider.overrideWithValue(true),
                  ],
                  child: TickerMode(
                    enabled: !_showIntro,
                    child: Offstage(offstage: _showIntro, child: const MyApp()),
                  ),
                );
              },
            ),
            // This element stays mounted while the router/services are prepared.
            if (_showIntro)
              Positioned.fill(
                key: const ValueKey('persistent-startup-intro'),
                child: ColoredBox(
                  color: Colors.black,
                  child: StartupIntroSurface(intro: _intro),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final deferredAuthPreparationProvider = FutureProvider<void>((ref) async {
  if (!splashShownThisSession) {
    await ref.read(startupIntroProvider).finished;
  }
  if (!ref.mounted) return;
  for (final asset in [
    'assets/videos/signin_bg.mp4',
    'assets/videos/signup_bg.mp4',
  ]) {
    if (!ref.mounted) return;
    try {
      await ref.read(authBackgroundVideoProvider(asset).future);
    } catch (error) {
      debugPrint('Auth video preparation postponed: $error');
    }
  }
});

final deferredDownloadRestorationProvider = FutureProvider<void>((ref) async {
  if (!splashShownThisSession) await ref.read(startupIntroProvider).finished;
  if (ref.mounted) ref.read(downloadServiceProvider);
});

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(deferredAuthPreparationProvider);
    ref.listen(firebaseInitializationProvider, (previous, next) {
      if (next.asData?.value == true && previous?.asData?.value != true) {
        ref.invalidate(authServiceProvider);
      }
    });
    ref.watch(deferredDownloadRestorationProvider);
    final router = ref.watch(routerProvider);
    final maintenanceEnabled = ref.watch(maintenanceModeProvider);
    final user = ref.watch(authStateProvider);

    return MaterialApp.router(
      title: 'AniWings Desktop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
      scrollBehavior: const DesktopScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      builder: (context, child) {
        Widget content;
        if (maintenanceEnabled && !(user?.isAdmin ?? false)) {
          content = const MaintenanceScreen();
        } else {
          content = child ?? const SizedBox.shrink();
        }

        final mediaQuery = MediaQuery.of(context);
        final baseTheme = Theme.of(context);
        final tvFocusOverlay = WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.focused)
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
          child: Theme(
            data: baseTheme.copyWith(
              // InkWell-based controls do not all provide their own focus
              // treatment. A shared colour keeps remote navigation visible.
              focusColor: AppColors.accentPrimary.withValues(alpha: 0.22),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: baseTheme.elevatedButtonTheme.style?.copyWith(
                  overlayColor: tvFocusOverlay,
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: baseTheme.outlinedButtonTheme.style?.copyWith(
                  overlayColor: tvFocusOverlay,
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: baseTheme.textButtonTheme.style?.copyWith(
                  overlayColor: tvFocusOverlay,
                ),
              ),
            ),
            child: Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter):
                    ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.gameButtonA):
                    ActivateIntent(),
              },
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // Keep mouse-wheel and trackpad scrolling bounded at page edges.
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Disable glowing overscroll and stretch effects for smooth desktop scrolling
    return child;
  }
}
