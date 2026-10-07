import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/list_sync_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/desktop_layout.dart';

/// AniWings Desktop — Account & Profile Dashboard.
/// Purely desktop-native interface designed for mouse and keyboard control.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _showSignOutDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.secondaryBg,
            borderRadius: AppRadii.dialog,
            border: Border.all(color: AppColors.border, width: 1.0),
            boxShadow: const [AppColors.shadowPanel],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandRed.withValues(alpha: 0.15),
                      borderRadius: AppRadii.control,
                      border: Border.all(
                        color: AppColors.brandRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.brandRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Sign Out of AniWings?',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Are you sure you want to sign out? Your cloud profile will be disconnected and the app will switch back to local guest viewing.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.control,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadii.control,
                      ),
                    ),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      await ref.read(authStateProvider.notifier).logout();
                      if (context.mounted) {
                        context.go('/home');
                      }
                    },
                    child: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider);
    final storage = ref.watch(storageServiceProvider);
    ref.watch(storageRevisionProvider);

    final activeUserId = user?.id ?? StorageService.guestWatchHistoryUserId;
    final watchlistCount = storage.getWatchlist().length;
    final historyList = storage.getWatchHistory(userId: activeUserId);
    final historyCount = historyList.length;
    final completedCount = historyList.where((e) => e.isCompleted).length;

    final listSync = ref.watch(listSyncServiceProvider);
    final malConnection = listSync.getConnection(
      ExternalListProvider.myAnimeList,
    );
    final anilistConnection = listSync.getConnection(
      ExternalListProvider.aniList,
    );

    final leftPadding = DesktopLayout.pageLeftPadding(context);
    final rightPadding = DesktopLayout.pagePadding(context);
    final isWide = MediaQuery.of(context).size.width >= 960;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        },
      },
      child: Scaffold(
        backgroundColor: AppColors.primaryBg,
        body: Stack(
          children: [
            const Positioned.fill(child: DesktopBackground()),
            SafeArea(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(leftPadding, 24, rightPadding, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Desktop Header
                    _buildHeader(context),

                    const SizedBox(height: 24),

                    // Main Content: 2-column or stacked
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left column: Profile card & credentials
                          SizedBox(
                            width: 380,
                            child: _buildUserCard(context, ref, user),
                          ),
                          const SizedBox(width: 28),
                          // Right column: Statistics & Integrations
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatsGrid(
                                  context,
                                  watchlistCount: watchlistCount,
                                  historyCount: historyCount,
                                  completedCount: completedCount,
                                  syncActive:
                                      malConnection != null ||
                                      anilistConnection != null,
                                ),
                                const SizedBox(height: 24),
                                _buildSyncCard(
                                  context,
                                  malConnection: malConnection,
                                  anilistConnection: anilistConnection,
                                ),
                                const SizedBox(height: 24),
                                _buildPreferencesOverviewCard(context, storage),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildUserCard(context, ref, user),
                          const SizedBox(height: 24),
                          _buildStatsGrid(
                            context,
                            watchlistCount: watchlistCount,
                            historyCount: historyCount,
                            completedCount: completedCount,
                            syncActive:
                                malConnection != null ||
                                anilistConnection != null,
                          ),
                          const SizedBox(height: 24),
                          _buildSyncCard(
                            context,
                            malConnection: malConnection,
                            anilistConnection: anilistConnection,
                          ),
                          const SizedBox(height: 24),
                          _buildPreferencesOverviewCard(context, storage),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.brandRed,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'ACCOUNT',
          style: TextStyle(
            color: AppColors.brandRed,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'Profile & Cloud Dashboard',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildUserCard(BuildContext context, WidgetRef ref, dynamic user) {
    final isLoggedIn = user != null;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLoggedIn ? AppColors.brandRed : Colors.white24,
                    width: 2.0,
                  ),
                ),
                child: CircleAvatar(
                  radius: 34,
                  foregroundImage: user?.avatarUrl?.isNotEmpty == true
                      ? (user!.avatarUrl!.startsWith('assets/')
                            ? AssetImage(user.avatarUrl!) as ImageProvider
                            : NetworkImage(user.avatarUrl!))
                      : null,
                  onForegroundImageError: user?.avatarUrl?.isNotEmpty == true
                      ? (_, _) {}
                      : null,
                  backgroundColor: const Color(0xFF262A35),
                  child: Text(
                    !isLoggedIn || user.username.isEmpty
                        ? 'G'
                        : user.username.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.username ?? 'Guest Explorer',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user?.email ?? 'Local desktop session',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isLoggedIn
                            ? AppColors.success.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: AppRadii.control,
                        border: Border.all(
                          color: isLoggedIn
                              ? AppColors.success
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLoggedIn
                                ? Icons.verified_user_rounded
                                : Icons.info_outline_rounded,
                            size: 12,
                            color: isLoggedIn
                                ? AppColors.success
                                : Colors.white70,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isLoggedIn ? 'AniWings Member' : 'Guest Mode',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isLoggedIn
                                  ? AppColors.success
                                  : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 18),

          if (!isLoggedIn) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.elevatedSurface,
                borderRadius: AppRadii.control,
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.cloud_sync_outlined,
                    color: AppColors.brandRed,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sign in to synchronize your watchlist, viewing history, and preferences across all devices.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.push('/login'),
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text('Sign In'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandRed,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(40),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.control,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/signup'),
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text('Create Account'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(40),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.control,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ] else ...[
            ElevatedButton.icon(
              onPressed: () => context.push('/edit-profile'),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit Profile & Avatar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.elevatedSurface,
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(40),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.control,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showSignOutDialog(context, ref),
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandRed,
                side: BorderSide(
                  color: AppColors.brandRed.withValues(alpha: 0.5),
                ),
                minimumSize: const Size.fromHeight(40),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.control,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsGrid(
    BuildContext context, {
    required int watchlistCount,
    required int historyCount,
    required int completedCount,
    required bool syncActive,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Activity Overview',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - (3 * 14)) / 4;
            final isTight = cardWidth < 140;

            if (isTight) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatTile(
                    label: 'Watchlist',
                    value: '$watchlistCount',
                    icon: Icons.bookmark_added_rounded,
                    color: AppColors.brandRed,
                    width: (constraints.maxWidth - 12) / 2,
                    onTap: () => context.go('/watchlist'),
                  ),
                  _buildStatTile(
                    label: 'Episodes Watched',
                    value: '$historyCount',
                    icon: Icons.play_circle_fill_rounded,
                    color: const Color(0xFF3B82F6),
                    width: (constraints.maxWidth - 12) / 2,
                    onTap: () => context.go('/history'),
                  ),
                  _buildStatTile(
                    label: 'Completed',
                    value: '$completedCount',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF10B981),
                    width: (constraints.maxWidth - 12) / 2,
                    onTap: () => context.go('/history'),
                  ),
                  _buildStatTile(
                    label: 'Cloud Sync',
                    value: syncActive ? 'Active' : 'Off',
                    icon: Icons.cloud_sync_rounded,
                    color: const Color(0xFF8B5CF6),
                    width: (constraints.maxWidth - 12) / 2,
                    onTap: () => context.push('/sync'),
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: _buildStatTile(
                    label: 'Watchlist',
                    value: '$watchlistCount',
                    icon: Icons.bookmark_added_rounded,
                    color: AppColors.brandRed,
                    onTap: () => context.go('/watchlist'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildStatTile(
                    label: 'Episodes Watched',
                    value: '$historyCount',
                    icon: Icons.play_circle_fill_rounded,
                    color: const Color(0xFF3B82F6),
                    onTap: () => context.go('/history'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildStatTile(
                    label: 'Completed',
                    value: '$completedCount',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF10B981),
                    onTap: () => context.go('/history'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildStatTile(
                    label: 'Cloud Sync',
                    value: syncActive ? 'Active' : 'Off',
                    icon: Icons.cloud_sync_rounded,
                    color: const Color(0xFF8B5CF6),
                    onTap: () => context.push('/sync'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double? width,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.card,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.card,
          border: Border.all(color: AppColors.border, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: AppRadii.control,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: Colors.white24,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncCard(
    BuildContext context, {
    required ExternalListConnection? malConnection,
    required ExternalListConnection? anilistConnection,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.brandRed.withValues(alpha: 0.15),
                  borderRadius: AppRadii.control,
                ),
                child: const Icon(
                  Icons.sync_alt_rounded,
                  color: AppColors.brandRed,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'External List Integrations',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Two-way sync and scrobble viewing progress to MyAnimeList & AniList.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/sync'),
                icon: const Icon(Icons.settings_outlined, size: 15),
                label: const Text('Configure'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadii.control,
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildIntegrationStatusTile(
                  name: 'MyAnimeList',
                  badge: 'MAL',
                  badgeColor: const Color(0xFF2E51A2),
                  connection: malConnection,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildIntegrationStatusTile(
                  name: 'AniList',
                  badge: 'AL',
                  badgeColor: const Color(0xFF02A9FF),
                  connection: anilistConnection,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntegrationStatusTile({
    required String name,
    required String badge,
    required Color badgeColor,
    required ExternalListConnection? connection,
  }) {
    final isConnected = connection != null && !connection.isExpired;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: AppRadii.control,
        border: Border.all(
          color: isConnected
              ? badgeColor.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: AppRadii.control,
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isConnected ? '@${connection.username}' : 'Not connected',
                  style: TextStyle(
                    fontSize: 11,
                    color: isConnected
                        ? AppColors.success
                        : AppColors.textSecondary,
                    fontWeight: isConnected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? AppColors.success : Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesOverviewCard(
    BuildContext context,
    StorageService storage,
  ) {
    final defaultServer = storage.getDefaultServerPreference();
    final defaultAudio = storage.getDefaultAudioPreference();
    final quality = storage.getVideoQualityPreference();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: AppRadii.control,
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Playback Preferences',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your current video resolution and server settings.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.push('/settings'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadii.control,
                  ),
                ),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _buildConfigChip('Server', defaultServer),
              _buildConfigChip('Audio', defaultAudio),
              _buildConfigChip('Quality', quality),
              _buildConfigChip('App Version', 'v1.2.5 Desktop'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: AppRadii.control,
        border: Border.all(color: AppColors.border, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
