import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../services/app_update_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_page_shell.dart';
import '../../widgets/desktop_layout.dart';

/// Playback preferences for AniWings desktop's native player.
/// Designed for desktop remotes with setting titles on the left and change options on the right.
class PlayerSettingsScreen extends ConsumerStatefulWidget {
  const PlayerSettingsScreen({super.key});

  @override
  ConsumerState<PlayerSettingsScreen> createState() =>
      _PlayerSettingsScreenState();
}

class _PlayerSettingsScreenState extends ConsumerState<PlayerSettingsScreen> {
  late String _defaultServer;
  late String _defaultAudio;
  late bool _autoPlayNext;
  late String _quality;

  bool _isCheckingUpdate = false;
  bool _hasAvailableUpdate = false;
  String _currentVersion = AppUpdateService.fallbackAppVersion;
  String _latestVersion = AppUpdateService.fallbackAppVersion;
  String _updateUrl = '';
  String _updateStatus = 'Check for the newest AniWings Desktop release.';

  late final FocusNode _backButtonFocusNode;
  late final FocusNode _serverGojoFocusNode;
  late final FocusNode _serverKakashiFocusNode;
  late final FocusNode _serverLuffyFocusNode;
  late final FocusNode _serverTanjiroFocusNode;
  late final FocusNode _serverLeviFocusNode;
  late final FocusNode _audioSubFocusNode;
  late final FocusNode _audioDubFocusNode;
  late final FocusNode _autoPlayDisabledFocusNode;
  late final FocusNode _autoPlayEnabledFocusNode;
  late final FocusNode _quality1080FocusNode;
  late final FocusNode _quality720FocusNode;
  late final FocusNode _quality480FocusNode;
  late final FocusNode _qualityAutoFocusNode;
  late final FocusNode _subtitlesFocusNode;
  late final FocusNode _updatesFocusNode;

  @override
  void initState() {
    super.initState();
    final storage = ref.read(storageServiceProvider);
    _defaultServer = storage.getDefaultServerPreference();
    _defaultAudio = storage.getDefaultAudioPreference();
    _autoPlayNext = storage.getAutoPlayNext();
    _quality = storage.getVideoQualityPreference();

    _backButtonFocusNode = FocusNode(debugLabel: 'Settings Back Button');
    _serverGojoFocusNode = FocusNode(debugLabel: 'Server Gojo');
    _serverKakashiFocusNode = FocusNode(debugLabel: 'Server Kakashi');
    _serverLuffyFocusNode = FocusNode(debugLabel: 'Server Luffy');
    _serverTanjiroFocusNode = FocusNode(debugLabel: 'Server Tanjiro');
    _serverLeviFocusNode = FocusNode(debugLabel: 'Server Levi');
    _audioSubFocusNode = FocusNode(debugLabel: 'Audio SUB');
    _audioDubFocusNode = FocusNode(debugLabel: 'Audio DUB');
    _autoPlayDisabledFocusNode = FocusNode(debugLabel: 'Autoplay Disabled');
    _autoPlayEnabledFocusNode = FocusNode(debugLabel: 'Autoplay Enabled');
    _quality1080FocusNode = FocusNode(debugLabel: 'Quality 1080p');
    _quality720FocusNode = FocusNode(debugLabel: 'Quality 720p');
    _quality480FocusNode = FocusNode(debugLabel: 'Quality 480p');
    _qualityAutoFocusNode = FocusNode(debugLabel: 'Quality Auto');
    _subtitlesFocusNode = FocusNode(debugLabel: 'Subtitles Setting Button');
    _updatesFocusNode = FocusNode(debugLabel: 'Updates Setting Button');
  }

  @override
  void dispose() {
    _backButtonFocusNode.dispose();
    _serverGojoFocusNode.dispose();
    _serverKakashiFocusNode.dispose();
    _serverLuffyFocusNode.dispose();
    _serverTanjiroFocusNode.dispose();
    _serverLeviFocusNode.dispose();
    _audioSubFocusNode.dispose();
    _audioDubFocusNode.dispose();
    _autoPlayDisabledFocusNode.dispose();
    _autoPlayEnabledFocusNode.dispose();
    _quality1080FocusNode.dispose();
    _quality720FocusNode.dispose();
    _quality480FocusNode.dispose();
    _qualityAutoFocusNode.dispose();
    _subtitlesFocusNode.dispose();
    _updatesFocusNode.dispose();
    super.dispose();
  }

