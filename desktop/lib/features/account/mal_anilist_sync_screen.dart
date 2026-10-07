import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/list_sync_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/desktop_page_shell.dart';

class MalAnilistSyncScreen extends ConsumerStatefulWidget {
  final String? callbackUrl;

  const MalAnilistSyncScreen({super.key, this.callbackUrl});

  @override
  ConsumerState<MalAnilistSyncScreen> createState() =>
      _MalAnilistSyncScreenState();
}

class _MalAnilistSyncScreenState extends ConsumerState<MalAnilistSyncScreen> {
  final AppLinks _appLinks = AppLinks();
  final Set<ExternalListProvider> _busyProviders = <ExternalListProvider>{};
  StreamSubscription<Uri>? _linkSubscription;
  final Set<String> _handledCallbackUrls = <String>{};
  ExternalListProvider? _pendingProvider;
  ExternalListSyncResult? _lastResult;
  String? _statusMessage;
  bool _statusIsError = false;

  Map<ExternalListProvider, ExternalListConnection> get _connections {
    return ref.read(listSyncServiceProvider).getConnections();
  }

  @override
  void initState() {
    super.initState();
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (_) {},
    );
    final callbackUrl = widget.callbackUrl;
    if (callbackUrl != null && callbackUrl.isNotEmpty) {
      final callback = Uri.tryParse(callbackUrl);
      if (callback != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_handleIncomingLink(callback));
        });
      }
    }
    unawaited(_handleInitialLink());
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  String _friendlyError(Object error) {
    if (error is ExternalListSyncException) {
      return error.message;
    }
    if (error is TimeoutException) {
      return 'The sync service took too long to respond. Check your connection and try again.';
    }
    return 'Sync failed. Try again later.';
  }

  Future<void> _withBusyProvider(
    ExternalListProvider provider,
    Future<void> Function() action, {
    String? busyMessage,
  }) async {
    setState(() {
      _busyProviders.add(provider);
      _lastResult = null;
      _statusMessage = busyMessage;
      _statusIsError = false;
    });

    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() {
        _statusMessage = message;
        _statusIsError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyProviders.remove(provider);
        });
      }
    }
  }

  Future<void> _connect(ExternalListProvider provider) async {
    if (ref.read(authStateProvider) == null) {
      context.go('/login');
      return;
    }

    final activeConnection = _connections.values.isEmpty
        ? null
        : _connections.values.first;
    if (activeConnection != null && activeConnection.provider != provider) {
      final message =
          'Disconnect ${activeConnection.provider.label} before syncing ${provider.label}. Only one provider can be active.';
      setState(() {
        _lastResult = null;
        _statusMessage = message;
        _statusIsError = true;
      });
      _showSyncSnackBar(backgroundColor: AppColors.danger, message: message);
      return;
    }

    setState(() {
      _busyProviders.add(provider);
      _pendingProvider = provider;
      _lastResult = null;
      _statusMessage = 'Opening ${provider.label} login...';
      _statusIsError = false;
    });

    try {
      final start = await ref
          .read(listSyncServiceProvider)
          .beginAuthorization(provider);
      if (!mounted) return;

      final callbackUrl = await _openAuthorization(start);
      if (callbackUrl == null) return;

      await _completeAuthorization(provider, callbackUrl);
    } catch (error) {
      await ref.read(listSyncServiceProvider).cancelAuthorization(provider);
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() {
        _busyProviders.remove(provider);
        _pendingProvider = null;
        _statusMessage = message;
        _statusIsError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text(message)),
      );
    }
  }

  Future<String?> _openAuthorization(ExternalListAuthorizationStart start) =>
      _openExternalAuthorization(start);

  Future<String?> _openExternalAuthorization(
    ExternalListAuthorizationStart start,
  ) async {
    final opened = await launchUrl(
      start.authorizationUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw ExternalListSyncException(
        'Could not open ${start.provider.label} authorization.',
      );
    }
    if (!mounted) return null;
    setState(() {
      _statusMessage =
          'Finish ${start.provider.label} login in the browser. AniWings Desktop will continue automatically when you return.';
    });
    return null;
  }

  void _notifyStorageChanged() {
    ref.read(storageRevisionProvider.notifier).state++;
  }

  void _showSyncSnackBar({
    required Color backgroundColor,
    required String message,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: backgroundColor, content: Text(message)),
    );
  }

  void _showImportResult(ExternalListSyncResult result) {
    _notifyStorageChanged();
    setState(() {
      _lastResult = result;
      _statusMessage = result.importedCount > 0
          ? 'Imported ${result.importedCount} ${result.importedCount == 1 ? 'entry' : 'entries'} from ${result.provider.label}.'
          : '${result.provider.label} is already in sync.';
      _statusIsError = false;
    });
    _showSyncSnackBar(
      backgroundColor: result.importedCount > 0
          ? AppColors.success
          : AppColors.cardSurface,
      message: _statusMessage ?? '',
    );
  }

  void _showAuthorizationImportResult({
    required ExternalListConnection connection,
    required ExternalListSyncResult? result,
    Object? importError,
  }) {
    final message = importError != null
        ? '${connection.provider.label} connected, but sync failed: ${_friendlyError(importError)}'
        : result == null
        ? '${connection.provider.label} connected.'
        : result.importedCount > 0
        ? 'Synced ${result.importedCount} ${result.importedCount == 1 ? 'entry' : 'entries'} from ${result.provider.label}.'
        : '${result.provider.label} is already in sync.';

    if (result != null) {
      _notifyStorageChanged();
    }

    setState(() {
      _busyProviders.remove(connection.provider);
      _pendingProvider = null;
      _lastResult = result;
      _statusMessage = message;
      _statusIsError = importError != null;
    });
    _showSyncSnackBar(
      backgroundColor: importError != null
          ? AppColors.danger
          : result == null || result.importedCount > 0
          ? AppColors.success
          : AppColors.cardSurface,
      message: message,
    );
  }

  Future<void> _import(ExternalListProvider provider) {
    return _withBusyProvider(
      provider,
      () async {
        final user = ref.read(authStateProvider);
        if (user == null) {
          context.go('/login');
          return;
        }

        final result = await _importConnected(provider, user.id);

        if (!mounted) return;
        _showImportResult(result);
      },
      busyMessage:
          'Fetching your ${provider.label} list. Large libraries can take a moment.',
    );
  }

  Future<void> _sync(ExternalListProvider provider, bool isConnected) {
    return isConnected ? _import(provider) : _connect(provider);
  }

  Future<ExternalListSyncResult> _importConnected(
    ExternalListProvider provider,
    String userId,
  ) {
    return ref
        .read(listSyncServiceProvider)
        .importConnectedWatchProgress(provider: provider, userId: userId);
  }

  Future<void> _disconnect(ExternalListProvider provider) {
    return _withBusyProvider(provider, () async {
      await ref.read(listSyncServiceProvider).disconnect(provider);
      if (!mounted) return;
      setState(() {
        if (_pendingProvider == provider) {
          _pendingProvider = null;
        }
        _lastResult = null;
        _statusMessage = '${provider.label} disconnected.';
        _statusIsError = false;
      });
    });
  }

  Future<void> _cancelConnection(ExternalListProvider provider) async {
    await ref.read(listSyncServiceProvider).cancelAuthorization(provider);
    if (!mounted) return;

    setState(() {
      _busyProviders.remove(provider);
      if (_pendingProvider == provider) {
        _pendingProvider = null;
      }
      _statusMessage = 'Connection cancelled.';
      _statusIsError = false;
    });
  }

  Future<void> _handleInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        await _handleIncomingLink(uri);
      }
    } catch (_) {}
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    final provider = _providerFromOAuthUri(uri);
    if (provider == null) return;

    final callbackUrl = uri.toString();
    if (!_handledCallbackUrls.add(callbackUrl)) return;

    final syncService = ref.read(listSyncServiceProvider);
    if (!syncService.hasPendingAuthorization(provider)) return;

    final fragmentParams = uri.hasFragment
        ? Uri.splitQueryString(uri.fragment)
        : const <String, String>{};
    final error = uri.queryParameters['error'] ?? fragmentParams['error'];
    if (error != null && error.isNotEmpty) {
      await syncService.cancelAuthorization(provider);
      if (!mounted) return;
      final description =
          uri.queryParameters['error_description'] ??
          fragmentParams['error_description'];
      setState(() {
        _busyProviders.remove(provider);
        if (_pendingProvider == provider) {
          _pendingProvider = null;
        }
        _statusMessage = _authorizationFailureMessage(
          provider: provider,
          error: error,
          description: description,
        );
        _statusIsError = true;
      });
      return;
    }

    await _completeAuthorization(provider, callbackUrl);
  }

  String _authorizationFailureMessage({
    required ExternalListProvider provider,
    required String error,
    String? description,
  }) {
    if (provider == ExternalListProvider.aniList &&
        error == 'unsupported_grant_type') {
      return 'AniList rejected the sign-in request. Update the AniList OAuth client configuration, then try again.';
    }

    if (description?.trim().isNotEmpty == true) {
      return description!.trim();
    }
    return '${provider.label} authorization was cancelled.';
  }

  ExternalListProvider? _providerFromOAuthUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final pathSegments = uri.pathSegments
        .map((segment) => segment.toLowerCase())
        .toList();

    if (uri.scheme == 'aniwings' && host == 'oauth') {
      return _providerFromPathSegment(pathSegments);
    }

    final isSupportedWebCallback =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        (host == 'ani-wings.web.app' ||
            host == 'aniwings-app.pages.dev' ||
            host == 'localhost' ||
            host == '127.0.0.1');
    final fragmentParams = uri.hasFragment
        ? Uri.splitQueryString(uri.fragment)
        : const <String, String>{};
    final hasOAuthResult =
        ((uri.queryParameters.containsKey('code') ||
                uri.queryParameters.containsKey('error')) &&
            uri.queryParameters.containsKey('state')) ||
        ((fragmentParams.containsKey('access_token') ||
                fragmentParams.containsKey('error')) &&
            fragmentParams.containsKey('state'));
    if (!isSupportedWebCallback && !hasOAuthResult) return null;

    return _providerFromPathSegment(pathSegments) ?? _pendingProvider;
  }

  ExternalListProvider? _providerFromPathSegment(List<String> pathSegments) {
    for (final segment in pathSegments) {
      switch (segment) {
        case 'anilist':
          return ExternalListProvider.aniList;
        case 'mal':
        case 'myanimelist':
          return ExternalListProvider.myAnimeList;
      }
    }
    return null;
  }

  Future<void> _completeAuthorization(
    ExternalListProvider provider,
    String callbackOrCode,
  ) async {
    setState(() {
      _busyProviders.add(provider);
      _pendingProvider = provider;
      _statusMessage = 'Completing ${provider.label} connection...';
      _statusIsError = false;
    });

    try {
      final connection = await ref
          .read(listSyncServiceProvider)
          .completeAuthorization(
            provider: provider,
            callbackOrCode: callbackOrCode,
          );
      final user = ref.read(authStateProvider);
      ExternalListSyncResult? result;
      Object? importError;
      if (user != null) {
        try {
          result = await _importConnected(provider, user.id);
        } catch (error) {
          importError = error;
        }
      }

      if (!mounted) return;
      _showAuthorizationImportResult(
        connection: connection,
        result: result,
        importError: importError,
      );
    } catch (error) {
      await ref.read(listSyncServiceProvider).cancelAuthorization(provider);
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() {
        _busyProviders.remove(provider);
        if (_pendingProvider == provider) {
          _pendingProvider = null;
        }
        _statusMessage = message;
        _statusIsError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text(message)),
      );
    }
  }

  Color _providerColor(ExternalListProvider provider) {
    return provider == ExternalListProvider.aniList
        ? AppColors.accentPrimary
        : AppColors.accentWarm;
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadii.control,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderMark(ExternalListProvider provider) {
    final color = _providerColor(provider);

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: AppRadii.control,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        provider.logoText,
        style: TextStyle(
          color: color,
          fontSize: provider == ExternalListProvider.aniList ? 16 : 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget _buildIntegrationRow(ExternalListProvider provider) {
    final activeConnection = _connections.values.isEmpty
        ? null
        : _connections.values.first;
    final connection = _connections[provider];
    final isConnected = connection != null;
    final isLocked =
        !isConnected &&
        activeConnection != null &&
        activeConnection.provider != provider;
    final isBusy = _busyProviders.contains(provider);
    final config = ExternalListOAuthConfig.forProvider(provider);
    final color = _providerColor(provider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final statusColor = isConnected
              ? AppColors.success
              : isLocked
              ? AppColors.textMuted
              : config.hasClientId
              ? color
              : AppColors.danger;
          final statusLabel = isConnected
              ? 'Connected'
              : isLocked
              ? 'Locked'
              : config.hasClientId
              ? 'Available'
              : 'Unavailable';
          final providerDetails = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProviderMark(provider),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            provider.label,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!compact)
                          _buildBadge(
                            icon: isConnected
                                ? Icons.verified_rounded
                                : config.hasClientId
                                ? Icons.link_rounded
                                : Icons.error_outline_rounded,
                            label: statusLabel,
                            color: statusColor,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isConnected
                          ? '@${connection.username} - ${connection.expiryLabel}'
                          : isLocked
                          ? 'Disconnect ${activeConnection.provider.label} first to use ${provider.label}.'
                          : provider.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    if (compact) ...[
                      const SizedBox(height: 12),
                      _buildBadge(
                        icon: isConnected
                            ? Icons.verified_rounded
                            : config.hasClientId
                            ? Icons.link_rounded
                            : Icons.error_outline_rounded,
                        label: statusLabel,
                        color: statusColor,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final actions = _buildActions(
            provider,
            isConnected,
            isBusy,
            config.hasClientId,
            isLocked,
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                providerDetails,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: actions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: providerDetails),
              const SizedBox(width: 18),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildActions(
    ExternalListProvider provider,
    bool isConnected,
    bool isBusy,
    bool isConfigured,
    bool isLocked,
  ) {
    if (isBusy) {
      return Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.accentPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.accentPrimary.withValues(alpha: 0.3),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentPrimary,
              ),
            ),
            SizedBox(width: 9),
            Text(
              'Syncing',
              style: TextStyle(
                color: AppColors.accentPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (!isConfigured) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          disabledForegroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.tune_rounded, size: 18),
        label: const Text(
          'Setup needed',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      );
    }

    if (isLocked) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          disabledForegroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
        ),
        icon: const Icon(Icons.lock_rounded, size: 16),
        label: const Text(
          'Locked',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      );
    }

    if (!isConnected) {
      return ElevatedButton.icon(
        onPressed: () => _sync(provider, isConnected),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandRed,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
        ),
        icon: const Icon(Icons.login_rounded, size: 16),
        label: const Text(
          'Connect',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: () => _sync(provider, isConnected),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandRed,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
          ),
          icon: const Icon(Icons.sync_rounded, size: 16),
          label: const Text(
            'Sync now',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => _disconnect(provider),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.danger.withValues(alpha: 0.15),
            foregroundColor: AppColors.danger,
            shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
          ),
          icon: const Icon(Icons.link_off_rounded, size: 18),
          tooltip: 'Disconnect',
        ),
      ],
    );
  }

  Widget _buildStatusPanel() {
    final message = _statusMessage;
    final result = _lastResult;
    final pendingProvider = _pendingProvider;
    final activeBusyProvider =
        pendingProvider ??
        (_busyProviders.isEmpty ? null : _busyProviders.first);
    if (message == null && result == null) return const SizedBox.shrink();

    final importedTitles = result?.importedTitles.join(', ');
    final details = result == null
        ? null
        : 'Scanned ${result.scannedCount} | unchanged ${result.unchangedCount} | skipped ${result.skippedCount}';
    final isPending = activeBusyProvider != null && !_statusIsError;
    final statusColor = _statusIsError
        ? AppColors.danger
        : isPending
        ? AppColors.accentPrimary
        : AppColors.success;
    final statusIcon = _statusIsError
        ? Icons.error_outline_rounded
        : isPending
        ? Icons.hourglass_top_rounded
        : Icons.check_circle_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null)
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (isPending) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(
                      minHeight: 4,
                      color: AppColors.accentPrimary,
                      backgroundColor: AppColors.borderSubtle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${activeBusyProvider.label} is preparing your list. Keep this screen open until it finishes.',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (details != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    details,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (importedTitles != null && importedTitles.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    importedTitles,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (pendingProvider != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _cancelConnection(pendingProvider),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accentPrimary,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderPanel() {
    final connection = _connections.values.isEmpty
        ? null
        : _connections.values.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sync_rounded,
                  color: AppColors.accentPrimary,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Sync your watch history',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Text(
            'Connect one service to import your list. Episodes you finish in AniWings Desktop will update there automatically.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
          if (connection != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Connected to ${connection.provider.label} as @${connection.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = DesktopLayout.pagePadding(context);

    return DesktopPageShell(
      onRootBack: () => context.canPop() ? context.pop() : context.go('/home'),
      child: Scaffold(
        backgroundColor: AppColors.primaryBg,
        body: DesktopPageBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                DesktopPageHeader(
                  leading: DesktopBackButton(
                    autofocus: true,
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/home'),
                  ),
                  eyebrow: 'WATCH SYNC',
                  title: 'List Sync',
                  subtitle: 'Connect AniList or MyAnimeList to your desktop library',
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      32,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeaderPanel(),
                            const SizedBox(height: 22),
                            _buildStatusPanel(),
                            if (_statusMessage != null || _lastResult != null)
                              const SizedBox(height: 22),
                            const DesktopSectionHeader(
                              title: 'Accounts',
                              subtitle:
                                  'Choose one sync provider for your watch progress',
                            ),
                            const SizedBox(height: 14),
                            DesktopSurface(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  _buildIntegrationRow(
                                    ExternalListProvider.aniList,
                                  ),
                                  const Divider(
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                    color: AppColors.borderSubtle,
                                  ),
                                  _buildIntegrationRow(
                                    ExternalListProvider.myAnimeList,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
