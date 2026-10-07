import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../features/home/splash_screen.dart';
import '../../features/downloads/downloads_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/category_screens.dart';
import '../../features/discover/discover_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/favorites/watchlist_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/collections/collections_screen.dart';
import '../../features/settings/desktop_settings_screen.dart';
import '../../features/details/details_screen.dart';
import '../../features/watch/watch_screen.dart';
import '../../features/account/profile_screen.dart';
import '../../features/account/support_screen.dart';
import '../../features/account/edit_profile_screen.dart';
import '../../features/account/mal_anilist_sync_screen.dart';
import '../../features/account/player_settings_screen.dart';
import '../../features/account/subtitle_settings_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/manual_login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../services/auth_service.dart';
import 'app_navigation_scope.dart';
import '../../widgets/desktop_side_nav.dart';
import '../../widgets/desktop_page_shell.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_update_banner.dart';
import '../theme/app_colors.dart';
import '../focus/desktop_navigation_controller.dart';
import '../services/device_service.dart';

// ─── Transition helpers ──────────────────────────────────────────────────────

Page<dynamic> _tabTransitionPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: Builder(
      builder: (context) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            AppNavigationScope.maybeOf(context)?.goBack();
          },
          child: child,
        );
      },
    ),
    transitionDuration: const Duration(milliseconds: 120),
    reverseTransitionDuration: const Duration(milliseconds: 100),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      );
    },
  );
}

bool _isAniWingsOAuthCallback(Uri uri) {
  return uri.scheme == 'aniwings' && uri.host.toLowerCase() == 'oauth';
}

String _syncCallbackLocation(Uri callback) {
  return '/sync?callback=${Uri.encodeQueryComponent(callback.toString())}';
}

// Helper for deep push routes (Premium 3D parallactic slide transition)
Page<dynamic> _pushTransitionPage({
  required LocalKey key,
  required Widget child,
  bool wrapWithPageShell = true,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: wrapWithPageShell
        ? Builder(
            builder: (context) => DesktopPageShell(
              onRootBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
              child: child,
            ),
          )
        : child,
    transitionDuration: const Duration(milliseconds: 140),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      );
    },
  );
}

// ─── Auth Listenable ─────────────────────────────────────────────────────────

class AuthListenable extends ChangeNotifier {
  AuthListenable(Ref ref) {
    ref.listen(authStateProvider, (previous, next) {
      notifyListeners();
    });
  }
}

final authListenableProvider = Provider<AuthListenable>((ref) {
  return AuthListenable(ref);
});

// ─── Launch-once flag ────────────────────────────────────────────────────────
// Tracks whether the splash has already been shown in this process lifetime.
// This is a simple in-memory flag — it resets only on a true cold start
// (process kill), not on app resume or hot restart from background.
bool splashShownThisSession = false;