  FocusNode get _currentServerFocusNode {
    return switch (_defaultServer.toLowerCase()) {
      'kakashi' => _serverKakashiFocusNode,
      'luffy' => _serverLuffyFocusNode,
      'tanjiro' => _serverTanjiroFocusNode,
      'levi' => _serverLeviFocusNode,
      _ => _serverGojoFocusNode,
    };
  }

  FocusNode get _currentAudioFocusNode {
    return _defaultAudio.toUpperCase() == 'DUB'
        ? _audioDubFocusNode
        : _audioSubFocusNode;
  }

  FocusNode get _currentAutoPlayFocusNode {
    return _autoPlayNext
        ? _autoPlayEnabledFocusNode
        : _autoPlayDisabledFocusNode;
  }

  FocusNode get _currentQualityFocusNode {
    return switch (_quality.toLowerCase()) {
      '720p' => _quality720FocusNode,
      '480p' => _quality480FocusNode,
      'auto' => _qualityAutoFocusNode,
      _ => _quality1080FocusNode,
    };
  }

  Future<void> _setServer(String server) async {
    setState(() => _defaultServer = server);
    final storage = ref.read(storageServiceProvider);
    await storage.setDefaultServerPreference(server);
    if (!mounted) return;
    ref.read(storageRevisionProvider.notifier).state++;
  }

  Future<void> _setAudio(String audio) async {
    setState(() => _defaultAudio = audio);
    final storage = ref.read(storageServiceProvider);
    await storage.setDefaultAudioPreference(audio);
    if (!mounted) return;
    ref.read(storageRevisionProvider.notifier).state++;
  }

  Future<void> _setAutoPlayNext(bool value) async {
    setState(() => _autoPlayNext = value);
    final storage = ref.read(storageServiceProvider);
    await storage.setAutoPlayNext(value);
    if (!mounted) return;
    ref.read(storageRevisionProvider.notifier).state++;
  }

  Future<void> _setQuality(String quality) async {
    setState(() => _quality = quality);
    final storage = ref.read(storageServiceProvider);
    await storage.setVideoQualityPreference(quality);
    if (!mounted) return;
    ref.read(storageRevisionProvider.notifier).state++;
  }

