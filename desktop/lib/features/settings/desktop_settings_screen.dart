import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../services/desktop_preferences.dart';
import '../../services/metadata_provider_service.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/desktop_update_dialog.dart';
import '../../widgets/social_follow_dialog.dart';

/// AniWings Desktop — Settings & Personalization Hub.
class DesktopSettingsScreen extends ConsumerStatefulWidget {
  const DesktopSettingsScreen({super.key});

  @override
  ConsumerState<DesktopSettingsScreen> createState() =>
      _DesktopSettingsScreenState();
}

class _DesktopSettingsScreenState extends ConsumerState<DesktopSettingsScreen> {
  late final ScrollController _scrollController;
  int _activeCategoryIndex = 0;

  // Settings values
  late String _defaultServer;
  late String _defaultAudio;
  late bool _autoPlayNext;
  late String _quality;
  late String _cardSize;
  late bool _skipIntroEnabled;
  late bool _autoSkipIntroOutro;
  late String _dnsMode;

  static const String _discordUrl = 'https://discord.gg/5WBhW723uB';
  static const String _telegramUrl = 'https://t.me/aniwings_community';
  static const String _redditUrl =
      'https://www.reddit.com/r/AniWings_Official/';
  static const String _supportEmail = 'wingsofficial750@gmail.com';

  static const List<String> _categories = [
    'Playback',
    'Appearance',
    'Keyboard Shortcuts',
    'Data & Cache',
    'Account & Profile',
    'Metadata Provider',
    'Community & Support',
    'Downloads',
  ];

  // Category FocusNodes (Left Sidebar)
  late final List<FocusNode> _categoryFocusNodes;

  // Playback Category FocusNodes
  final FocusNode _autoNextNode = FocusNode(debugLabel: 'AutoNext');
  final Map<String, FocusNode> _serverNodes = {
    'Gojo': FocusNode(debugLabel: 'Server-Gojo'),
    'Kakashi': FocusNode(debugLabel: 'Server-Kakashi'),
    'Luffy': FocusNode(debugLabel: 'Server-Luffy'),
    'Tanjiro': FocusNode(debugLabel: 'Server-Tanjiro'),
    'Levi': FocusNode(debugLabel: 'Server-Levi'),
  };
  final Map<String, FocusNode> _audioNodes = {
    'SUB': FocusNode(debugLabel: 'Audio-SUB'),
    'DUB': FocusNode(debugLabel: 'Audio-DUB'),
  };
  final Map<String, FocusNode> _dnsNodes = {
    'Off': FocusNode(debugLabel: 'Dns-Off'),
    '1.1.1.1': FocusNode(debugLabel: 'Dns-1.1.1.1'),
    '8.8.8.8': FocusNode(debugLabel: 'Dns-8.8.8.8'),
    '9.9.9.9': FocusNode(debugLabel: 'Dns-9.9.9.9'),
  };
  final Map<String, FocusNode> _qualityNodes = {
    '1080p': FocusNode(debugLabel: 'Quality-1080p'),
    '720p': FocusNode(debugLabel: 'Quality-720p'),
    '480p': FocusNode(debugLabel: 'Quality-480p'),
    'Auto': FocusNode(debugLabel: 'Quality-Auto'),
  };
  final FocusNode _skipIntroNode = FocusNode(debugLabel: 'SkipIntro');
  final FocusNode _autoSkipIntroOutroNode = FocusNode(
    debugLabel: 'AutoSkipIntroOutro',
  );
  final FocusNode _subtitleSettingsNode = FocusNode(
    debugLabel: 'SubtitleSettings',
  );

  // Appearance Category FocusNodes
  final Map<String, FocusNode> _cardSizeNodes = {
    'standard': FocusNode(debugLabel: 'CardSize-standard'),
    'compact': FocusNode(debugLabel: 'CardSize-compact'),
    'spacious': FocusNode(debugLabel: 'CardSize-spacious'),
  };

  // Data Category FocusNodes
  final FocusNode _clearSearchNode = FocusNode(debugLabel: 'ClearSearch');
  final FocusNode _flushCacheNode = FocusNode(debugLabel: 'FlushCache');
  final FocusNode _checkUpdateNode = FocusNode(debugLabel: 'CheckUpdate');

  // Account Category FocusNodes
  final FocusNode _accountActionNode = FocusNode(debugLabel: 'AccountAction');
  final FocusNode _manualLoginNode = FocusNode(debugLabel: 'ManualLogin');
  final FocusNode _logoutActionNode = FocusNode(debugLabel: 'LogoutAction');
  final _metadataNodes = {
    MetadataProvider.myAnimeList: FocusNode(debugLabel: 'Metadata-MyAnimeList'),
    MetadataProvider.aniList: FocusNode(debugLabel: 'Metadata-AniList'),
  };

  // Community Category FocusNodes
  final FocusNode _communityDiscordNode = FocusNode(
    debugLabel: 'CommunityDiscord',
  );
  final FocusNode _communityTelegramNode = FocusNode(
    debugLabel: 'CommunityTelegram',
  );
  final FocusNode _communityRedditNode = FocusNode(
    debugLabel: 'CommunityReddit',
  );
  final FocusNode _communityEmailNode = FocusNode(debugLabel: 'CommunityEmail');
  final FocusNode _communityPopupNode = FocusNode(debugLabel: 'CommunityPopup');
  final FocusNode _communityFaqNode = FocusNode(debugLabel: 'CommunityFaq');