// ─── Router ──────────────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final authListenable = ref.watch(authListenableProvider);

  // On every cold start of the app, show the splash (loading) screen.
  // If the splash was already shown in this process session (e.g. app was resumed),
  // skip straight to home.
  final String startLocation = splashShownThisSession ? '/home' : '/';

  return GoRouter(
    initialLocation: startLocation,
    refreshListenable: authListenable,
    onException: (context, state, router) {
      final callback = state.uri;
      if (_isAniWingsOAuthCallback(callback)) {
        router.go(_syncCallbackLocation(callback));
        return;
      }
      router.go('/home');
    },
    redirect: (context, state) {
      final user = ref.read(authStateProvider);
      final isLoggedIn = user != null;

      // Determine if active route is gated (requires authentication)
      final gatedLocations = ['/edit-profile', '/sync'];
      final isGated = gatedLocations.any(
        (loc) => state.matchedLocation.startsWith(loc),
      );

      // Determine if active route is auth-specific (login/signup)
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/manual-login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/forgot-password';

      if (!isLoggedIn && isGated) {
        return '/login';
      }

      if (isLoggedIn && isAuthRoute) {
        return '/home';
      }

      return null;
    },
    routes: [
      // ── Splash (only on first cold start) ──
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            _tabTransitionPage(key: state.pageKey, child: const SplashScreen()),
      ),

      // ── Shell for all main desktop tab branches ─────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) => _tabTransitionPage(
                  key: state.pageKey,
                  child: const HomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                pageBuilder: (context, state) => _tabTransitionPage(
                  key: state.pageKey,
                  child: const DiscoverScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                pageBuilder: (context, state) => _tabTransitionPage(
                  key: state.pageKey,
                  child: const SearchScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/watchlist',
                pageBuilder: (context, state) => _tabTransitionPage(
                  key: state.pageKey,
                  child: const WatchlistScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                pageBuilder: (context, state) => _tabTransitionPage(
                  key: state.pageKey,
                  child: const HistoryScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/collections',
                pageBuilder: (context, state) => _tabTransitionPage(
                  key: state.pageKey,
                  child: const CollectionsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => _tabTransitionPage(
                  key: state.pageKey,
                  child: const DesktopSettingsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                pageBuilder: (context, state) => _tabTransitionPage(
                  key: state.pageKey,
                  child: const DownloadsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: '/download-settings',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const DownloadSettingsScreen(),
        ),
      ),

      // ── Redirects / Aliases for existing links ───────────────────────────
      GoRoute(path: '/browse', redirect: (context, state) => '/discover'),
      GoRoute(path: '/schedule', redirect: (context, state) => '/discover'),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const ProfileScreen(),
        ),
      ),

      // ── Deep push routes (outside shell — own back stack) ────────────────
      GoRoute(
        path: '/anime/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _pushTransitionPage(
            key: state.pageKey,
            child: DetailsScreen(animeId: id),
          );
        },
      ),
      GoRoute(
        path: '/watch/:animeId/:episodeId',
        pageBuilder: (context, state) {
          final animeId = state.pathParameters['animeId']!;
          final episodeId = state.pathParameters['episodeId']!;
          return _pushTransitionPage(
            key: state.pageKey,
            child: WatchScreen(animeId: animeId, episodeId: episodeId),
            // WatchScreen owns fullscreen and inline Back handling. Wrapping
            // it in a second key handler can pop the player and then traverse
            // the shell's tab history from a single remote press.
            wrapWithPageShell: false,
          );
        },
      ),
      GoRoute(
        path: '/edit-profile',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          wrapWithPageShell: false,
          child: const EditProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/mal',
        redirect: (context, state) => _syncCallbackLocation(state.uri),
      ),
      GoRoute(
        path: '/anilist',
        redirect: (context, state) => _syncCallbackLocation(state.uri),
      ),
      GoRoute(
        path: '/sync',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          wrapWithPageShell: false,
          child: MalAnilistSyncScreen(
            callbackUrl: state.uri.queryParameters['callback'],
          ),
        ),
      ),
      GoRoute(
        path: '/player-settings',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          wrapWithPageShell: false,
          child: const PlayerSettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/subtitle-settings',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          wrapWithPageShell: false,
          child: const SubtitleSettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/hot-right-now',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const HotRightNowScreen(),
        ),
      ),
      GoRoute(
        path: '/upcoming-anime',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const UpcomingAnimeScreen(),
        ),
      ),
      GoRoute(
        path: '/everyones-watching',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const EveryonesWatchingScreen(),
        ),
      ),
      GoRoute(
        path: '/best-of-2025',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const BestOf2025Screen(),
        ),
      ),
      GoRoute(
        path: '/top-picks',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const TopPicksScreen(),
        ),
      ),
      GoRoute(
        path: '/top-movies',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const TopMoviesScreen(),
        ),
      ),
      GoRoute(
        path: '/curated-for-you',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const CuratedForYouScreen(),
        ),
      ),
      GoRoute(
        path: '/recommended',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const RecommendedScreen(),
        ),
      ),
      GoRoute(
        path: '/support',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          wrapWithPageShell: false,
          child: const SupportScreen(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _pushTransitionPage(key: state.pageKey, child: const LoginScreen()),
      ),
      GoRoute(
        path: '/manual-login',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const ManualLoginScreen(),
        ),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const SignUpScreen(),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => _pushTransitionPage(
          key: state.pageKey,
          child: const ForgotPasswordScreen(),
        ),
      ),
    ],
  );
});