  Future<void> _checkForUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() {
      _isCheckingUpdate = true;
      _updateStatus = 'Checking update.json...';
    });

    try {
      final result = await ref.read(appUpdateServiceProvider).check();
      if (!mounted) return;
      setState(() {
        _currentVersion = result.currentVersion;
        _latestVersion = result.release.version;
        _hasAvailableUpdate = result.hasUpdate;
        _updateUrl = result.desktopUpdateUrl;
        _updateStatus = result.hasUpdate
            ? result.isMandatory
                  ? 'Required update available for AniWings Desktop.'
                  : 'Update available for AniWings Desktop.'
            : 'AniWings Desktop is up to date.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasAvailableUpdate = false;
        _updateStatus =
            'Could not reach update server. Check network connection.';
      });
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  Future<void> _openUpdate() async {
    final targetUrl = _updateUrl.isNotEmpty
        ? _updateUrl
        : 'https://github.com/thehakaiben-cmyk/aniwings-app/releases';
    final uri = Uri.tryParse(targetUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _goBack(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return;
    }
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    router?.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return DesktopPageShell(
      onRootBack: () => _goBack(context),
      child: Scaffold(
        backgroundColor: AppColors.primaryBg,
        body: DesktopPageBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                DesktopPageHeader(
                  leading: DesktopBackButton(
                    focusNode: _backButtonFocusNode,
                    autofocus: true,
                    directionalKeyHandlers: {
                      LogicalKeyboardKey.arrowDown: () =>
                          _currentServerFocusNode.requestFocus(),
                    },
                    onPressed: () => _goBack(context),
                  ),
                  eyebrow: 'PLAYBACK',
                  title: 'Player settings',
                  subtitle:
                      'Streaming server, audio language, autoplay, and quality',
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      DesktopLayout.pagePadding(context),
                      8,
                      DesktopLayout.pagePadding(context),
                      40,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          children: [
                            // ─── 1. Streaming Server Setting ─────────────────
                            _buildSettingRow(
                              icon: Icons.dns_rounded,
                              title: 'Streaming Server',
                              description:
                                  'Choose default video streaming provider for anime playback',
                              optionsWidget: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildOptionPill(
                                      label: 'Gojo',
                                      badge: 'Default',
                                      isSelected:
                                          _defaultServer.toLowerCase() ==
                                          'gojo',
                                      focusNode: _serverGojoFocusNode,
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowUp: () =>
                                            _backButtonFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowDown: () =>
                                            _currentAudioFocusNode
                                                .requestFocus(),
                                        LogicalKeyboardKey.arrowLeft: () =>
                                            _backButtonFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowRight: () =>
                                            _serverKakashiFocusNode
                                                .requestFocus(),
                                      },
                                      onTap: () => _setServer('Gojo'),
                                    ),
                                    const SizedBox(width: 10),
                                    _buildOptionPill(
                                      label: 'Kakashi',
                                      isSelected:
                                          _defaultServer.toLowerCase() ==
                                          'kakashi',
                                      focusNode: _serverKakashiFocusNode,
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowUp: () =>
                                            _backButtonFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowDown: () =>
                                            _currentAudioFocusNode
                                                .requestFocus(),
                                        LogicalKeyboardKey.arrowLeft: () =>
                                            _serverGojoFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowRight: () =>
                                            _serverLuffyFocusNode
                                                .requestFocus(),
                                      },
                                      onTap: () => _setServer('Kakashi'),
                                    ),
                                    const SizedBox(width: 10),
                                    _buildOptionPill(
                                      label: 'Luffy',
                                      isSelected:
                                          _defaultServer.toLowerCase() ==
                                          'luffy',
                                      focusNode: _serverLuffyFocusNode,
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowUp: () =>
                                            _backButtonFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowDown: () =>
                                            _currentAudioFocusNode
                                                .requestFocus(),
                                        LogicalKeyboardKey.arrowLeft: () =>
                                            _serverKakashiFocusNode
                                                .requestFocus(),
                                        LogicalKeyboardKey.arrowRight: () =>
                                            _serverTanjiroFocusNode
                                                .requestFocus(),
                                      },
                                      onTap: () => _setServer('Luffy'),
                                    ),
                                    const SizedBox(width: 10),
                                    _buildOptionPill(
                                      label: 'Tanjiro',
                                      isSelected:
                                          _defaultServer.toLowerCase() ==
                                          'tanjiro',
                                      focusNode: _serverTanjiroFocusNode,
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowUp: () =>
                                            _backButtonFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowDown: () =>
                                            _currentAudioFocusNode
                                                .requestFocus(),
                                        LogicalKeyboardKey.arrowLeft: () =>
                                            _serverLuffyFocusNode
                                                .requestFocus(),
                                        LogicalKeyboardKey.arrowRight: () =>
                                            _serverLeviFocusNode.requestFocus(),
                                      },
                                      onTap: () => _setServer('Tanjiro'),
                                    ),
                                    const SizedBox(width: 10),
                                    _buildOptionPill(
                                      label: 'Levi',
                                      isSelected:
                                          _defaultServer.toLowerCase() ==
                                          'levi',
                                      focusNode: _serverLeviFocusNode,
                                      directionalKeyHandlers: {
                                        LogicalKeyboardKey.arrowUp: () =>
                                            _backButtonFocusNode.requestFocus(),
                                        LogicalKeyboardKey.arrowDown: () =>
                                            _currentAudioFocusNode
                                                .requestFocus(),
                                        LogicalKeyboardKey.arrowLeft: () =>
                                            _serverTanjiroFocusNode
                                                .requestFocus(),
                                      },
                                      onTap: () => _setServer('Levi'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ─── 2. Default Audio Language ───────────────────
                            _buildSettingRow(
                              icon: Icons.audiotrack_rounded,
                              title: 'Default Audio Language',
                              description:
                                  'Prioritize Japanese Subtitles or English Dubbing on startup',
                              optionsWidget: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildOptionPill(
                                    label: 'SUB',
                                    badge: 'Original JP',
                                    isSelected:
                                        _defaultAudio.toUpperCase() == 'SUB',
                                    focusNode: _audioSubFocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _currentServerFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowDown: () =>
                                          _currentAutoPlayFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _backButtonFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowRight: () =>
                                          _audioDubFocusNode.requestFocus(),
                                    },
                                    onTap: () => _setAudio('SUB'),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildOptionPill(
                                    label: 'DUB',
                                    badge: 'English',
                                    isSelected:
                                        _defaultAudio.toUpperCase() == 'DUB',
                                    focusNode: _audioDubFocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _currentServerFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowDown: () =>
                                          _currentAutoPlayFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _audioSubFocusNode.requestFocus(),
                                    },
                                    onTap: () => _setAudio('DUB'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ─── 3. Autoplay Next Episode ────────────────────
                            _buildSettingRow(
                              icon: Icons.play_circle_outline_rounded,
                              title: 'Autoplay Next Episode',
                              description:
                                  'Automatically load and stream the next episode when current finishes',
                              optionsWidget: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildOptionPill(
                                    label: 'Disabled',
                                    isSelected: !_autoPlayNext,
                                    focusNode: _autoPlayDisabledFocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _currentAudioFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowDown: () =>
                                          _currentQualityFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _backButtonFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowRight: () =>
                                          _autoPlayEnabledFocusNode
                                              .requestFocus(),
                                    },
                                    onTap: () => _setAutoPlayNext(false),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildOptionPill(
                                    label: 'Enabled',
                                    isSelected: _autoPlayNext,
                                    focusNode: _autoPlayEnabledFocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _currentAudioFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowDown: () =>
                                          _currentQualityFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _autoPlayDisabledFocusNode
                                              .requestFocus(),
                                    },
                                    onTap: () => _setAutoPlayNext(true),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ─── 4. Video Quality ────────────────────────────
                            _buildSettingRow(
                              icon: Icons.high_quality_rounded,
                              title: 'Video Quality',
                              description:
                                  'Default streaming resolution preference across all episodes',
                              optionsWidget: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildOptionPill(
                                    label: '1080p',
                                    isSelected: _quality == '1080p',
                                    focusNode: _quality1080FocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _currentAutoPlayFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowDown: () =>
                                          _subtitlesFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _backButtonFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowRight: () =>
                                          _quality720FocusNode.requestFocus(),
                                    },
                                    onTap: () => _setQuality('1080p'),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildOptionPill(
                                    label: '720p',
                                    isSelected: _quality == '720p',
                                    focusNode: _quality720FocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _currentAutoPlayFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowDown: () =>
                                          _subtitlesFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _quality1080FocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowRight: () =>
                                          _quality480FocusNode.requestFocus(),
                                    },
                                    onTap: () => _setQuality('720p'),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildOptionPill(
                                    label: '480p',
                                    isSelected: _quality == '480p',
                                    focusNode: _quality480FocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _currentAutoPlayFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowDown: () =>
                                          _subtitlesFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _quality720FocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowRight: () =>
                                          _qualityAutoFocusNode.requestFocus(),
                                    },
                                    onTap: () => _setQuality('480p'),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildOptionPill(
                                    label: 'Auto',
                                    isSelected:
                                        _quality.toLowerCase() == 'auto',
                                    focusNode: _qualityAutoFocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _currentAutoPlayFocusNode
                                              .requestFocus(),
                                      LogicalKeyboardKey.arrowDown: () =>
                                          _subtitlesFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _quality480FocusNode.requestFocus(),
                                    },
                                    onTap: () => _setQuality('auto'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ─── 5. Subtitle Appearance Shortcut ─────────────
                            _buildSettingRow(
                              icon: Icons.subtitles_outlined,
                              title: 'Subtitle Appearance',
                              description:
                                  'Configure subtitle font, size, typography, colors, and positioning',
                              optionsWidget: SizedBox(
                                height: 38,
                                child: DesktopFocusWrapper.builder(
                                  focusNode: _subtitlesFocusNode,
                                  directionalKeyHandlers: {
                                    LogicalKeyboardKey.arrowUp: () =>
                                        _currentQualityFocusNode.requestFocus(),
                                    LogicalKeyboardKey.arrowDown: () =>
                                        _updatesFocusNode.requestFocus(),
                                    LogicalKeyboardKey.arrowLeft: () =>
                                        _backButtonFocusNode.requestFocus(),
                                  },
                                  borderRadius: AppRadii.control,
                                  onTap: () =>
                                      context.push('/subtitle-settings'),
                                  builder: (context, isFocused, isHovered) {
                                    final active = isFocused || isHovered;
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 140,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? AppColors.hoverState
                                            : AppColors.elevatedSurface,
                                        borderRadius: AppRadii.control,
                                        border: Border.all(
                                          color: isFocused
                                              ? Colors.white
                                              : (active
                                                    ? AppColors.border
                                                    : AppColors.borderSubtle),
                                          width: isFocused ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Customize Subtitles',
                                            style: TextStyle(
                                              color: active
                                                  ? Colors.white
                                                  : AppColors.textPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 15,
                                            color: active
                                                ? Colors.white
                                                : AppColors.brandRed,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ─── 6. Application Updates Row ──────────────────
                            KeyedSubtree(
                              key: const ValueKey('player-update-settings'),
                              child: _buildSettingRow(
                                icon: Icons.system_update_rounded,
                                title: 'Application Updates',
                                description:
                                    'Installed: v${AppUpdateService.displayVersion(_currentVersion)}  •  $_updateStatus',
                                optionsWidget: SizedBox(
                                  height: 38,
                                  child: DesktopFocusWrapper.builder(
                                    focusNode: _updatesFocusNode,
                                    directionalKeyHandlers: {
                                      LogicalKeyboardKey.arrowUp: () =>
                                          _subtitlesFocusNode.requestFocus(),
                                      LogicalKeyboardKey.arrowLeft: () =>
                                          _backButtonFocusNode.requestFocus(),
                                    },
                                    borderRadius: AppRadii.control,
                                    onTap: _hasAvailableUpdate
                                        ? _openUpdate
                                        : _checkForUpdate,
                                    builder: (context, isFocused, isHovered) {
                                      final active = isFocused || isHovered;
                                      final isUpdateReady = _hasAvailableUpdate;
                                      return AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 140,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isUpdateReady
                                              ? AppColors.brandRed
                                              : (active
                                                    ? AppColors.hoverState
                                                    : AppColors
                                                          .elevatedSurface),
                                          borderRadius: AppRadii.control,
                                          border: Border.all(
                                            color: isFocused
                                                ? Colors.white
                                                : (isUpdateReady
                                                      ? AppColors.brandRed
                                                      : (active
                                                            ? AppColors.border
                                                            : AppColors
                                                                  .borderSubtle)),
                                            width: isFocused ? 1.5 : 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_isCheckingUpdate) ...[
                                              const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              ),
                                              const SizedBox(width: 8),
                                            ] else ...[
                                              Icon(
                                                isUpdateReady
                                                    ? Icons.download_rounded
                                                    : Icons.refresh_rounded,
                                                size: 15,
                                                color: isUpdateReady
                                                    ? Colors.white
                                                    : (active
                                                          ? Colors.white
                                                          : AppColors
                                                                .textSecondary),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            Text(
                                              isUpdateReady
                                                  ? 'Download Update (${AppUpdateService.displayVersion(_latestVersion)})'
                                                  : (_isCheckingUpdate
                                                        ? 'Checking...'
                                                        : 'Check for Updates'),
                                              style: TextStyle(
                                                color: isUpdateReady || active
                                                    ? Colors.white
                                                    : AppColors.textPrimary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
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

  /// Full-width setting card:
  /// Left side: Icon, Title, and Description
  /// Right side: Interactive change options aligned cleanly
  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String description,
    required Widget optionsWidget,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.borderSubtle, width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left Side: Title & About ──────────────────────────────────────
          Expanded(
            flex: 5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.brandRed.withValues(alpha: 0.15),
                    borderRadius: AppRadii.control,
                    border: Border.all(
                      color: AppColors.brandRed.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: Icon(icon, color: AppColors.brandRed, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // ── Right Side: Change Options ────────────────────────────────────
          Flexible(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child: optionsWidget,
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive option pill for choice selection
  Widget _buildOptionPill({
    required String label,
    String? badge,
    required bool isSelected,
    required VoidCallback onTap,
    FocusNode? focusNode,
    Map<LogicalKeyboardKey, VoidCallback> directionalKeyHandlers = const {},
  }) {
    return SizedBox(
      height: 36,
      child: DesktopFocusWrapper.builder(
        focusNode: focusNode,
        directionalKeyHandlers: directionalKeyHandlers,
        borderRadius: AppRadii.control,
        onTap: onTap,
        builder: (context, isFocused, isHovered) {
          final active = isFocused || isHovered;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.brandRed
                  : (active ? AppColors.hoverState : AppColors.elevatedSurface),
              borderRadius: AppRadii.control,
              border: Border.all(
                color: isFocused
                    ? Colors.white
                    : (isSelected
                          ? AppColors.brandRed
                          : (active
                                ? AppColors.border
                                : AppColors.borderSubtle)),
                width: isFocused ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected || active
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : AppColors.surface,
                      borderRadius: AppRadii.control,
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