  final FocusNode _downloadSettingsNode = FocusNode(
    debugLabel: 'DownloadSettings',
  );
  bool _savingMetadata = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _categoryFocusNodes = List.generate(
      _categories.length,
      (i) => FocusNode(debugLabel: 'Category-$i'),
    );
    _loadSettings();
  }

  void _loadSettings() {
    final storage = ref.read(storageServiceProvider);
    _defaultServer = storage.getDefaultServerPreference();
    _defaultAudio = storage.getDefaultAudioPreference();
    _autoPlayNext = storage.getAutoPlayNext();
    _quality = storage.getVideoQualityPreference();
    _cardSize = storage.getCardSizePreference();
    _skipIntroEnabled = storage.getSkipIntroEnabled();
    _autoSkipIntroOutro = storage.getAutoSkipIntroOutro();
    _dnsMode = storage.getDnsModePreference();
  }

  Future<void> _launchExternalUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error launching URL ($urlString): $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final node in _categoryFocusNodes) {
      node.dispose();
    }
    _autoNextNode.dispose();
    for (final node in _serverNodes.values) {
      node.dispose();
    }
    for (final node in _audioNodes.values) {
      node.dispose();
    }
    for (final node in _dnsNodes.values) {
      node.dispose();
    }
    for (final node in _qualityNodes.values) {
      node.dispose();
    }
    _skipIntroNode.dispose();
    _autoSkipIntroOutroNode.dispose();
    _subtitleSettingsNode.dispose();
    for (final node in _cardSizeNodes.values) {
      node.dispose();
    }
    _clearSearchNode.dispose();
    _flushCacheNode.dispose();
    _checkUpdateNode.dispose();
    _accountActionNode.dispose();
    _manualLoginNode.dispose();
    _logoutActionNode.dispose();
    for (final node in _metadataNodes.values) {
      node.dispose();
    }
    _communityDiscordNode.dispose();
    _communityTelegramNode.dispose();
    _communityRedditNode.dispose();
    _communityEmailNode.dispose();
    _communityPopupNode.dispose();
    _communityFaqNode.dispose();
    _downloadSettingsNode.dispose();
    super.dispose();
  }

  void _focusCategoryContent(int index) {
    switch (index) {
      case 0:
        _autoNextNode.requestFocus();
        break;
      case 1:
        (_cardSizeNodes[_cardSize] ?? _cardSizeNodes['standard'])
            ?.requestFocus();
        break;
      case 2:
        // Keyboard Shortcuts reference table
        break;
      case 3:
        _clearSearchNode.requestFocus();
        break;
      case 4:
        _accountActionNode.requestFocus();
        break;
      case 5:
        _metadataNodes[ref.read(metadataProviderPreference)]!.requestFocus();
        break;
      case 6:
        _communityDiscordNode.requestFocus();
        break;
      case 7:
        _downloadSettingsNode.requestFocus();
        break;
    }
  }

  void _openCategory(int index) {
    setState(() => _activeCategoryIndex = index);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _checkUpdates() async {
    showDesktopUpdateDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageServiceProvider);
    final user = ref.watch(authStateProvider);

    final leftPadding = DesktopLayout.pageLeftPadding(context);
    final rightPadding = DesktopLayout.pagePadding(context);

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(leftPadding, 24, rightPadding, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _buildHeader(),

                  const SizedBox(height: 24),

                  // Split view: Left category selector + Right settings panel
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Categories List
                        SizedBox(
                          width: 224,
                          child: ListView.separated(
                            itemCount: _categories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final cat = _categories[index];
                              final isSelected = _activeCategoryIndex == index;
                              final icon = switch (index) {
                                0 => Icons.play_circle_outline_rounded,
                                1 => Icons.palette_outlined,
                                2 => Icons.keyboard_rounded,
                                3 => Icons.storage_rounded,
                                4 => Icons.account_circle_outlined,
                                5 => Icons.hub_outlined,
                                6 => Icons.groups_outlined,
                                7 => Icons.download_outlined,
                                _ => Icons.settings_outlined,
                              };

                              return DesktopFocusWrapper.builder(
                                focusNode: _categoryFocusNodes[index],
                                autofocus: index == 0,
                                onTap: () {
                                  _categoryFocusNodes[index].requestFocus();
                                  _openCategory(index);
                                },
                                directionalKeyHandlers: {
                                  LogicalKeyboardKey.arrowUp: () =>
                                      _categoryFocusNodes[(index - 1).clamp(
                                            0,
                                            _categories.length - 1,
                                          )]
                                          .requestFocus(),
                                  LogicalKeyboardKey.arrowDown: () =>
                                      _categoryFocusNodes[(index + 1).clamp(
                                            0,
                                            _categories.length - 1,
                                          )]
                                          .requestFocus(),
                                  LogicalKeyboardKey.arrowRight: () {
                                    _openCategory(index);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted) {
                                            _focusCategoryContent(index);
                                          }
                                        });
                                  },
                                },
                                borderRadius: AppRadii.control,
                                builder: (context, isFocused, isHovered) {
                                  final active = isFocused || isHovered;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.activeState
                                          : (active
                                                ? AppColors.hoverState
                                                : Colors.transparent),
                                      borderRadius: AppRadii.control,
                                      border: Border.all(
                                        color: isFocused
                                            ? Colors.white
                                            : (isSelected
                                                  ? AppColors.borderStrong
                                                  : (active
                                                        ? AppColors.border
                                                        : Colors.transparent)),
                                        width: isFocused ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          icon,
                                          size: 18,
                                          color: isSelected
                                              ? AppColors.brandRed
                                              : (active
                                                    ? Colors.white
                                                    : AppColors.textSecondary),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            cat,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isSelected || active
                                                  ? Colors.white
                                                  : AppColors.textSecondary,
                                              fontSize: 13,
                                              fontWeight: isSelected || active
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            width: 5,
                                            height: 5,
                                            decoration: const BoxDecoration(
                                              color: AppColors.brandRed,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 24),

                        // Right Category Panel
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildCategoryContent(
                                      categoryIndex: _activeCategoryIndex,
                                      storage: storage,
                                      user: user,
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.only(
                                        top: 40,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        '🛠️ Crafted by Cosmic Garou',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings & Customization',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Make AniWings work the way you watch. Changes are saved automatically.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
        const Text(
          'AniWings Desktop  /  1.2.5',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCategoryContent({
    required int categoryIndex,
    required StorageService storage,
    required dynamic user,
  }) {
    switch (categoryIndex) {
      case 0:
        return _buildPlaybackSection(storage);
      case 1:
        return _buildAppearanceSection(storage);
      case 2:
        return _buildKeyboardShortcutsSection();
      case 3:
        return _buildDataSection(storage);
      case 4:
        return _buildAccountSection(storage, user);
      case 5:
        return _buildMetadataSection();
      case 6:
        return _buildCommunityAndSupportSection(storage);
      case 7:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Downloads & Offline',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Choose download quality, audio language and storage location. Manage your queue and watch completed episodes offline.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              focusNode: _downloadSettingsNode,
              onPressed: () => context.push('/download-settings'),
              icon: const Icon(Icons.settings),
              label: const Text('Download settings'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/downloads'),
              icon: const Icon(Icons.download_done),
              label: const Text('Open downloads'),
            ),
            TextButton.icon(
              onPressed: () => context.push('/support'),
              icon: const Icon(Icons.help_outline),
              label: const Text('Download FAQs'),
            ),
          ],
        );
      default:
        return _buildPlaybackSection(storage);
    }
  }

  // 1. Appearance Section
  Widget _buildMetadataSection() {
    final selected = ref.watch(metadataProviderPreference);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Metadata provider',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Choose the catalog used across Home, Browse, Search, Details and episode information.',
          style: TextStyle(color: Colors.white60, fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 24),
        for (final provider in MetadataProvider.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DesktopFocusWrapper.builder(
              focusNode: _metadataNodes[provider],
              canRequestFocus: !_savingMetadata,
              focusedScale: 1,
              debugLabel: provider.label,
              directionalKeyHandlers: {
                LogicalKeyboardKey.arrowLeft: () =>
                    _categoryFocusNodes[5].requestFocus(),
                LogicalKeyboardKey.arrowDown: () =>
                    _metadataNodes[MetadataProvider.aniList]!.requestFocus(),
                LogicalKeyboardKey.arrowUp: () =>
                    _metadataNodes[MetadataProvider.myAnimeList]!
                        .requestFocus(),
              },
              onTap: _savingMetadata
                  ? null
                  : () async {
                      setState(() => _savingMetadata = true);
                      try {
                        await ref
                            .read(metadataProviderPreference.notifier)
                            .select(provider);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${provider.label} selected. All metadata pages refresh automatically.',
                              ),
                            ),
                          );
                        }
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not save the metadata provider. Try again.',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _savingMetadata = false);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _metadataNodes[provider]!.requestFocus();
                            }
                          });
                        }
                      }
                    },
              builder: (_, focused, hovered) => AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: focused
                      ? AppColors.hoverState
                      : (selected == provider
                            ? AppColors.activeState
                            : AppColors.secondaryBg),
                  borderRadius: AppRadii.card,
                  border: Border.all(
                    color: focused
                        ? Colors.white
                        : (selected == provider
                              ? AppColors.brandRed
                              : AppColors.borderSubtle),
                    width: focused ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: provider == MetadataProvider.aniList
                            ? const Color(0xFF02A9FF).withValues(alpha: 0.15)
                            : const Color(0xFF2E51A2).withValues(alpha: 0.15),
                        borderRadius: AppRadii.control,
                        border: Border.all(
                          color: provider == MetadataProvider.aniList
                              ? const Color(0xFF02A9FF).withValues(alpha: 0.4)
                              : const Color(0xFF2E51A2).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        provider == MetadataProvider.aniList ? 'AL' : 'MAL',
                        style: TextStyle(
                          color: provider == MetadataProvider.aniList
                              ? const Color(0xFF02A9FF)
                              : const Color(0xFF4D78E0),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            provider == MetadataProvider.aniList
                                ? 'AniList catalog, artwork and airing data'
                                : 'MAL catalog and episode titles via Jikan',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      selected == provider
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected == provider
                          ? AppColors.brandRed
                          : AppColors.textMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Text(
          'If a provider is unavailable, choose the other here. Your watchlist and viewing progress stay with the same title IDs.',
          style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 12),
        const Text(
          'AniList episode titles and thumbnails appear when supplied by the catalog. Other released episodes use numbered labels. Video servers are selected separately in Playback.',
          style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildAppearanceSection(StorageService storage) {
    final cardSizes = const ['standard', 'compact', 'spacious'];
    final cardSizeHandlers = <String, Map<LogicalKeyboardKey, VoidCallback>>{};
    for (int i = 0; i < cardSizes.length; i++) {
      final s = cardSizes[i];
      cardSizeHandlers[s] = {
        LogicalKeyboardKey.arrowLeft: () {
          if (i == 0) {
            _categoryFocusNodes[1].requestFocus();
          } else {
            _cardSizeNodes[cardSizes[i - 1]]?.requestFocus();
          }
        },
        if (i < cardSizes.length - 1)
          LogicalKeyboardKey.arrowRight: () {
            _cardSizeNodes[cardSizes[i + 1]]?.requestFocus();
          },
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appearance & Layout',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Customize visual density and brand presentation for your desktop display.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),

        _buildSettingOptionTile(
          title: 'Card Sizing',
          subtitle:
              'Choose between compact rows or spacious poster presentations.',
          options: cardSizes,
          selected: _cardSize,
          focusNodes: _cardSizeNodes,
          directionalHandlers: cardSizeHandlers,
          onSelected: (val) async {
            setState(() => _cardSize = val);
            await ref.read(desktopDensityProvider.notifier).select(val);
          },
        ),

        const SizedBox(height: 12),

        const ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16),
          title: Text('Desktop theme'),
          subtitle: Text(
            'Charcoal surfaces, a red accent and system typography.',
          ),
          trailing: Icon(Icons.desktop_windows_outlined),
        ),
      ],
    );
  }

  // 2. Playback Section
  Widget _buildPlaybackSection(StorageService storage) {
    final serverList = const ['Gojo', 'Kakashi', 'Luffy', 'Tanjiro', 'Levi'];
    final audioList = const ['SUB', 'DUB'];
    final dnsList = const ['Off', '1.1.1.1', '8.8.8.8', '9.9.9.9'];
    final qualityList = const ['1080p', '720p', '480p', 'Auto'];

    // Key handlers for AutoNext
    final autoNextHandlers = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.arrowLeft: () => _categoryFocusNodes[0].requestFocus(),
      LogicalKeyboardKey.arrowDown: () {
        final node = _serverNodes[_defaultServer] ?? _serverNodes['Gojo'];
        node?.requestFocus();
      },
    };

    // Key handlers for Servers
    final serverHandlers = <String, Map<LogicalKeyboardKey, VoidCallback>>{};
    for (int i = 0; i < serverList.length; i++) {
      final s = serverList[i];
      serverHandlers[s] = {
        LogicalKeyboardKey.arrowUp: () => _autoNextNode.requestFocus(),
        LogicalKeyboardKey.arrowDown: () {
          final node = _audioNodes[_defaultAudio] ?? _audioNodes['SUB'];
          node?.requestFocus();
        },
        LogicalKeyboardKey.arrowLeft: () {
          if (i == 0) {
            _categoryFocusNodes[0].requestFocus();
          } else {
            _serverNodes[serverList[i - 1]]?.requestFocus();
          }
        },
        if (i < serverList.length - 1)
          LogicalKeyboardKey.arrowRight: () {
            _serverNodes[serverList[i + 1]]?.requestFocus();
          },
      };
    }

    // Key handlers for Audio
    final audioHandlers = <String, Map<LogicalKeyboardKey, VoidCallback>>{};
    for (int i = 0; i < audioList.length; i++) {
      final a = audioList[i];
      audioHandlers[a] = {
        LogicalKeyboardKey.arrowUp: () {
          final node = _serverNodes[_defaultServer] ?? _serverNodes['Gojo'];
          node?.requestFocus();
        },
        LogicalKeyboardKey.arrowDown: () {
          final node = _dnsNodes[_dnsMode] ?? _dnsNodes['Off'];
          node?.requestFocus();
        },
        LogicalKeyboardKey.arrowLeft: () {
          if (i == 0) {
            _categoryFocusNodes[0].requestFocus();
          } else {
            _audioNodes[audioList[i - 1]]?.requestFocus();
          }
        },
        if (i < audioList.length - 1)
          LogicalKeyboardKey.arrowRight: () {
            _audioNodes[audioList[i + 1]]?.requestFocus();
          },
      };
    }

    // Key handlers for DNS
    final dnsHandlers = <String, Map<LogicalKeyboardKey, VoidCallback>>{};
    for (int i = 0; i < dnsList.length; i++) {
      final d = dnsList[i];
      dnsHandlers[d] = {
        LogicalKeyboardKey.arrowUp: () {
          final node = _audioNodes[_defaultAudio] ?? _audioNodes['SUB'];
          node?.requestFocus();
        },
        LogicalKeyboardKey.arrowDown: () {
          final node = _qualityNodes[_quality] ?? _qualityNodes['1080p'];
          node?.requestFocus();
        },
        LogicalKeyboardKey.arrowLeft: () {
          if (i == 0) {
            _categoryFocusNodes[0].requestFocus();
          } else {
            _dnsNodes[dnsList[i - 1]]?.requestFocus();
          }
        },
        if (i < dnsList.length - 1)
          LogicalKeyboardKey.arrowRight: () {
            _dnsNodes[dnsList[i + 1]]?.requestFocus();
          },
      };
    }

    // Key handlers for Quality
    final qualityHandlers = <String, Map<LogicalKeyboardKey, VoidCallback>>{};
    for (int i = 0; i < qualityList.length; i++) {
      final q = qualityList[i];
      qualityHandlers[q] = {
        LogicalKeyboardKey.arrowUp: () {
          final node = _dnsNodes[_dnsMode] ?? _dnsNodes['Off'];
          node?.requestFocus();
        },
        LogicalKeyboardKey.arrowDown: () => _skipIntroNode.requestFocus(),
        LogicalKeyboardKey.arrowLeft: () {
          if (i == 0) {
            _categoryFocusNodes[0].requestFocus();
          } else {
            _qualityNodes[qualityList[i - 1]]?.requestFocus();
          }
        },
        if (i < qualityList.length - 1)
          LogicalKeyboardKey.arrowRight: () {
            _qualityNodes[qualityList[i + 1]]?.requestFocus();
          },
      };
    }

    // Key handlers for Skip Intro
    final skipIntroHandlers = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.arrowLeft: () => _categoryFocusNodes[0].requestFocus(),
      LogicalKeyboardKey.arrowUp: () {
        final node = _qualityNodes[_quality] ?? _qualityNodes['1080p'];
        node?.requestFocus();
      },
      LogicalKeyboardKey.arrowDown: () =>
          _autoSkipIntroOutroNode.requestFocus(),
    };

    // Key handlers for Auto Skip Intro & Outro
    final autoSkipHandlers = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.arrowLeft: () => _categoryFocusNodes[0].requestFocus(),
      LogicalKeyboardKey.arrowUp: () => _skipIntroNode.requestFocus(),
      LogicalKeyboardKey.arrowDown: () => _subtitleSettingsNode.requestFocus(),
    };

    // Key handlers for Subtitle Settings
    final subtitleHandlers = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.arrowLeft: () => _categoryFocusNodes[0].requestFocus(),
      LogicalKeyboardKey.arrowUp: () => _autoSkipIntroOutroNode.requestFocus(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Video Playback',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Configure server resolution, autoplay, and audio track preferences.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // 1. Autoplay Next
        _buildToggleTile(
          focusNode: _autoNextNode,
          directionalKeyHandlers: autoNextHandlers,
          title: 'Auto Next Episode',
          subtitle:
              'Automatically advance and countdown to the next episode upon completion.',
          value: _autoPlayNext,
          onChanged: (val) async {
            setState(() => _autoPlayNext = val);
            await storage.setAutoPlayNext(val);
          },
        ),

        const Divider(
          color: AppColors.borderSubtle,
          height: 16,
          thickness: 1.0,
        ),

        // 2. Default Server
        _buildSettingOptionTile(
          title: 'Default Streaming Server',
          subtitle:
              'Select preferred CDN streaming provider (Gojo recommended for fast native HLS).',
          options: serverList,
          selected: _defaultServer,
          focusNodes: _serverNodes,
          directionalHandlers: serverHandlers,
          onSelected: (val) async {
            setState(() => _defaultServer = val);
            await storage.setDefaultServerPreference(val);
          },
        ),

        const Divider(
          color: AppColors.borderSubtle,
          height: 16,
          thickness: 1.0,
        ),

        // 3. Audio Preference
        _buildSettingOptionTile(
          title: 'Audio Preference',
          subtitle:
              'Original Japanese audio with English subtitles or English Dub.',
          options: audioList,
          selected: _defaultAudio,
          focusNodes: _audioNodes,
          directionalHandlers: audioHandlers,
          onSelected: (val) async {
            setState(() => _defaultAudio = val);
            await storage.setDefaultAudioPreference(val);
          },
        ),

        const Divider(
          color: AppColors.borderSubtle,
          height: 16,
          thickness: 1.0,
        ),

        // 4. Secure DNS Mode (DoH)
        _buildSettingOptionTile(
          title: 'Secure DNS Mode (DoH)',
          subtitle:
              'Private DNS over HTTPS resolver. Defaults to Off (system default ISP routing).',
          options: dnsList,
          selected: _dnsMode,
          focusNodes: _dnsNodes,
          directionalHandlers: dnsHandlers,
          onSelected: (val) async {
            setState(() => _dnsMode = val);
            await storage.setDnsModePreference(val);
          },
        ),

        const Divider(
          color: AppColors.borderSubtle,
          height: 16,
          thickness: 1.0,
        ),

        // 5. Video Quality
        _buildSettingOptionTile(
          title: 'Preferred Video Quality',
          subtitle: 'Choose target resolution for native streams.',
          options: qualityList,
          selected: _quality,
          focusNodes: _qualityNodes,
          directionalHandlers: qualityHandlers,
          onSelected: (val) async {
            setState(() => _quality = val);
            await storage.setVideoQualityPreference(val);
          },
        ),

        const Divider(
          color: AppColors.borderSubtle,
          height: 16,
          thickness: 1.0,
        ),

        // 6. Skip Intro
        _buildToggleTile(
          focusNode: _skipIntroNode,
          directionalKeyHandlers: skipIntroHandlers,
          title: 'Show skip buttons',
          subtitle:
              'Show intro and outro buttons when verified episode timings are available.',
          value: _skipIntroEnabled,
          onChanged: (val) async {
            setState(() => _skipIntroEnabled = val);
            await storage.setSkipIntroEnabled(val);
          },
        ),

        const Divider(
          color: AppColors.borderSubtle,
          height: 16,
          thickness: 1.0,
        ),

        // 7. Auto-Skip Intro & Outro
        _buildToggleTile(
          focusNode: _autoSkipIntroOutroNode,
          directionalKeyHandlers: autoSkipHandlers,
          title: 'Auto-Skip Intro & Outro',
          subtitle:
              'Automatically skip opening and ending theme songs during playback.',
          value: _autoSkipIntroOutro,
          onChanged: (val) async {
            setState(() => _autoSkipIntroOutro = val);
            await storage.setAutoSkipIntroOutro(val);
          },
        ),

        const Divider(
          color: AppColors.borderSubtle,
          height: 16,
          thickness: 1.0,
        ),

        // 8. Subtitle Settings link
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subtitle Appearance',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Text sizing, border shadows, and caption styling.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            DesktopFocusWrapper(
              focusNode: _subtitleSettingsNode,
              directionalKeyHandlers: subtitleHandlers,
              borderRadius: AppRadii.control,
              onTap: () => context.push('/subtitle-settings'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.elevatedSurface,
                  borderRadius: AppRadii.control,
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: const Text(
                  'Customize',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 3. Desktop Keyboard Shortcuts Section
  Widget _buildKeyboardShortcutsSection() {
    const shortcutGroups = [
      (
        category: 'Global & Navigation',
        shortcuts: [
          (
            'Ctrl + K / Cmd + K',
            'Quick jump to Search bar from anywhere in the app',
          ),
          ('Escape', 'Go back, exit dialogs, or clear search field'),
          ('Enter / Space', 'Open or activate focused anime card or episode'),
          ('Arrow Keys (← ↑ → ↓)', 'Navigate cards, shelves, and options'),
        ],
      ),
      (
        category: 'Media Player Controls',
        shortcuts: [
          ('Space', 'Toggle Play / Pause instantly'),
          ('F', 'Toggle edge-to-edge fullscreen playback'),
          ('M', 'Mute or unmute playback audio'),
          ('← (Left Arrow)', 'Seek backward by 10 seconds'),
          ('→ (Right Arrow)', 'Seek forward by 10 seconds'),
          ('↑ (Up Arrow)', 'Increase volume by 5%'),
          ('↓ (Down Arrow)', 'Decrease volume by 5%'),
        ],
      ),
      (
        category: 'Mouse Interactions',
        shortcuts: [
          (
            'Right-Click Card',
            'Open context menu: Play, Details, Add/Remove List, Copy Title',
          ),
          ('Double-Click Video', 'Toggle edge-to-edge fullscreen playback'),
          ('Single Click Video', 'Toggle Play / Pause'),
          ('Hover on Card', 'Subtle 1.025x elevation and metadata highlight'),
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Desktop Keyboard Shortcuts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Quick reference for keybindings, media controls, and mouse gestures.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),

        for (final group in shortcutGroups) ...[
          Text(
            group.category.toUpperCase(),
            style: const TextStyle(
              color: AppColors.accentPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.secondaryBg,
              borderRadius: AppRadii.card,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < group.shortcuts.length; i++) ...[
                  if (i > 0)
                    const Divider(color: AppColors.borderSubtle, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.elevatedSurface,
                            borderRadius: AppRadii.control,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            group.shortcuts[i].$1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            group.shortcuts[i].$2,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  // 4. Data & Cache Section
  Widget _buildDataSection(StorageService storage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Data & Cache Management',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Clear local search histories, image cache, or sync states.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),

        _buildActionTile(
          focusNode: _clearSearchNode,
          directionalKeyHandlers: {
            LogicalKeyboardKey.arrowLeft: () =>
                _categoryFocusNodes[3].requestFocus(),
            LogicalKeyboardKey.arrowDown: () => _flushCacheNode.requestFocus(),
          },
          title: 'Clear Search History',
          subtitle: 'Removes recent query chips from the search screen.',
          buttonLabel: 'Clear Searches',
          onTap: () async {
            await storage.clearSearchHistory();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Search history cleared.')),
            );
          },
        ),

        const SizedBox(height: 12),

        _buildActionTile(
          focusNode: _flushCacheNode,
          directionalKeyHandlers: {
            LogicalKeyboardKey.arrowLeft: () =>
                _categoryFocusNodes[3].requestFocus(),
            LogicalKeyboardKey.arrowUp: () => _clearSearchNode.requestFocus(),
            LogicalKeyboardKey.arrowDown: () => _checkUpdateNode.requestFocus(),
          },
          title: 'Flush Image Memory Cache',
          subtitle: 'Free memory and disk image cache on your desktop system.',
          buttonLabel: 'Flush Cache',
          onTap: () {
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Image memory cache flushed.')),
              );
            }
          },
        ),

        const SizedBox(height: 12),

        _buildActionTile(
          focusNode: _checkUpdateNode,
          directionalKeyHandlers: {
            LogicalKeyboardKey.arrowLeft: () =>
                _categoryFocusNodes[3].requestFocus(),
            LogicalKeyboardKey.arrowUp: () => _flushCacheNode.requestFocus(),
          },
          title: 'Check Application Updates',
          subtitle:
              'View release notes, check for new builds, and update AniWings Desktop.',
          buttonLabel: 'Check for Updates',
          onTap: _checkUpdates,
        ),
      ],
    );
  }

  // 5. Account & Profile Section
  Widget _buildAccountSection(StorageService storage, dynamic user) {
    final isLoggedIn = user != null;
    final username = user?.username ?? 'Guest Explorer';
    final email = user?.email ?? 'No desktop account logged in';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Account & Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Manage your desktop account credentials, profile details, and authentication.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // User badge card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.secondaryBg,
            borderRadius: AppRadii.card,
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandRed.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppColors.brandRed,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isLoggedIn
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.brandRed.withValues(alpha: 0.15),
                  borderRadius: AppRadii.control,
                ),
                child: Text(
                  isLoggedIn ? 'LOGGED IN' : 'GUEST',
                  style: TextStyle(
                    color: isLoggedIn ? AppColors.success : AppColors.brandRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        if (!isLoggedIn) ...[
          _buildActionTile(
            focusNode: _accountActionNode,
            directionalKeyHandlers: {
              LogicalKeyboardKey.arrowLeft: () =>
                  _categoryFocusNodes[4].requestFocus(),
              LogicalKeyboardKey.arrowDown: () =>
                  _manualLoginNode.requestFocus(),
            },
            title: 'Sign In to AniWings',
            subtitle:
                'Access your cloud watchlist and sync progress across devices.',
            buttonLabel: 'Sign In',
            onTap: () => context.push('/login'),
          ),
          const SizedBox(height: 16),
          _buildActionTile(
            focusNode: _manualLoginNode,
            directionalKeyHandlers: {
              LogicalKeyboardKey.arrowLeft: () =>
                  _categoryFocusNodes[4].requestFocus(),
              LogicalKeyboardKey.arrowUp: () =>
                  _accountActionNode.requestFocus(),
            },
            title: 'Create Account',
            subtitle: 'New to AniWings? Create a free account now.',
            buttonLabel: 'Sign Up',
            onTap: () => context.push('/signup'),
          ),
          const SizedBox(height: 16),
          _buildActionTile(
            title: 'External List Sync (MAL / AniList)',
            subtitle:
                'Connect your MyAnimeList or AniList accounts to import watchlists and sync episode progress.',
            buttonLabel: 'Manage Sync',
            onTap: () => context.push('/sync'),
          ),
        ] else ...[
          _buildActionTile(
            focusNode: _accountActionNode,
            directionalKeyHandlers: {
              LogicalKeyboardKey.arrowLeft: () =>
                  _categoryFocusNodes[4].requestFocus(),
              LogicalKeyboardKey.arrowDown: () =>
                  _manualLoginNode.requestFocus(),
            },
            title: 'Edit Profile & Avatar',
            subtitle: 'Change your display name or pick a custom anime avatar.',
            buttonLabel: 'Edit Profile',
            onTap: () => context.push('/edit-profile'),
          ),
          const SizedBox(height: 16),
          _buildActionTile(
            focusNode: _manualLoginNode,
            directionalKeyHandlers: {
              LogicalKeyboardKey.arrowLeft: () =>
                  _categoryFocusNodes[4].requestFocus(),
              LogicalKeyboardKey.arrowUp: () =>
                  _accountActionNode.requestFocus(),
              LogicalKeyboardKey.arrowDown: () =>
                  _logoutActionNode.requestFocus(),
            },
            title: 'External List Sync',
            subtitle: 'Connect your MyAnimeList or AniList accounts.',
            buttonLabel: 'Manage Sync',
            onTap: () => context.push('/sync'),
          ),
          const SizedBox(height: 12),
          _buildActionTile(
            focusNode: _logoutActionNode,
            directionalKeyHandlers: {
              LogicalKeyboardKey.arrowLeft: () =>
                  _categoryFocusNodes[4].requestFocus(),
              LogicalKeyboardKey.arrowUp: () => _manualLoginNode.requestFocus(),
            },
            title: 'Sign Out of AniWings Desktop',
            subtitle:
                'Clears session credentials and switches back to local guest viewing.',
            buttonLabel: 'Sign Out',
            isDestructive: true,
            onTap: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Logged out of AniWings Desktop.'),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // 6. Community & Support Section
  Widget _buildCommunityAndSupportSection(StorageService storage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Community & Support',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Join our global anime community, get live announcements, access FAQs, and contact support.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // Community Cards Grid
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildCommunityPlatformCard(
                focusNode: _communityDiscordNode,
                title: 'Discord Community',
                subtitle:
                    'Chat with fans, watch parties, server status, feedback & suggestions.',
                icon: Icons.forum_rounded,
                iconColor: const Color(0xFF5865F2),
                badgeText: 'JOIN CHAT',
                directionalKeyHandlers: {
                  LogicalKeyboardKey.arrowLeft: () =>
                      _categoryFocusNodes[6].requestFocus(),
                  LogicalKeyboardKey.arrowRight: () =>
                      _communityTelegramNode.requestFocus(),
                  LogicalKeyboardKey.arrowDown: () =>
                      _communityRedditNode.requestFocus(),
                },
                onTap: () => _launchExternalUrl(_discordUrl),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildCommunityPlatformCard(
                focusNode: _communityTelegramNode,
                title: 'Telegram Channel',
                subtitle:
                    'Instant anime release notifications, updates & community chat.',
                icon: Icons.send_rounded,
                iconColor: const Color(0xFF229ED9),
                badgeText: 'FOLLOW',
                directionalKeyHandlers: {
                  LogicalKeyboardKey.arrowLeft: () =>
                      _communityDiscordNode.requestFocus(),
                  LogicalKeyboardKey.arrowDown: () =>
                      _communityEmailNode.requestFocus(),
                },
                onTap: () => _launchExternalUrl(_telegramUrl),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildCommunityPlatformCard(
                focusNode: _communityRedditNode,
                title: 'Reddit Community',
                subtitle:
                    'r/AniWings_Official • Discussions, feature polls & community memes.',
                icon: Icons.groups_2_rounded,
                iconColor: const Color(0xFFFF4500),
                badgeText: 'SUBREDDIT',
                directionalKeyHandlers: {
                  LogicalKeyboardKey.arrowLeft: () =>
                      _categoryFocusNodes[6].requestFocus(),
                  LogicalKeyboardKey.arrowUp: () =>
                      _communityDiscordNode.requestFocus(),
                  LogicalKeyboardKey.arrowRight: () =>
                      _communityEmailNode.requestFocus(),
                  LogicalKeyboardKey.arrowDown: () =>
                      _communityPopupNode.requestFocus(),
                },
                onTap: () => _launchExternalUrl(_redditUrl),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildCommunityPlatformCard(
                focusNode: _communityEmailNode,
                title: 'Email Support',
                subtitle:
                    '$_supportEmail • Direct help with playback, account, or bugs.',
                icon: Icons.mail_outline_rounded,
                iconColor: AppColors.brandRed,
                badgeText: 'CONTACT',
                directionalKeyHandlers: {
                  LogicalKeyboardKey.arrowLeft: () =>
                      _communityRedditNode.requestFocus(),
                  LogicalKeyboardKey.arrowUp: () =>
                      _communityTelegramNode.requestFocus(),
                  LogicalKeyboardKey.arrowDown: () =>
                      _communityFaqNode.requestFocus(),
                },
                onTap: () => _launchExternalUrl('mailto:$_supportEmail'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 24),

        // Quick Action Row: Community Popup & Help Desk
        _buildActionTile(
          focusNode: _communityPopupNode,
          directionalKeyHandlers: {
            LogicalKeyboardKey.arrowLeft: () =>
                _categoryFocusNodes[6].requestFocus(),
            LogicalKeyboardKey.arrowUp: () =>
                _communityRedditNode.requestFocus(),
            LogicalKeyboardKey.arrowDown: () =>
                _communityFaqNode.requestFocus(),
          },
          title: 'Show Community Channels Popup',
          subtitle:
              'Display the welcome social channels modal with quick links.',
          buttonLabel: 'Open Popup',
          onTap: () {
            showDialog(
              context: context,
              barrierDismissible: true,
              barrierColor: Colors.black.withValues(alpha: 0.75),
              builder: (context) => const SocialFollowDialog(),
            );
          },
        ),

        const SizedBox(height: 16),

        _buildActionTile(
          focusNode: _communityFaqNode,
          directionalKeyHandlers: {
            LogicalKeyboardKey.arrowLeft: () =>
                _categoryFocusNodes[6].requestFocus(),
            LogicalKeyboardKey.arrowUp: () =>
                _communityPopupNode.requestFocus(),
          },
          title: 'Open Full Help Center & FAQs',
          subtitle:
              'Explore 20+ categorized answers, server guides, DoH setup, and troubleshooting.',
          buttonLabel: 'Help Center',
          onTap: () => context.push('/support'),
        ),
      ],
    );
  }

  Widget _buildCommunityPlatformCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String badgeText,
    required VoidCallback onTap,
    FocusNode? focusNode,
    Map<LogicalKeyboardKey, VoidCallback>? directionalKeyHandlers,
  }) {
    return DesktopFocusWrapper.builder(
      focusNode: focusNode,
      directionalKeyHandlers: directionalKeyHandlers ?? const {},
      onTap: onTap,
      borderRadius: AppRadii.card,
      builder: (context, isFocused, isHovered) {
        final active = isFocused || isHovered;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: active ? AppColors.hoverState : AppColors.secondaryBg,
            borderRadius: AppRadii.card,
            border: Border.all(
              color: isFocused
                  ? Colors.white
                  : (active ? AppColors.borderStrong : AppColors.borderSubtle),
              width: isFocused ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: AppRadii.control,
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    FocusNode? focusNode,
    Map<LogicalKeyboardKey, VoidCallback>? directionalKeyHandlers,
  }) {
    return DesktopFocusWrapper.builder(
      focusNode: focusNode,
      directionalKeyHandlers: directionalKeyHandlers ?? const {},
      onTap: () => onChanged(!value),
      borderRadius: AppRadii.control,
      builder: (context, isFocused, isHovered) {
        final active = isFocused || isHovered;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: active ? AppColors.hoverState : Colors.transparent,
            borderRadius: AppRadii.control,
            border: Border.all(
              color: isFocused ? Colors.white : Colors.transparent,
              width: isFocused ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ExcludeFocus(
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.brandRed,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingOptionTile({
    required String title,
    required String subtitle,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
    Map<String, FocusNode>? focusNodes,
    Map<String, Map<LogicalKeyboardKey, VoidCallback>>? directionalHandlers,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          );
          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final isChosen = opt.toLowerCase() == selected.toLowerCase();
              final node = focusNodes?[opt];
              final handlers = directionalHandlers?[opt] ?? const {};

              return DesktopFocusWrapper.builder(
                focusNode: node,
                directionalKeyHandlers: handlers,
                onTap: () => onSelected(opt),
                borderRadius: AppRadii.control,
                builder: (context, isFocused, isHovered) {
                  final active = isFocused || isHovered;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isChosen
                          ? AppColors.brandRed.withValues(alpha: 0.16)
                          : (active ? AppColors.hoverState : AppColors.surface),
                      borderRadius: AppRadii.control,
                      border: Border.all(
                        color: isFocused
                            ? Colors.white
                            : (isChosen
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
                        Icon(
                          Icons.check_rounded,
                          color: isChosen
                              ? AppColors.brandRed
                              : Colors.transparent,
                          size: 13,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          opt,
                          style: TextStyle(
                            color: isChosen || active
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: isChosen || active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }).toList(),
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 12), controls],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 4, child: label),
              const SizedBox(width: 28),
              Expanded(flex: 5, child: controls),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onTap,
    FocusNode? focusNode,
    Map<LogicalKeyboardKey, VoidCallback>? directionalKeyHandlers,
    bool isDestructive = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        DesktopFocusWrapper.builder(
          focusNode: focusNode,
          directionalKeyHandlers: directionalKeyHandlers ?? const {},
          onTap: onTap,
          borderRadius: AppRadii.control,
          builder: (context, isFocused, isHovered) {
            final active = isFocused || isHovered;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDestructive
                    ? (active ? AppColors.danger : AppColors.darkRed)
                    : (active ? AppColors.brandRed : AppColors.elevatedSurface),
                borderRadius: AppRadii.control,
                border: Border.all(
                  color: isFocused
                      ? Colors.white
                      : (isDestructive
                            ? AppColors.danger
                            : AppColors.borderSubtle),
                  width: isFocused ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                buttonLabel,
                style: TextStyle(
                  color: active
                      ? Colors.white
                      : (isDestructive ? AppColors.secondaryRed : Colors.white),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Backwards Compatibility Alias ──────────────────────────────────────────