// ─── App Shell ───────────────────────────────────────────────────────────────
// Keeps tab pages alive and tracks branch history so Back returns to the
// previous tab before falling back to Home/the OS.
class _AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const _AppShell({required this.navigationShell});

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final List<int> _branchHistory = <int>[];
  late int _lastIndex;
  bool _isRestoringBranch = false;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.navigationShell.currentIndex;
  }

  @override
  void didUpdateWidget(covariant _AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIndex = widget.navigationShell.currentIndex;
    if (currentIndex == _lastIndex) return;

    if (_isRestoringBranch) {
      _isRestoringBranch = false;
    } else {
      _branchHistory
        ..remove(currentIndex)
        ..add(_lastIndex);
    }
    _lastIndex = currentIndex;
  }

  void _goToBranch(int index, {bool reset = false}) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: reset || index == widget.navigationShell.currentIndex,
    );
  }

  void _restoreBranch(int index) {
    _isRestoringBranch = true;
    widget.navigationShell.goBranch(index);
  }

  void _showExitConfirmationDialog(BuildContext context) {
    DesktopNavigationController.showDesktopDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _DesktopExitConfirmationDialog(),
    );
  }

  DateTime _lastBranchBackTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _goBackThroughBranchHistory() {
    final now = DateTime.now();
    if (now.difference(_lastBranchBackTime).inMilliseconds < 400) {
      return;
    }
    _lastBranchBackTime = now;

    if (_branchHistory.isNotEmpty) {
      final previousIndex = _branchHistory.removeLast();
      _restoreBranch(previousIndex);
      return;
    }

    if (widget.navigationShell.currentIndex != 0) {
      _restoreBranch(0);
      return;
    }

    _showExitConfirmationDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final content = DesktopSideNav(
      currentIndex: widget.navigationShell.currentIndex,
      onDestinationSelected: (index) => _goToBranch(index),
      child: widget.navigationShell,
    );

    final appScope = AppNavigationScope(
      currentBranchIndex: widget.navigationShell.currentIndex,
      goToBranch: _goToBranch,
      goBack: _goBackThroughBranchHistory,
      child: DesktopPageShell(
        onRootBack: _goBackThroughBranchHistory,
        child: Column(
          children: [
            const DesktopUpdateBanner(),
            Expanded(child: content),
          ],
        ),
      ),
    );

    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final isCtrlOrCmd =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyK) {
          _goToBranch(2);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: appScope,
    );
  }
}

class _DesktopExitConfirmationDialog extends StatefulWidget {
  const _DesktopExitConfirmationDialog();

  @override
  State<_DesktopExitConfirmationDialog> createState() =>
      _DesktopExitConfirmationDialogState();
}

class _DesktopExitConfirmationDialogState
    extends State<_DesktopExitConfirmationDialog> {
  late final FocusNode _cancelFocusNode;
  late final FocusNode _exitFocusNode;

  @override
  void initState() {
    super.initState();
    _cancelFocusNode = FocusNode(debugLabel: 'Exit dialog cancel');
    _exitFocusNode = FocusNode(debugLabel: 'Exit dialog confirm');
  }

  @override
  void dispose() {
    _cancelFocusNode.dispose();
    _exitFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: FocusScope(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (DesktopNavigationController.isDesktopBackKey(event)) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.elevatedSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderStrong, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 40,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.accentPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.power_settings_new_rounded,
                        color: AppColors.accentPrimary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Exit AniWings Desktop?',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Are you sure you want to quit AniWings Desktop?',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    DesktopFocusWrapper(
                      focusNode: _cancelFocusNode,
                      autofocus: true,
                      borderRadius: BorderRadius.circular(12),
                      directionalKeyHandlers: {
                        LogicalKeyboardKey.arrowRight: () =>
                            _exitFocusNode.requestFocus(),
                      },
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderStrong),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    DesktopFocusWrapper(
                      focusNode: _exitFocusNode,
                      borderRadius: BorderRadius.circular(12),
                      directionalKeyHandlers: {
                        LogicalKeyboardKey.arrowLeft: () =>
                            _cancelFocusNode.requestFocus(),
                      },
                      onTap: () async {
                        Navigator.of(context).pop();
                        await DeviceService.exitApp();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentPrimary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Exit App',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
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
    );
  }
}
