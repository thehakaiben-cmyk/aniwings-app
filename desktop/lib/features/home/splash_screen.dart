import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/navigation/router.dart' show splashShownThisSession;
import '../../core/theme/app_colors.dart';
import '../../services/storage_service.dart';
import '../../services/auth_service.dart';
import '../../services/anime_service.dart';
import '../../services/app_update_service.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../services/image_download_cache.dart';
import '../../widgets/startup_intro.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  late final Animation<double> _exitFadeAnimation;

  late final StartupIntro _intro;
  bool _isVideoFinished = false;
  bool _isTransitioning = false;

  // Remote focus nodes for desktop D-pad / keyboard navigation
  final FocusNode _retryFocusNode = FocusNode(debugLabel: 'SplashRetry');
  final FocusNode _browseOfflineFocusNode = FocusNode(
    debugLabel: 'SplashBrowseOffline',
  );
  final FocusNode _updateNowFocusNode = FocusNode(
    debugLabel: 'SplashUpdateNow',
  );
  final FocusNode _updateLaterFocusNode = FocusNode(
    debugLabel: 'SplashUpdateLater',
  );

  bool _isOffline = false;

  // App Update State
  bool _hasUpdate = false;
  String _currentAppVersion = AppUpdateService.fallbackAppVersion;
  String _newVersion = '';
  String _updateUrl = '';
  List<String> _releaseNotes = const [];
  bool _isMandatoryUpdate = false;

  @override
  void initState() {
    super.initState();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _exitFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOutCubic),
    );

    _intro = ref.read(startupIntroProvider);
    _isVideoFinished = _intro.isFinished;
    unawaited(
      _intro.finished.then((_) {
        if (mounted) _onVideoFinished();
      }),
    );
    // Check updates & connectivity concurrently in background without starving video decoder
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runStartupSequence());
      if (_intro.isFinished) _checkTransitionReady();
    });
  }

  @override
  void dispose() {
    _exitController.dispose();
    _retryFocusNode.dispose();
    _browseOfflineFocusNode.dispose();
    _updateNowFocusNode.dispose();
    _updateLaterFocusNode.dispose();
    super.dispose();
  }

  void _onVideoFinished() {
    if (_isVideoFinished) return;
    setState(() => _isVideoFinished = true);
    unawaited(_warmHomeContent());
    _checkTransitionReady();
  }

  /// Concurrently verify connectivity and updates in the background
  /// while the intro video plays on screen.
  Future<void> _runStartupSequence() async {
    if (!mounted) return;
    setState(() {
      _isOffline = false;
      _hasUpdate = false;
    });

    // Step 1: Internet connectivity check
    final hasInternet = await _hasInternetConnection();
    if (!mounted) return;

    if (!hasInternet) {
      setState(() {
        _isOffline = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retryFocusNode.requestFocus();
      });
      return;
    }

    // Step 2: Check for app updates in the background
    try {
      final result = await ref
          .read(appUpdateServiceProvider)
          .check()
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;

      if (result.hasUpdate) {
        final latestVersion = result.release.version;
        final storage = ref.read(storageServiceProvider);
        final dismissedVersion = storage.getDismissedUpdateVersion();

        if (result.isMandatory || dismissedVersion != latestVersion) {
          setState(() {
            _currentAppVersion = result.currentVersion;
            _hasUpdate = true;
            _newVersion = latestVersion;
            _updateUrl = result.desktopUpdateUrl;
            _releaseNotes = result.release.releaseNotes;
            _isMandatoryUpdate = result.isMandatory;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateNowFocusNode.requestFocus();
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Update check warning: $e');
    }

    _checkTransitionReady();
  }

  Future<bool> _hasInternetConnection() async {
    if (kIsWeb) return true;
    final client = http.Client();
    try {
      return await ConnectivityService(client).isOnline();
    } finally {
      client.close();
    }
  }

  Future<void> _warmHomeContent() async {
    final trendingFuture = ref.read(trendingAnimeProvider.future);
    final recentFuture = ref.read(recentlyUpdatedProvider.future);
    unawaited(ref.read(hotRightNowProvider.future).onError((_, _) => []));
    unawaited(ref.read(upcomingAnimeProvider.future).onError((_, _) => []));
    unawaited(ref.read(everyonesWatchingProvider.future).onError((_, _) => []));

    final service = ref.read(animeServiceProvider);
    final storage = ref.read(storageServiceProvider);
    final userId =
        ref.read(authStateProvider)?.id ??
        StorageService.guestWatchHistoryUserId;
    for (final entry
        in storage
            .getWatchHistory(userId: userId)
            .where((entry) => !entry.isExternalSync)
            .take(6)) {
      unawaited(
        service
            .getAnimeById(entry.animeId)
            .then((anime) async {
              if (anime == null) return;
              await ImageDownloadCache.shared.prefetch([
                anime.backdropUrl.trim().isNotEmpty
                    ? anime.backdropUrl
                    : anime.posterUrl,
              ]);
            })
            .catchError((Object _) {}),
      );
    }

    // Download encoded bytes while the intro runs. These jobs are independent
    // of the splash widget, so navigation cannot cancel the Home warmup.
    unawaited(
      trendingFuture
          .then((trending) async {
            if (trending.isEmpty) return;
            final hero = trending.first;
            await ImageDownloadCache.shared.prefetch([
              hero.backdropUrl.isNotEmpty ? hero.backdropUrl : hero.posterUrl,
              ...trending.take(8).map((anime) => anime.posterUrl),
              ...trending
                  .skip(1)
                  .take(1)
                  .map(
                    (anime) => anime.backdropUrl.isNotEmpty
                        ? anime.backdropUrl
                        : anime.posterUrl,
                  ),
            ]);
          })
          .catchError((Object _) {}),
    );
    unawaited(
      recentFuture
          .then((recent) async {
            await ImageDownloadCache.shared.prefetch(
              recent
                  .take(4)
                  .map(
                    (anime) => anime.backdropUrl.isNotEmpty
                        ? anime.backdropUrl
                        : anime.posterUrl,
                  ),
            );
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> _checkTransitionReady() async {
    if (_isTransitioning || !mounted) return;
    if (_hasUpdate || _isOffline) return;

    if (!_isVideoFinished) return;

    await _continueToHome();
  }

  Future<void> _continueToHome() async {
    if (_isTransitioning || !mounted) return;
    _isTransitioning = true;
    unawaited(_warmHomeContent());
    splashShownThisSession = true;
    final prefs = ref.read(storageServiceProvider);
    unawaited(prefs.markAppLaunched());
    if (mounted) {
      context.go('/home');
    }
  }

  Future<void> _launchUpdate() async {
    final targetUrl = _updateUrl.isNotEmpty
        ? _updateUrl
        : 'https://github.com/thehakaiben-cmyk/aniwings-app/releases';
    final uri = Uri.tryParse(targetUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch update URL: $e');
    }
  }

  Future<void> _dismissUpdateAndContinue() async {
    if (_newVersion.isNotEmpty) {
      await ref
          .read(storageServiceProvider)
          .setDismissedUpdateVersion(_newVersion);
    }
    await _continueToHome();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_hasUpdate && !_isMandatoryUpdate) {
          await _dismissUpdateAndContinue();
        } else if (_isOffline) {
          _runStartupSequence();
        }
      },
      child: FadeTransition(
        opacity: _exitFadeAnimation,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            alignment: Alignment.center,
            children: [
              // Clean Black Background matching video
              Positioned.fill(child: Container(color: Colors.black)),

              // High-fidelity 10s intro video with 16:9 aspect ratio display fit
              Positioned.fill(
                child: ref.read(startupIntroSurfaceOwnedProvider)
                    ? const SizedBox.shrink()
                    : Center(child: StartupIntroSurface(intro: _intro)),
              ),

              // ─── Network Error / Offline desktop Screen ────────────────────────
              if (_isOffline && _isVideoFinished)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.88),
                    alignment: Alignment.center,
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 600),
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.fromLTRB(36, 36, 36, 32),
                      decoration: BoxDecoration(
                        color: AppColors.elevatedSurface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppColors.borderStrong,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: AppColors.accentPrimary.withValues(
                                alpha: 0.15,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.accentPrimary.withValues(
                                  alpha: 0.4,
                                ),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.wifi_off_rounded,
                              color: AppColors.accentPrimary,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'No Internet Connection',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'AniWings Desktop requires a network connection to stream anime and sync your watchlist. Please check your internet connection.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.45,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              // Secondary action: Browse Offline
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: DesktopFocusWrapper.builder(
                                    focusNode: _browseOfflineFocusNode,
                                    onTap: () => _continueToHome(),
                                    borderRadius: BorderRadius.circular(14),
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowRight: () =>
                                          _retryFocusNode.requestFocus(),
                                    },
                                    builder: (context, isFocused, isHovered) {
                                      final active = isFocused || isHovered;
                                      return AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 140,
                                        ),
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: active
                                              ? AppColors.secondaryBg
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: active
                                                ? Colors.white
                                                : AppColors.borderSubtle,
                                            width: active ? 2.0 : 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.cloud_off_rounded,
                                              size: 18,
                                              color: active
                                                  ? Colors.white
                                                  : AppColors.textSecondary,
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Browse Offline',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: active
                                                      ? Colors.white
                                                      : AppColors.textSecondary,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              // Primary action: Retry Connection (autofocused)
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: DesktopFocusWrapper.builder(
                                    focusNode: _retryFocusNode,
                                    autofocus: true,
                                    onTap: _runStartupSequence,
                                    borderRadius: BorderRadius.circular(14),
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _browseOfflineFocusNode
                                              .requestFocus(),
                                    },
                                    builder: (context, isFocused, isHovered) {
                                      final active = isFocused || isHovered;
                                      return AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 140,
                                        ),
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentPrimary,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: active
                                                ? Colors.white
                                                : Colors.transparent,
                                            width: active ? 2.5 : 0.0,
                                          ),
                                          boxShadow: active
                                              ? const [
                                                  BoxShadow(
                                                    color: Color(0x66000000),
                                                    blurRadius: 10,
                                                    offset: Offset(0, 3),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.refresh_rounded,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Retry Connection',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ─── Update Available desktop Screen ──────────────────────────────
              if (_hasUpdate && _isVideoFinished)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.88),
                    alignment: Alignment.center,
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 580),
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.fromLTRB(36, 34, 36, 30),
                      decoration: BoxDecoration(
                        color: AppColors.elevatedSurface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppColors.borderStrong,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: AppColors.accentPrimary.withValues(
                                alpha: 0.15,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.accentPrimary.withValues(
                                  alpha: 0.4,
                                ),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.system_update_rounded,
                              color: AppColors.accentPrimary,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _isMandatoryUpdate
                                ? 'Required Update'
                                : 'Update Available',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),

                          // Version comparison badge
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'CURRENT VERSION',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        AppUpdateService.displayVersion(
                                          _currentAppVersion,
                                        ),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.accentPrimary.withValues(
                                      alpha: 0.15,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: AppColors.accentPrimary,
                                    size: 18,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'NEW VERSION',
                                        style: TextStyle(
                                          color: AppColors.accentPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        AppUpdateService.displayVersion(
                                          _newVersion,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Release notes or summary
                          if (_releaseNotes.isNotEmpty)
                            Container(
                              constraints: const BoxConstraints(maxHeight: 90),
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListView(
                                shrinkWrap: true,
                                children: _releaseNotes.take(3).map((note) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '• ',
                                          style: TextStyle(
                                            color: AppColors.accentPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            note,
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            )
                          else
                            const Text(
                              'A new update is available with desktop optimizations, streaming enhancements, and BitTorrent performance improvements.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),

                          const SizedBox(height: 24),

                          // Action Buttons
                          Row(
                            children: [
                              if (!_isMandatoryUpdate) ...[
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: DesktopFocusWrapper.builder(
                                      focusNode: _updateLaterFocusNode,
                                      onTap: _dismissUpdateAndContinue,
                                      borderRadius: BorderRadius.circular(14),
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowRight: () =>
                                            _updateNowFocusNode.requestFocus(),
                                      },
                                      builder: (context, isFocused, isHovered) {
                                        final active = isFocused || isHovered;
                                        return AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 140,
                                          ),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? AppColors.secondaryBg
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: active
                                                  ? Colors.white
                                                  : AppColors.borderSubtle,
                                              width: active ? 2.0 : 1.0,
                                            ),
                                          ),
                                          child: const Text(
                                            'Later',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                              ],
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: DesktopFocusWrapper.builder(
                                    focusNode: _updateNowFocusNode,
                                    autofocus: true,
                                    onTap: _launchUpdate,
                                    borderRadius: BorderRadius.circular(14),
                                    directionalKeyHandlers: {
                                      if (!_isMandatoryUpdate)
                                        LogicalKeyboardKey.arrowLeft: () =>
                                            _updateLaterFocusNode
                                                .requestFocus(),
                                    },
                                    builder: (context, isFocused, isHovered) {
                                      final active = isFocused || isHovered;
                                      return AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 140,
                                        ),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppColors.accentPrimary,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: active
                                                ? Colors.white
                                                : Colors.transparent,
                                            width: active ? 2.5 : 0.0,
                                          ),
                                          boxShadow: active
                                              ? const [
                                                  BoxShadow(
                                                    color: Color(0x66000000),
                                                    blurRadius: 10,
                                                    offset: Offset(0, 3),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.download_rounded,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Update Now',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
