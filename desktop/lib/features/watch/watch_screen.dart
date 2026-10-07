import '../downloads/downloads_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/device_service.dart';
import '../../core/focus/desktop_navigation_controller.dart';
import '../../models/anime.dart';
import '../../models/episode.dart';
import '../../models/watch_entry.dart';
import '../../models/video_provider.dart';
import '../../services/anime_service.dart';
import '../../services/auth_service.dart';
import '../../services/list_sync_service.dart';
import '../../services/storage_service.dart';
import '../../services/skip_times_service.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/player_popup_focus.dart';
import '../../widgets/custom_video_player.dart';
import '../../widgets/dotted_spinner.dart';
import '../../widgets/loading_shimmer.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/web_video_player.dart';
import '../../services/levi_native_proxy_stub.dart'
    if (dart.library.io) '../../services/levi_native_proxy_io.dart';

class WatchScreen extends ConsumerStatefulWidget {
  final String animeId;
  final String episodeId;

  const WatchScreen({
    super.key,
    required this.animeId,
    required this.episodeId,
  });

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  final GlobalKey _playerHostKey = GlobalKey(
    debugLabel: 'persistent-watch-player',
  );
  String _selectedLanguage = 'SUB';
  String? _selectedProviderName = 'Gojo';
  bool _userExplicitlySelectedProvider = false;
  bool _isEpisodePageInitialized = false;
  int _currentEpisodePage = 0;
  String? _lastSavedEpisodeId;
  int _playerReloadIndex = 0;
  final Map<String, String> _extractedUrls = {};
  final Map<String, String> _extractedSubtitleUrls = {};
  final Map<String, List<SubtitleTrack>> _extractedSubtitleTracks = {};
  final Set<String> _failedProviderKeys = {};
  final Map<String, String> _providerFailureMessages = {};
  final Map<String, Future<String?>> _torrentStreams = {};
  int _torrentGeneration = 0;
  String? _automaticPlaybackKey;
  String? _automaticPlaybackScope;

  Future<String?> _prepareTorrent(String source, int episode) {
    return _torrentStreams.putIfAbsent(source, () async {
      final generation = _torrentGeneration;
      final url = await prepareLeviNativeStream(source, episodeNumber: episode);
      if (!mounted || generation != _torrentGeneration) {
        if (url != null) await stopLeviNativeStream(url);
        return null;
      }
      return url;
    });
  }

  void _releaseTorrentStreams() {
    _torrentGeneration++;
    for (final future in _torrentStreams.values) {
      unawaited(
        future
            .then((url) async {
              if (url != null) await stopLeviNativeStream(url);
            })
            .catchError((Object _) {}),
      );
    }
    _torrentStreams.clear();
  }

  final Set<String> _externalSyncCompletionKeys = {};
  bool _lastSavedCompleted = false;
  DateTime _lastProgressSaveTime = DateTime.now();
  Duration? _lastSavedPosition;
  Timer? _autoNextTimer;
  final TextEditingController _playlistFilterController =
      TextEditingController();
  String _playlistFilterQuery = '';
  bool _isSynopsisExpanded = false;
  // Playback is the primary action on a desktop watch route. Start in a true
  // edge-to-edge player; Back returns to the episode/server control center.
  bool _isPlayerFullscreen = false;

  int _requestedEpisodeNumber() {
    final match = RegExp(r'_ep_(\d+)$').firstMatch(widget.episodeId);
    return int.tryParse(match?.group(1) ?? '') ?? 1;
  }

  List<Episode> _provisionalEpisodes(Anime anime) {
    final requestedNumber = _requestedEpisodeNumber();
    var episodeCount = anime.totalEpisodes;
    if (episodeCount < requestedNumber) episodeCount = requestedNumber;
    if (episodeCount <= 0) episodeCount = 1;
    final duration = Duration(
      minutes: anime.episodeDurationMinutes > 0
          ? anime.episodeDurationMinutes
          : 24,
    );
    final now = DateTime.now();
    return List.generate(episodeCount, (index) {
      final number = index + 1;
      return Episode(
        id: '${anime.id}_ep_$number',
        animeId: anime.id,
        episodeNumber: number,
        title: 'Episode $number',
        airDate: now,
        duration: duration,
        videoUrls: const [],
      );
    }, growable: false);
  }

  @override
  void initState() {
    super.initState();
    unawaited(DeviceService.setScreenAwake(true));
    final defaultAudio = ref
        .read(storageServiceProvider)
        .getDefaultAudioPreference()
        .toUpperCase();
    _selectedLanguage = defaultAudio == 'DUB' ? 'DUB' : 'SUB';
    final defaultServer = ref
        .read(storageServiceProvider)
        .getDefaultServerPreference();
    if (defaultServer.isNotEmpty) {
      _selectedProviderName = defaultServer;
    }
  }

  void _lockLandscapePlayback() {
    unawaited(DeviceService.setDesktopFullscreen(true));
  }

  void _restoreDesktopPlayback() {
    unawaited(DeviceService.setDesktopFullscreen(false));
  }

  void _setPlayerFullscreen(bool fullscreen) {
    if (fullscreen) {
      _lockLandscapePlayback();
    } else {
      _restoreDesktopPlayback();
    }

    if (_isPlayerFullscreen == fullscreen) return;
    setState(() {
      _isPlayerFullscreen = fullscreen;
    });
  }

  void _handleToggleFullscreen() {
    _setPlayerFullscreen(!_isPlayerFullscreen);
  }

  bool _isExiting = false;

  void _handleExitWatch(BuildContext context) {
    if (_isExiting) return;
    _isExiting = true;
    _restoreDesktopPlayback();
    final detailsLocation = '/anime/${widget.animeId}';

    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return;
    }

    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() ?? false) {
      navigator!.pop();
      return;
    }

    router?.go(detailsLocation);
  }

  KeyEventResult _handleDesktopWatchKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _handleToggleFullscreen();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape &&
          _isPlayerFullscreen) {
        _setPlayerFullscreen(false);
        return KeyEventResult.handled;
      }
    }
    if (!DesktopNavigationController.isDesktopBackKey(event)) {
      return KeyEventResult.ignored;
    }

    if (_isPlayerFullscreen) {
      _setPlayerFullscreen(false);
    } else {
      _handleExitWatch(context);
    }
    return KeyEventResult.handled;
  }

  String _subtitlePreferenceForPlayback(StorageService storageService) {
    final preference = storageService.getSubtitlePreference().trim();
    final normalized = preference.toLowerCase();
    final disablesSubtitles =
        normalized.isEmpty ||
        normalized == 'off' ||
        normalized == 'none' ||
        normalized == 'disabled';

    if (_selectedLanguage == 'SUB' && disablesSubtitles) {
      return 'English';
    }

    return preference.isEmpty ? 'English' : preference;
  }

  bool _subtitlePreferenceDisablesCaptions(String preference) {
    final normalized = preference.toLowerCase().trim();
    return normalized == 'off' ||
        normalized == 'none' ||
        normalized == 'disabled';
  }

  String _normalizedSubtitleSearchText(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll('_', '-')
        .replaceAll('\u00e1', 'a')
        .replaceAll('\u00e0', 'a')
        .replaceAll('\u00e2', 'a')
        .replaceAll('\u00e3', 'a')
        .replaceAll('\u00e4', 'a')
        .replaceAll('\u00e9', 'e')
        .replaceAll('\u00e8', 'e')
        .replaceAll('\u00ea', 'e')
        .replaceAll('\u00eb', 'e')
        .replaceAll('\u00ed', 'i')
        .replaceAll('\u00ec', 'i')
        .replaceAll('\u00ee', 'i')
        .replaceAll('\u00ef', 'i')
        .replaceAll('\u00f3', 'o')
        .replaceAll('\u00f2', 'o')
        .replaceAll('\u00f4', 'o')
        .replaceAll('\u00f5', 'o')
        .replaceAll('\u00f6', 'o')
        .replaceAll('\u00fa', 'u')
        .replaceAll('\u00f9', 'u')
        .replaceAll('\u00fb', 'u')
        .replaceAll('\u00fc', 'u')
        .replaceAll('\u00e7', 'c')
        .replaceAll('\u00f1', 'n');
  }

  List<String> _subtitleAliasesForPreference(String preference) {
    final normalized = _normalizedSubtitleSearchText(preference);
    if (normalized == 'portuguese' ||
        normalized == 'pt' ||
        normalized == 'pt-br' ||
        normalized == 'por' ||
        normalized == 'brazilian') {
      return const [
        'pt',
        'pt-br',
        'por',
        'portuguese',
        'portugues',
        'brazilian',
      ];
    }
    if (normalized == 'spanish' ||
        normalized == 'es' ||
        normalized == 'spa' ||
        normalized == 'castellano') {
      return const [
        'es',
        'spa',
        'spanish',
        'espanol',
        'castilian',
        'castellano',
      ];
    }
    return const ['en', 'eng', 'english'];
  }

  bool _subtitleTrackMatchesPreference(SubtitleTrack track, String preference) {
    final language = _normalizedSubtitleSearchText(track.language);
    final label = _normalizedSubtitleSearchText(track.label);
    for (final alias in _subtitleAliasesForPreference(preference)) {
      if (alias.length <= 3) {
        if (language == alias || language.startsWith('$alias-')) {
          return true;
        }
        continue;
      }
      if (language == alias || label.contains(alias)) return true;
    }
    return false;
  }

  bool _isKnownSubtitleLanguage(SubtitleTrack track) {
    return _subtitleTrackMatchesPreference(track, 'English') ||
        _subtitleTrackMatchesPreference(track, 'Portuguese') ||
        _subtitleTrackMatchesPreference(track, 'Spanish');
  }

  bool _isGenericSubtitlePreference(String preference) {
    final normalized = _normalizedSubtitleSearchText(preference);
    return normalized == 'on' ||
        normalized == 'enabled' ||
        normalized == 'true' ||
        normalized == 'auto' ||
        normalized == 'default' ||
        normalized == 'subtitles' ||
        normalized == 'captions';
  }

  String _subtitleLanguageFromText(String text) {
    final normalized = _normalizedSubtitleSearchText(text);
    if (RegExp(r'(^|[^a-z])(en|eng|english)([^a-z]|$)').hasMatch(normalized)) {
      return 'en';
    }
    if (RegExp(
      r'(^|[^a-z])(pt|pt-br|por|portuguese|portugues|brazilian)([^a-z]|$)',
    ).hasMatch(normalized)) {
      return 'pt';
    }
    if (RegExp(
      r'(^|[^a-z])(es|spa|spanish|espanol|castilian|castellano)([^a-z]|$)',
    ).hasMatch(normalized)) {
      return 'es';
    }
    return '';
  }

  String _subtitleLabelForLanguage(String language, String url) {
    final normalized = _normalizedSubtitleSearchText(language);
    if (normalized == 'en' || normalized == 'eng' || normalized == 'english') {
      return 'English';
    }
    if (normalized == 'pt' ||
        normalized == 'pt-br' ||
        normalized == 'por' ||
        normalized == 'portuguese' ||
        normalized == 'portugues' ||
        normalized == 'brazilian') {
      return 'Portuguese';
    }
    if (normalized == 'es' ||
        normalized == 'spa' ||
        normalized == 'spanish' ||
        normalized == 'espanol' ||
        normalized == 'castilian' ||
        normalized == 'castellano') {
      return 'Spanish';
    }

    final uri = Uri.tryParse(url);
    final fileName = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    return fileName.isNotEmpty ? fileName : 'Default';
  }

  SubtitleTrack _fallbackSubtitleTrack(String url) {
    final language = _subtitleLanguageFromText(url);
    return SubtitleTrack(
      label: _subtitleLabelForLanguage(language, url),
      language: language,
      url: url,
    );
  }

  List<SubtitleTrack>? _subtitleTracksForPlayback({
    required List<SubtitleTrack>? extractedTracks,
    required List<SubtitleTrack>? providerTracks,
    required String? fallbackSubtitleUrl,
  }) {
    final tracks = <SubtitleTrack>[];
    final seenUrls = <String>{};

    void addTrack(SubtitleTrack track) {
      final url = track.url.trim();
      if (url.isEmpty || !seenUrls.add(url)) return;
      tracks.add(track);
    }

    for (final track in extractedTracks ?? const <SubtitleTrack>[]) {
      addTrack(track);
    }
    for (final track in providerTracks ?? const <SubtitleTrack>[]) {
      addTrack(track);
    }

    final fallbackUrl = fallbackSubtitleUrl?.trim();
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      final existingIndex = tracks.indexWhere(
        (track) => track.url.trim() == fallbackUrl,
      );
      if (existingIndex == -1) {
        addTrack(_fallbackSubtitleTrack(fallbackUrl));
      } else if (!_isKnownSubtitleLanguage(tracks[existingIndex])) {
        final fallbackTrack = _fallbackSubtitleTrack(fallbackUrl);
        if (fallbackTrack.language.isNotEmpty ||
            fallbackTrack.label != 'Default') {
          tracks[existingIndex] = SubtitleTrack(
            label: tracks[existingIndex].label.isNotEmpty
                ? tracks[existingIndex].label
                : fallbackTrack.label,
            language: tracks[existingIndex].language.isNotEmpty
                ? tracks[existingIndex].language
                : fallbackTrack.language,
            url: fallbackUrl,
          );
        }
      }
    }

    return tracks.isEmpty ? null : List.unmodifiable(tracks);
  }

  String? _subtitleUrlForPreference(
    List<SubtitleTrack>? tracks,
    String preference,
  ) {
    if (tracks == null || tracks.isEmpty) return null;
    if (_subtitlePreferenceDisablesCaptions(preference)) return null;
    if (_isGenericSubtitlePreference(preference)) return tracks.first.url;
    final index = tracks.indexWhere(
      (track) => _subtitleTrackMatchesPreference(track, preference),
    );
    return index == -1 ? null : tracks[index].url;
  }

  String _subtitlePreferenceForProviderPlayback({
    required String preference,
    required List<SubtitleTrack>? tracks,
  }) {
    if (_subtitlePreferenceDisablesCaptions(preference) ||
        tracks == null ||
        tracks.isEmpty) {
      return preference;
    }
    if (tracks.any(
      (track) => _subtitleTrackMatchesPreference(track, preference),
    )) {
      return preference;
    }

    if (!tracks.any(_isKnownSubtitleLanguage)) {
      return 'Default';
    }

    return preference;
  }

  bool _looksLikeNativeVideoUrl(String url) {
    final lower = url.toLowerCase();
    return !lower.startsWith('blob:') &&
        (lower.contains('.m3u8') || lower.contains('.mp4'));
  }

  int _qualityHintFromUrl(String url) {
    final match = RegExp(
      r'(?:^|[^0-9])(2160|1440|1080|720|480|360|240)(?:p|[^0-9]|$)',
      caseSensitive: false,
    ).firstMatch(url);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  int _extractedVideoUrlScore(String url) {
    final lower = url.toLowerCase();
    if (!_looksLikeNativeVideoUrl(lower)) return 0;

    var score = lower.contains('.m3u8') ? 2000 : 1000;
    if (lower.contains('master') ||
        lower.contains('playlist') ||
        lower.contains('index.m3u8')) {
      score += 2000;
    }
    score += _qualityHintFromUrl(lower).clamp(0, 2160);
    return score;
  }

  bool _shouldReplaceExtractedVideoUrl(String? currentUrl, String nextUrl) {
    final next = nextUrl.trim();
    if (!_looksLikeNativeVideoUrl(next)) return false;
    final current = currentUrl?.trim();
    if (current == null || current.isEmpty) return true;
    if (current == next) return false;

    final currentScore = _extractedVideoUrlScore(current);
    final nextScore = _extractedVideoUrlScore(next);
    return nextScore > currentScore;
  }

  String _normalizedProviderName(String name) => name.toLowerCase().trim();

  VideoProviderSource? _providerBySelectedName(
    List<VideoProviderSource> providers,
  ) {
    final selectedName = _selectedProviderName;
    if (selectedName == null || selectedName.trim().isEmpty) return null;
    final normalizedSelectedName = _normalizedProviderName(selectedName);
    for (final provider in providers) {
      if (_normalizedProviderName(provider.name) == normalizedSelectedName &&
          !provider.isEmbed) {
        return provider;
      }
    }
    for (final provider in providers) {
      if (_normalizedProviderName(provider.name) == normalizedSelectedName) {
        return provider;
      }
    }
    return null;
  }

  VideoProviderSource _bestAutomaticProvider(
    List<VideoProviderSource> providers,
  ) {
    if (providers.isEmpty) throw StateError('No providers available');

    VideoProviderSource? findByName(String name, {bool? requireNative}) {
      final target = name.toLowerCase();
      for (final p in providers) {
        if (_normalizedProviderName(p.name) == target) {
          if (requireNative == null || p.isEmbed != requireNative) {
            return p;
          }
        }
      }
      return null;
    }

    // Resolve a native source before preferring a provider's name. Embed URLs
    // are unverified fallbacks and may be error pages rather than playable media.
    for (final name in [
      'gojo',
      'kakashi',
      'luffy',
      'tanjiro',
      'levi',
      'eren',
      'mikasa',
    ]) {
      final native = findByName(name, requireNative: true);
      if (native != null) return native;
    }
    for (final provider in providers) {
      if (!provider.isEmbed) return provider;
    }
    return providers.first;
  }

  VideoProviderSource? _selectActiveProvider(
    List<VideoProviderSource> providers,
  ) {
    if (providers.isEmpty) return null;

    if (!_userExplicitlySelectedProvider &&
        _automaticPlaybackScope == '${widget.episodeId}|$_selectedLanguage') {
      for (final provider in providers) {
        if (_providerFailureKey(provider) == _automaticPlaybackKey &&
            !_providerHasFailed(provider)) {
          return provider;
        }
      }
    }

    final selectedProvider = _providerBySelectedName(providers);

    // If a server is selected (by default or user choice):
    if (selectedProvider != null) {
      if (!_providerHasFailed(selectedProvider)) {
        if (!_userExplicitlySelectedProvider && selectedProvider.isEmbed) {
          final native = providers
              .where((p) => !p.isEmbed && !_providerHasFailed(p))
              .toList();
          if (native.isNotEmpty) return _bestAutomaticProvider(native);
        }
        return selectedProvider;
      }
      // Preserve an explicit choice, but let a failing default fall back to
      // another available provider instead of stopping playback altogether.
      if (_userExplicitlySelectedProvider) return null;
    }

    if (_userExplicitlySelectedProvider) {
      // Explicitly chosen provider is unavailable for this episode/audio
      return null;
    }

    // Default preference fallback if preferred server is absent from episode
    final playableProviders = providers
        .where((provider) => !_providerHasFailed(provider))
        .toList();
    if (playableProviders.isEmpty) {
      return null;
    }

    // Return the best available provider without mutating _selectedProviderName
    return _bestAutomaticProvider(playableProviders);
  }

  String _providerFailureKey(VideoProviderSource provider) {
    final primaryUrl = provider.videoUrls.isNotEmpty
        ? provider.videoUrls.first.trim()
        : provider.description.trim();
    return [
      provider.name.toLowerCase().trim(),
      provider.languageType.toUpperCase().trim(),
      provider.isEmbed ? 'embed' : 'native',
      primaryUrl,
    ].join('|');
  }

  bool _providerHasFailed(VideoProviderSource provider) {
    return _failedProviderKeys.contains(_providerFailureKey(provider));
  }

  void _markProviderPlaybackFailed(VideoProviderSource provider) {
    final key = _providerFailureKey(provider);
    if (!mounted || _failedProviderKeys.contains(key)) return;
    setState(() {
      _failedProviderKeys.add(key);
    });
  }

  void _retryProviderLoad(String animeId, int episodeNumber) {
    setState(() {
      _failedProviderKeys.clear();
      _providerFailureMessages.clear();
    });
    ref.invalidate(
      videoProvidersProvider((animeId: animeId, episodeNumber: episodeNumber)),
    );
  }

  void _scheduleAutoPlayNext({
    required bool enabled,
    required bool hasNextEpisode,
    required VoidCallback? playNext,
  }) {
    _autoNextTimer?.cancel();
    if (!enabled || !hasNextEpisode || playNext == null) return;
    _autoNextTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && ref.read(storageServiceProvider).getAutoPlayNext()) {
        playNext();
      }
    });
  }

  void _saveWatchProgress(Anime anime, Episode episode) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final storageService = ref.read(storageServiceProvider);
      final user = ref.read(authStateProvider);
      final activeUserId = user?.id ?? StorageService.guestWatchHistoryUserId;

      final existingEntry = storageService.getWatchEntryForAnime(
        anime.id,
        userId: activeUserId,
      );
      Duration initialDuration = Duration.zero;
      bool isCompleted = false;

      if (existingEntry != null &&
          existingEntry.lastWatchedEpisode == episode.episodeNumber) {
        initialDuration = existingEntry.watchedDuration;
        isCompleted = existingEntry.isCompleted;
      }

      final entry = WatchEntry(
        id: '${anime.id}_history',
        userId: activeUserId,
        animeId: anime.id,
        lastWatchedEpisode: episode.episodeNumber,
        watchedDuration: initialDuration,
        lastWatchedAt: DateTime.now(),
        isCompleted: isCompleted,
      );
      await storageService.saveWatchEntry(entry);
    });
  }

  Future<void> _saveWatchEntryAndSync(Anime anime, WatchEntry entry) async {
    await ref.read(storageServiceProvider).saveWatchEntry(entry);
    _syncCompletedWatchProgress(anime, entry);
  }

  void _syncCompletedWatchProgress(Anime anime, WatchEntry entry) {
    if (!entry.isCompleted || entry.isExternalSync) return;

    final syncKey =
        '${entry.userId}:${entry.animeId}:${entry.lastWatchedEpisode}';
    if (!_externalSyncCompletionKeys.add(syncKey)) return;

    unawaited(
      ref
          .read(listSyncServiceProvider)
          .syncCompletedWatchProgress(anime: anime, entry: entry)
          .catchError((Object error) {
            debugPrint('External list progress update failed: $error');
            _externalSyncCompletionKeys.remove(syncKey);
            return null;
          }),
    );
  }

  @override
  void dispose() {
    unawaited(DeviceService.setDesktopFullscreen(false));
    _releaseTorrentStreams();
    _playlistFilterController.dispose();
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    for (final url in _extractedUrls.values) {
      if (url.startsWith('http://127.0.0.1')) {
        unawaited(stopLeviNativeStream(url));
      }
    }
    _extractedUrls.clear();
    _extractedSubtitleUrls.clear();
    _extractedSubtitleTracks.clear();
    _failedProviderKeys.clear();
    _providerFailureMessages.clear();
    _externalSyncCompletionKeys.clear();
    unawaited(DeviceService.setScreenAwake(false));
    _restoreDesktopPlayback();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WatchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeId != widget.episodeId ||
        oldWidget.animeId != widget.animeId) {
      _releaseTorrentStreams();
      _autoNextTimer?.cancel();
      _autoNextTimer = null;
      final defaultServer = ref
          .read(storageServiceProvider)
          .getDefaultServerPreference();
      _selectedProviderName = defaultServer.isNotEmpty ? defaultServer : 'Gojo';
      _isEpisodePageInitialized = false;
      _extractedUrls.clear();
      _extractedSubtitleUrls.clear();
      _extractedSubtitleTracks.clear();
      _failedProviderKeys.clear();
      _providerFailureMessages.clear();
      _lastSavedPosition = null;
      _lastSavedCompleted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final storageService = ref.watch(storageServiceProvider);
    final user = ref.watch(authStateProvider);
    final activeUserId = user?.id ?? StorageService.guestWatchHistoryUserId;

    final animeAsync = ref.watch(animeDetailsProvider(widget.animeId));
    final episodesAsync = ref.watch(animeEpisodesProvider(widget.animeId));

    if (animeAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.primaryBg,
        body: DesktopPageBackdrop(
          child: SafeArea(child: LoadingShimmer.watch()),
        ),
      );
    }

    if (animeAsync.hasError) {
      return _buildWatchMessageScaffold(
        icon: Icons.error_outline_rounded,
        title: 'Unable to load episode playback data.',
        message: 'Check your connection and retry the episode.',
        action: ElevatedButton.icon(
          onPressed: () {
            ref.invalidate(animeDetailsProvider(widget.animeId));
            ref.invalidate(animeEpisodesProvider(widget.animeId));
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentPrimary,
            foregroundColor: Colors.black,
            minimumSize: const Size(180, 54),
          ),
        ),
      );
    }

    final anime = animeAsync.value;
    final episodes =
        episodesAsync.asData?.value ??
        (anime == null ? const <Episode>[] : _provisionalEpisodes(anime));

    if (anime == null || episodes.isEmpty) {
      return _buildWatchMessageScaffold(
        icon: Icons.video_library_outlined,
        title: 'Episode not found.',
        message: 'This title has no playable episode data right now.',
        action: OutlinedButton.icon(
          onPressed: () => _handleExitWatch(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Go Back'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(180, 54),
          ),
        ),
      );
    }

    Episode? episode;
    try {
      episode = episodes.firstWhere((e) => e.id == widget.episodeId);
    } catch (_) {
      try {
        final requestedNumber = _requestedEpisodeNumber();
        episode = episodes.firstWhere(
          (e) => e.episodeNumber == requestedNumber,
        );
      } catch (_) {}
    }

    if (episode == null) {
      return _buildWatchMessageScaffold(
        icon: Icons.movie_filter_outlined,
        title: 'Requested episode is missing.',
        message: 'You can start from the first available episode instead.',
        action: ElevatedButton(
          onPressed: () {
            context.replace('/watch/${anime.id}/${episodes.first.id}');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentPrimary,
            foregroundColor: Colors.black,
            minimumSize: const Size(180, 54),
          ),
          child: Text('Play Ep ${episodes.first.episodeNumber}'),
        ),
      );
    }

    final Episode activeEpisode = episode;
    const episodesPerPage = 18;

    if (_lastSavedEpisodeId != activeEpisode.id) {
      _lastSavedEpisodeId = activeEpisode.id;
      _saveWatchProgress(anime, activeEpisode);
    }

    if (!_isEpisodePageInitialized) {
      _currentEpisodePage =
          ((activeEpisode.episodeNumber - 1) / episodesPerPage).floor();
      final maxPage = ((episodes.length - 1) / episodesPerPage).floor();
      if (_currentEpisodePage > maxPage) {
        _currentEpisodePage = 0;
      }
      _isEpisodePageInitialized = true;
    }

    final watchEntry = storageService.getWatchEntryForAnime(
      anime.id,
      userId: activeUserId,
    );
    final resumePosition =
        (watchEntry != null &&
            watchEntry.lastWatchedEpisode == activeEpisode.episodeNumber)
        ? watchEntry.watchedDuration
        : Duration.zero;

    final hasNextEpisode = episodes.any(
      (e) => e.episodeNumber == activeEpisode.episodeNumber + 1,
    );
    VoidCallback? playNextCallback;
    if (hasNextEpisode) {
      playNextCallback = () {
        try {
          final nextEp = episodes.firstWhere(
            (e) => e.episodeNumber == activeEpisode.episodeNumber + 1,
          );
          context.replace('/watch/${anime.id}/${nextEp.id}');
        } catch (_) {}
      };
    }

    final hasPrevEpisode = activeEpisode.episodeNumber > 1;
    VoidCallback? playPrevCallback;
    if (hasPrevEpisode) {
      playPrevCallback = () {
        try {
          final prevEp = episodes.firstWhere(
            (e) => e.episodeNumber == activeEpisode.episodeNumber - 1,
          );
          context.replace('/watch/${anime.id}/${prevEp.id}');
        } catch (_) {}
      };
    }

    final providersAsync = ref.watch(
      videoProvidersProvider((
        animeId: anime.id,
        episodeNumber: activeEpisode.episodeNumber,
      )),
    );
    final providers = providersAsync.asData?.value ?? [];
    final subtitlePreference = _subtitlePreferenceForPlayback(storageService);
    final filteredProviders = providers.where((p) {
      final providerLanguage = p.languageType.toUpperCase();
      if (_selectedLanguage == 'SUB') {
        return providerLanguage == 'SUB' || providerLanguage == 'HSUB';
      }
      return providerLanguage == _selectedLanguage;
    }).toList();
    // Prefer native streams on desktop. If only embed streams are present while
    // providers are actively loading, keep the loading placeholder rather than
    // prematurely starting Chromium WebView.
    final hasNativeProvider = filteredProviders.any((p) => !p.isEmbed);
    final isLoadingProviders =
        providersAsync.isLoading && (providers.isEmpty || !hasNativeProvider);
    final availableProviders = filteredProviders
        .where((provider) => !_providerHasFailed(provider))
        .toList();
    final allLanguageProvidersFailed =
        filteredProviders.isNotEmpty && availableProviders.isEmpty;
    final activeProvider = _selectActiveProvider(filteredProviders);
    if (!_userExplicitlySelectedProvider &&
        activeProvider != null &&
        !activeProvider.isEmbed) {
      _automaticPlaybackKey = _providerFailureKey(activeProvider);
      _automaticPlaybackScope = '${widget.episodeId}|$_selectedLanguage';
    }
    final selectedProvider = _providerBySelectedName(filteredProviders);
    final selectedProviderFailed =
        selectedProvider != null && _providerHasFailed(selectedProvider);

    final videoUrls = activeProvider?.videoUrls ?? const <String>[];
    final isEmbed = activeProvider?.isEmbed ?? false;

    final String? primaryUrl = videoUrls.isNotEmpty ? videoUrls.first : null;
    final String? extractedUrl = primaryUrl != null
        ? _extractedUrls[primaryUrl]
        : null;
    final String? extractedSubtitleUrl = primaryUrl != null
        ? _extractedSubtitleUrls[primaryUrl]
        : null;
    final extractedSubtitleTracks = primaryUrl != null
        ? _extractedSubtitleTracks[primaryUrl]
        : null;

    final bool hasExtractedNativeUrl =
        extractedUrl != null &&
        extractedUrl.isNotEmpty &&
        _looksLikeNativeVideoUrl(extractedUrl);
    final bool isDirectNativeUrl =
        primaryUrl != null && _looksLikeNativeVideoUrl(primaryUrl);

    final finalVideoUrls = hasExtractedNativeUrl ? [extractedUrl] : videoUrls;
    final useNativePlayer =
        hasExtractedNativeUrl || isDirectNativeUrl || (!isEmbed);
    final shouldAutoPlayNext = storageService.getAutoPlayNext();
    final effectiveSubtitleTracks = _subtitleTracksForPlayback(
      extractedTracks: extractedSubtitleTracks,
      providerTracks: activeProvider?.subtitleTracks,
      fallbackSubtitleUrl: extractedSubtitleUrl ?? activeProvider?.subtitleUrl,
    );
    final effectiveSubtitlePreference = _subtitlePreferenceForProviderPlayback(
      preference: subtitlePreference,
      tracks: effectiveSubtitleTracks,
    );
    final tracksAreUnavailable =
        effectiveSubtitleTracks == null || effectiveSubtitleTracks.isEmpty;
    final effectiveSubtitleUrl =
        _subtitleUrlForPreference(
          effectiveSubtitleTracks,
          effectiveSubtitlePreference,
        ) ??
        (tracksAreUnavailable &&
                !_subtitlePreferenceDisablesCaptions(
                  effectiveSubtitlePreference,
                )
            ? extractedSubtitleUrl ?? activeProvider?.subtitleUrl
            : null);

    final isFullscreen = _isPlayerFullscreen;
    final shouldPlayerAutofocus = (isFullscreen);
    final progressSaveInterval = (const Duration(seconds: 8));
    final progressSaveDelta = (const Duration(seconds: 8));

    Widget playerWidget;
    if (isLoadingProviders) {
      playerWidget = _buildPlayerPlaceholder(
        'Loading streaming servers...',
        onShowEpisodes: () => _showEpisodePicker(
          anime: anime,
          activeEpisode: activeEpisode,
          episodes: episodes,
        ),
        onShowServers: () => _showServerPicker(
          providers: filteredProviders,
          activeProvider: activeProvider,
        ),
        onToggleLanguage: _toggleWatchLanguage,
      );
    } else if (activeProvider == null ||
        (finalVideoUrls.isEmpty && !activeProvider.usesTorrentPlayer)) {
      final hasSelectedProvider =
          _selectedProviderName != null && _selectedProviderName!.isNotEmpty;
      final isSelectedProviderUnavailable =
          hasSelectedProvider &&
          selectedProvider == null &&
          _userExplicitlySelectedProvider;
      final isProblemState =
          providersAsync.hasError ||
          selectedProviderFailed ||
          isSelectedProviderUnavailable ||
          allLanguageProvidersFailed;
      playerWidget = _buildPlayerPlaceholder(
        _providerFailureMessages.isNotEmpty
            ? _providerFailureMessages.values.last
            : providersAsync.hasError
            ? 'Failed to fetch streaming servers.\nCheck your connection and retry.'
            : selectedProviderFailed
            ? '${selectedProvider.name} could not start playback.\nRetry it or choose another server.'
            : isSelectedProviderUnavailable
            ? '$_selectedProviderName is unavailable for this episode.\nRetry or choose another server.'
            : allLanguageProvidersFailed
            ? 'All $_selectedLanguage servers failed.\nTap Retry or switch language.'
            : 'No $_selectedLanguage stream available.\nTry switching language above.',
        showRetry: isProblemState,
        isError: isProblemState,
        onRetry: () =>
            _retryProviderLoad(anime.id, activeEpisode.episodeNumber),
        onShowEpisodes: () => _showEpisodePicker(
          anime: anime,
          activeEpisode: activeEpisode,
          episodes: episodes,
        ),
        onShowServers: () => _showServerPicker(
          providers: filteredProviders,
          activeProvider: activeProvider,
        ),
        onToggleLanguage: _toggleWatchLanguage,
      );
    } else if (useNativePlayer) {
      Widget buildNativePlayer(List<String> urls) => CustomVideoPlayer(
        key: ValueKey(
          'native_${activeProvider.name}_${finalVideoUrls.isNotEmpty ? finalVideoUrls.first : ''}_${_selectedLanguage}_${storageService.getDnsModePreference()}_$_playerReloadIndex',
        ),
        videoUrls: urls,
        skipTimes: activeProvider.skipTimes,
        loadSkipTimes: (duration) => ref
            .read(skipTimesServiceProvider)
            .getSkipTimes(
              anime.malId ?? '',
              activeEpisode.episodeNumber,
              duration,
            ),
        animeTitle: anime.title,
        episodeTitle:
            'Episode ${activeEpisode.episodeNumber}: ${activeEpisode.title}',
        initialPosition: resumePosition,
        isFullscreen: isFullscreen,
        autoSkipIntroOutro: storageService.getAutoSkipIntroOutro(),
        showSkipButtons: storageService.getSkipIntroEnabled(),
        subtitleUrl: effectiveSubtitleUrl,
        subtitleTracks: effectiveSubtitleTracks,
        preferredVideoQuality: storageService.getVideoQualityPreference(),
        preferredSubtitleLanguage: effectiveSubtitlePreference,
        subtitleFontSize: storageService.getSubtitleSizePreference(),
        subtitleTextStyle: storageService.getSubtitleTextStylePreference(),
        subtitleTextColor: storageService.getSubtitleTextColorValue(),
        subtitleBackgroundColor: storageService
            .getSubtitleBackgroundColorValue(),
        subtitleBottomPosition: storageService.getSubtitleBottomPosition(),
        subtitleTextShadow: storageService.getSubtitleTextShadow(),
        subtitleBackgroundOpacity: storageService
            .getSubtitleBackgroundOpacity(),
        initialPlaybackSpeed: storageService.getPlaybackSpeedPreference(),
        // Keep every episode in the same desktop viewport from its first frame.
        initialVideoDisplayMode: 'fit_16_9',
        onQualityPreferenceChanged: (quality) {
          unawaited(storageService.setVideoQualityPreference(quality));
        },
        onSubtitlePreferenceChanged: (language) {
          unawaited(storageService.setSubtitlePreference(language));
        },
        onPlaybackSpeedChanged: (speed) {
          unawaited(storageService.setPlaybackSpeedPreference(speed));
        },
        onVideoDisplayModeChanged: (mode) {
          unawaited(storageService.setVideoDisplayModePreference(mode));
        },
        onShowEpisodes: () => _showEpisodePicker(
          anime: anime,
          activeEpisode: activeEpisode,
          episodes: episodes,
        ),
        onShowServers: () => _showServerPicker(
          providers: filteredProviders,
          activeProvider: activeProvider,
        ),
        onToggleLanguage: _toggleWatchLanguage,
        languageLabel: _selectedLanguage,
        serverLabel: activeProvider.name,
        autofocus: shouldPlayerAutofocus,
        autoPlayNext: shouldAutoPlayNext,
        alwaysShowControls: false,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          if (videoUrls.isNotEmpty &&
              Uri.tryParse(videoUrls.first)?.hasAuthority == true) ...{
            'Referer': 'https://${Uri.parse(videoUrls.first).host}/',
            'Origin': 'https://${Uri.parse(videoUrls.first).host}',
          },
          if (activeProvider.headers != null) ...activeProvider.headers!,
        },
        onPlayNext: playNextCallback,
        onPlayPrev: playPrevCallback,
        onToggleFullscreen: _handleToggleFullscreen,
        onBack: () => _handleExitWatch(context),
        onPlaybackError: (message) {
          _providerFailureMessages[_providerFailureKey(activeProvider)] =
              message;
        },
        onPlaybackFailed: () => _markProviderPlaybackFailed(activeProvider),
        onPositionChanged: (pos) {
          final now = DateTime.now();
          final timeSinceLastSave = now.difference(_lastProgressSaveTime);
          final epDurationSec = activeEpisode.duration.inSeconds > 0
              ? activeEpisode.duration.inSeconds
              : (anime.episodeDurationMinutes > 0
                    ? anime.episodeDurationMinutes * 60
                    : 1440);
          final isCompleted = pos.inSeconds >= (epDurationSec - 30);

          if (timeSinceLastSave >= progressSaveInterval ||
              (isCompleted && !_lastSavedCompleted) ||
              _lastSavedPosition == null ||
              (pos - _lastSavedPosition!).abs() > progressSaveDelta) {
            _lastProgressSaveTime = now;
            _lastSavedPosition = pos;
            _lastSavedCompleted = isCompleted;

            final entry = WatchEntry(
              id: '${anime.id}_history',
              userId: activeUserId,
              animeId: anime.id,
              lastWatchedEpisode: activeEpisode.episodeNumber,
              watchedDuration: pos,
              lastWatchedAt: now,
              isCompleted: isCompleted,
            );
            unawaited(_saveWatchEntryAndSync(anime, entry));
          }
        },
        onVideoEnded: () {
          final epDuration = activeEpisode.duration > Duration.zero
              ? activeEpisode.duration
              : Duration(
                  minutes: anime.episodeDurationMinutes > 0
                      ? anime.episodeDurationMinutes
                      : 24,
                );
          final entry = WatchEntry(
            id: '${anime.id}_history',
            userId: activeUserId,
            animeId: anime.id,
            lastWatchedEpisode: activeEpisode.episodeNumber,
            watchedDuration: epDuration,
            lastWatchedAt: DateTime.now(),
            isCompleted: true,
          );
          unawaited(_saveWatchEntryAndSync(anime, entry));

          _scheduleAutoPlayNext(
            enabled: shouldAutoPlayNext,
            hasNextEpisode: hasNextEpisode,
            playNext: playNextCallback,
          );
        },
      );
      final torrentSource = activeProvider.sourcePlayerUrl;
      if (activeProvider.usesTorrentPlayer &&
          finalVideoUrls.isEmpty &&
          torrentSource != null) {
        playerWidget = FutureBuilder<String?>(
          key: ValueKey(torrentSource),
          future: _prepareTorrent(torrentSource, activeEpisode.episodeNumber),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Finding peers and preparing video…'),
                  ],
                ),
              );
            }
            final url = snapshot.data;
            if (url == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Torrent could not start. Check peer availability or choose another server.',
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        _releaseTorrentStreams();
                        setState(() => _playerReloadIndex++);
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            return buildNativePlayer([url]);
          },
        );
      } else {
        playerWidget = buildNativePlayer(finalVideoUrls);
      }
    } else {
      playerWidget = WebVideoPlayer(
        key: ValueKey(
          'web_${activeProvider.name}_${videoUrls.isNotEmpty ? videoUrls.first : ''}_${_selectedLanguage}_${storageService.getDnsModePreference()}_$_playerReloadIndex',
        ),
        embedUrl: videoUrls.first,
        headers: activeProvider.headers,
        animeTitle: anime.title,
        episodeTitle:
            'Episode ${activeEpisode.episodeNumber}: ${activeEpisode.title}',
        initialPosition: resumePosition,
        alwaysShowControls: false,
        isFullscreen: isFullscreen,
        preferFlutterFullscreen: true,
        autofocus: shouldPlayerAutofocus,
        preferredSubtitleLanguage: effectiveSubtitlePreference,
        initialPlaybackSpeed: storageService.getPlaybackSpeedPreference(),
        initialVideoDisplayMode: 'fit_16_9',
        onSubtitlePreferenceChanged: (language) {
          unawaited(storageService.setSubtitlePreference(language));
        },
        onPlaybackSpeedChanged: (speed) {
          unawaited(storageService.setPlaybackSpeedPreference(speed));
        },
        onVideoDisplayModeChanged: (mode) {
          unawaited(storageService.setVideoDisplayModePreference(mode));
        },
        onShowEpisodes: () => _showEpisodePicker(
          anime: anime,
          activeEpisode: activeEpisode,
          episodes: episodes,
        ),
        onShowServers: () => _showServerPicker(
          providers: filteredProviders,
          activeProvider: activeProvider,
        ),
        onToggleLanguage: _toggleWatchLanguage,
        languageLabel: _selectedLanguage,
        serverLabel: activeProvider.name,
        onPlayNext: playNextCallback,
        onPlayPrev: playPrevCallback,
        onPlaybackFailed: () => _markProviderPlaybackFailed(activeProvider),
        onPositionChanged: (pos) {
          final now = DateTime.now();
          final timeSinceLastSave = now.difference(_lastProgressSaveTime);
          final epDurationSec = activeEpisode.duration.inSeconds > 0
              ? activeEpisode.duration.inSeconds
              : (anime.episodeDurationMinutes > 0
                    ? anime.episodeDurationMinutes * 60
                    : 1440);
          final isCompleted = pos.inSeconds >= (epDurationSec - 30);

          if (timeSinceLastSave >= progressSaveInterval ||
              (isCompleted && !_lastSavedCompleted) ||
              _lastSavedPosition == null ||
              (pos - _lastSavedPosition!).abs() > progressSaveDelta) {
            _lastProgressSaveTime = now;
            _lastSavedPosition = pos;
            _lastSavedCompleted = isCompleted;

            final entry = WatchEntry(
              id: '${anime.id}_history',
              userId: activeUserId,
              animeId: anime.id,
              lastWatchedEpisode: activeEpisode.episodeNumber,
              watchedDuration: pos,
              lastWatchedAt: now,
              isCompleted: isCompleted,
            );
            unawaited(_saveWatchEntryAndSync(anime, entry));
          }
        },
        onVideoEnded: () {
          final epDuration = activeEpisode.duration > Duration.zero
              ? activeEpisode.duration
              : Duration(
                  minutes: anime.episodeDurationMinutes > 0
                      ? anime.episodeDurationMinutes
                      : 24,
                );
          final entry = WatchEntry(
            id: '${anime.id}_history',
            userId: activeUserId,
            animeId: anime.id,
            lastWatchedEpisode: activeEpisode.episodeNumber,
            watchedDuration: epDuration,
            lastWatchedAt: DateTime.now(),
            isCompleted: true,
          );
          unawaited(_saveWatchEntryAndSync(anime, entry));

          _scheduleAutoPlayNext(
            enabled: shouldAutoPlayNext,
            hasNextEpisode: hasNextEpisode,
            playNext: playNextCallback,
          );
        },
        onVideoExtracted: (url) {
          if (videoUrls.isNotEmpty &&
              _shouldReplaceExtractedVideoUrl(
                _extractedUrls[videoUrls.first],
                url,
              )) {
            setState(() {
              _extractedUrls[videoUrls.first] = url;
            });
          }
        },
        onSubtitleExtracted: (track) {
          if (videoUrls.isNotEmpty) {
            final providerKey = videoUrls.first;
            final existingTracks =
                _extractedSubtitleTracks[providerKey] ??
                const <SubtitleTrack>[];
            final existingIndex = existingTracks.indexWhere(
              (existing) => existing.url == track.url,
            );
            final hasBetterMetadata =
                existingIndex != -1 &&
                (existingTracks[existingIndex].label.isEmpty ||
                    existingTracks[existingIndex].language.isEmpty) &&
                (track.label.isNotEmpty || track.language.isNotEmpty);
            if (existingIndex == -1 || hasBetterMetadata) {
              final nextTracks = List<SubtitleTrack>.from(existingTracks);
              if (existingIndex == -1) {
                nextTracks.add(track);
              } else {
                nextTracks[existingIndex] = track;
              }
              setState(() {
                _extractedSubtitleTracks[providerKey] = nextTracks;
                _extractedSubtitleUrls[providerKey] = track.url;
              });
            }
          }
        },
        onToggleFullscreen: _handleToggleFullscreen,
        onBack: () => _handleExitWatch(context),
      );
    }

    // Reparent the existing player state without reopening its media source.
    playerWidget = KeyedSubtree(key: _playerHostKey, child: playerWidget);

    final Widget contentWidget;
    if (_isPlayerFullscreen) {
      contentWidget = Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(child: playerWidget),
      );
    } else {
      contentWidget = Scaffold(
        backgroundColor: AppColors.primaryBg,
        body: _buildDesktopWatchPage(
          anime: anime,
          activeEpisode: activeEpisode,
          episodes: episodes,
          playerWidget: playerWidget,
          filteredProviders: filteredProviders,
          activeProvider: activeProvider,
          storageService: storageService,
          playNextCallback: playNextCallback,
          playPrevCallback: playPrevCallback,
        ),
      );
    }

    final routedContent = Focus(
      onKeyEvent: _handleDesktopWatchKey,
      child: contentWidget,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExitWatch(context);
      },
      child: routedContent,
    );
  }

  Widget _buildDesktopWatchPage({
    required Anime anime,
    required Episode activeEpisode,
    required List<Episode> episodes,
    required Widget playerWidget,
    required List<VideoProviderSource> filteredProviders,
    required VideoProviderSource? activeProvider,
    required StorageService storageService,
    VoidCallback? playNextCallback,
    VoidCallback? playPrevCallback,
  }) {
    return Column(
      children: [
        // ── Top Desktop Watch Bar ──
        _buildDesktopWatchTopBar(
          anime: anime,
          activeEpisode: activeEpisode,
          activeProvider: activeProvider,
          filteredProviders: filteredProviders,
          storageService: storageService,
        ),

        // ── Main Content Area ──
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 960;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main Player & Info (Left)
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 20, 24, 36),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 16:9 Player Container
                            Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      ((constraints.maxHeight - 160).clamp(
                                        180.0,
                                        double.infinity,
                                      )) *
                                      16 /
                                      9,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Container(
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.borderSubtle,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x66000000),
                                          blurRadius: 24,
                                          offset: Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: playerWidget,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Server Selector & Quick Actions Under Player
                            _buildDesktopQuickActionBar(
                              filteredProviders: filteredProviders,
                              activeProvider: activeProvider,
                              onPlayPrev: playPrevCallback,
                              onPlayNext: playNextCallback,
                            ),
                            const SizedBox(height: 20),

                            // Episode & Anime Info Card
                            _buildDesktopWatchInfoCard(
                              anime: anime,
                              activeEpisode: activeEpisode,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Desktop Episode Playlist Sidebar (Right)
                    SizedBox(
                      width: 390,
                      child: _buildDesktopPlaylistSidebar(
                        anime: anime,
                        activeEpisode: activeEpisode,
                        episodes: episodes,
                      ),
                    ),
                  ],
                );
              }

              // Narrow desktop layout: stacked
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: playerWidget,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDesktopQuickActionBar(
                      filteredProviders: filteredProviders,
                      activeProvider: activeProvider,
                      onPlayPrev: playPrevCallback,
                      onPlayNext: playNextCallback,
                    ),
                    const SizedBox(height: 16),
                    _buildDesktopWatchInfoCard(
                      anime: anime,
                      activeEpisode: activeEpisode,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 480,
                      child: _buildDesktopPlaylistSidebar(
                        anime: anime,
                        activeEpisode: activeEpisode,
                        episodes: episodes,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopWatchTopBar({
    required Anime anime,
    required Episode activeEpisode,
    required VideoProviderSource? activeProvider,
    required List<VideoProviderSource> filteredProviders,
    required StorageService storageService,
  }) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.primaryBg,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // Back button
          InkWell(
            onTap: () => _handleExitWatch(context),
            borderRadius: AppRadii.control,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.control,
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: AppColors.textPrimary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Details',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Breadcrumb divider
          const Text(
            '/',
            style: TextStyle(color: AppColors.borderStrong, fontSize: 14),
          ),
          const SizedBox(width: 14),

          // Breadcrumbs: Anime Title -> EP Badge -> Episode Title
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: InkWell(
                    onTap: () => _handleExitWatch(context),
                    borderRadius: AppRadii.control,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 2,
                      ),
                      child: Text(
                        anime.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandRed.withValues(alpha: 0.16),
                    borderRadius: AppRadii.control,
                    border: Border.all(
                      color: AppColors.brandRed.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    'EP ${activeEpisode.episodeNumber}',
                    style: const TextStyle(
                      color: AppColors.brandRed,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '— ${activeEpisode.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Audio toggle (SUB / DUB segmented pill)
          InkWell(
            onTap: _toggleWatchLanguage,
            borderRadius: AppRadii.control,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.control,
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedLanguage == 'DUB'
                        ? Icons.mic_rounded
                        : Icons.subtitles_rounded,
                    size: 14,
                    color: AppColors.brandRed,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Audio: $_selectedLanguage',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Fullscreen toggle button
          InkWell(
            onTap: _handleToggleFullscreen,
            borderRadius: AppRadii.control,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.brandRed.withValues(alpha: 0.14),
                borderRadius: AppRadii.control,
                border: Border.all(
                  color: AppColors.brandRed.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fullscreen_rounded,
                    size: 16,
                    color: AppColors.brandRed,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Fullscreen (F)',
                    style: TextStyle(
                      color: AppColors.brandRed,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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

  Widget _buildDesktopQuickActionBar({
    required List<VideoProviderSource> filteredProviders,
    required VideoProviderSource? activeProvider,
    VoidCallback? onPlayPrev,
    VoidCallback? onPlayNext,
  }) {
    final storageService = ref.read(storageServiceProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Previous episode button
            Tooltip(
              message: onPlayPrev != null
                  ? 'Previous Episode'
                  : 'No previous episode',
              child: InkWell(
                onTap: onPlayPrev,
                borderRadius: AppRadii.control,
                child: Opacity(
                  opacity: onPlayPrev != null ? 1.0 : 0.4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryBg,
                      borderRadius: AppRadii.control,
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.skip_previous_rounded,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Prev',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Next episode button
            Tooltip(
              message: onPlayNext != null ? 'Next Episode' : 'No next episode',
              child: InkWell(
                onTap: onPlayNext,
                borderRadius: AppRadii.control,
                child: Opacity(
                  opacity: onPlayNext != null ? 1.0 : 0.4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryBg,
                      borderRadius: AppRadii.control,
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Next',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.skip_next_rounded,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Divider
            Container(height: 20, width: 1, color: AppColors.borderSubtle),
            const SizedBox(width: 12),

            // Servers label
            const Icon(Icons.dns_rounded, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 6),
            const Text(
              'Servers:',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),

            // Server chips
            SizedBox(
              width: 480,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final provider in filteredProviders) ...[
                      Builder(
                        builder: (context) {
                          final isSelected =
                              activeProvider != null &&
                              _normalizedProviderName(provider.name) ==
                                  _normalizedProviderName(activeProvider.name);
                          final hasFailed = _providerHasFailed(provider);
                          final isTorrent =
                              provider.usesTorrentPlayer ||
                              provider.name.toLowerCase().contains('levi') ||
                              provider.name.toLowerCase().contains('eren') ||
                              provider.name.toLowerCase().contains('mikasa');

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () => _selectProvider(provider),
                              borderRadius: AppRadii.control,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.brandRed
                                      : (hasFailed
                                            ? AppColors.danger.withValues(
                                                alpha: 0.12,
                                              )
                                            : AppColors.secondaryBg),
                                  borderRadius: AppRadii.control,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.brandRed
                                        : (hasFailed
                                              ? AppColors.danger.withValues(
                                                  alpha: 0.4,
                                                )
                                              : AppColors.borderSubtle),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isTorrent)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 5,
                                        ),
                                        child: Icon(
                                          Icons.bolt_rounded,
                                          size: 13,
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.brandRed,
                                        ),
                                      ),
                                    Text(
                                      provider.name,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                        fontSize: 11.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    if (isTorrent) ...[
                                      const SizedBox(width: 5),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.white.withValues(
                                                  alpha: 0.25,
                                                )
                                              : AppColors.brandRed.withValues(
                                                  alpha: 0.15,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                        child: Text(
                                          'P2P',
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : AppColors.brandRed,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (hasFailed) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        size: 12,
                                        color: AppColors.danger,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),

            Tooltip(
              message: 'Auto play next episode',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Auto next', style: TextStyle(fontSize: 11)),
                  Switch(
                    value: storageService.getAutoPlayNext(),
                    onChanged: (value) async {
                      await storageService.setAutoPlayNext(value);
                      if (!value) _autoNextTimer?.cancel();
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Download this episode',
              child: IconButton(
                icon: const Icon(Icons.download_outlined),
                onPressed: () {
                  final anime = ref
                      .read(animeDetailsProvider(widget.animeId))
                      .value;
                  final episodes = ref
                      .read(animeEpisodesProvider(widget.animeId))
                      .value;
                  if (anime != null && episodes != null) {
                    showAnimeDownloadDialog(
                      context,
                      anime,
                      episodes
                          .where(
                            (episode) =>
                                episode.episodeNumber ==
                                _requestedEpisodeNumber(),
                          )
                          .toList(),
                    );
                  }
                },
              ),
            ),
            // DNS mode button
            Tooltip(
              message: 'Change DNS resolver mode',
              child: InkWell(
                onTap: _showDnsPicker,
                borderRadius: AppRadii.control,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBg,
                    borderRadius: AppRadii.control,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: AppColors.brandRed,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'DNS: ${storageService.getDnsModePreference()}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopWatchInfoCard({
    required Anime anime,
    required Episode activeEpisode,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.panel,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Episode ${activeEpisode.episodeNumber}: ${activeEpisode.title}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _handleExitWatch(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            anime.title,
                            style: const TextStyle(
                              color: AppColors.brandRed,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: AppColors.brandRed,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (anime.rating > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x18F59E0B),
                    borderRadius: AppRadii.control,
                    border: Border.all(color: const Color(0x35F59E0B)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 15,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        anime.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (anime.year.isNotEmpty) _buildInfoBadge(anime.year),
              if (anime.status.isNotEmpty) _buildInfoBadge(anime.status),
              _buildInfoBadge(
                '${anime.totalEpisodes > 0 ? anime.totalEpisodes : "?"} Episodes',
              ),
              if (activeEpisode.duration.inMinutes > 0)
                _buildInfoBadge(
                  '${activeEpisode.duration.inMinutes}m duration',
                ),
              for (final genre in anime.genres.take(5))
                _buildInfoBadge(genre, isGenre: true),
            ],
          ),
          if (anime.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              anime.description,
              maxLines: _isSynopsisExpanded ? null : 3,
              overflow: _isSynopsisExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.55,
              ),
            ),
            if (anime.description.length > 180) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () =>
                    setState(() => _isSynopsisExpanded = !_isSynopsisExpanded),
                child: Text(
                  _isSynopsisExpanded ? 'Show less' : 'Read more',
                  style: const TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInfoBadge(String text, {bool isGenre = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: isGenre ? AppColors.secondaryBg : AppColors.surface,
        borderRadius: AppRadii.control,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isGenre ? AppColors.textSecondary : AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDesktopPlaylistSidebar({
    required Anime anime,
    required Episode activeEpisode,
    required List<Episode> episodes,
  }) {
    final query = _playlistFilterQuery.toLowerCase();
    final filteredEpisodes = query.isEmpty
        ? episodes
        : episodes.where((ep) {
            final matchesNum = ep.episodeNumber.toString().contains(query);
            final matchesTitle = ep.title.toLowerCase().contains(query);
            return matchesNum || matchesTitle;
          }).toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.secondaryBg,
        border: Border(
          left: BorderSide(color: AppColors.borderSubtle, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle, width: 1.0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.video_library_rounded,
                      size: 18,
                      color: AppColors.brandRed,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Playlist',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.control,
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Text(
                        '${episodes.length}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Quick filter search input
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadii.control,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: TextField(
                    controller: _playlistFilterController,
                    onChanged: (val) {
                      setState(() {
                        _playlistFilterQuery = val.trim();
                      });
                    },
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      suffixIcon: _playlistFilterQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 14),
                              padding: EdgeInsets.zero,
                              color: AppColors.textMuted,
                              onPressed: () {
                                _playlistFilterController.clear();
                                setState(() {
                                  _playlistFilterQuery = '';
                                });
                              },
                            )
                          : null,
                      hintText: 'Filter episodes (e.g. 12 or title)...',
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Episode List
          Expanded(
            child: filteredEpisodes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No episodes found matching filter.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    itemCount: filteredEpisodes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 5),
                    itemBuilder: (context, index) {
                      final ep = filteredEpisodes[index];
                      final isCurrent =
                          ep.id == activeEpisode.id ||
                          ep.episodeNumber == activeEpisode.episodeNumber;

                      return InkWell(
                        onTap: () =>
                            _openEpisode(anime, ep, isCurrent: isCurrent),
                        borderRadius: AppRadii.control,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppColors.brandRed.withValues(alpha: 0.12)
                                : AppColors.surface,
                            borderRadius: AppRadii.control,
                            border: Border.all(
                              color: isCurrent
                                  ? AppColors.brandRed
                                  : AppColors.borderSubtle,
                              width: isCurrent ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Episode Number Badge
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? AppColors.brandRed
                                      : AppColors.secondaryBg,
                                  borderRadius: AppRadii.control,
                                  border: Border.all(
                                    color: isCurrent
                                        ? AppColors.brandRed
                                        : AppColors.borderSubtle,
                                  ),
                                ),
                                child: Center(
                                  child: isCurrent
                                      ? const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 20,
                                          color: Colors.white,
                                        )
                                      : Text(
                                          '${ep.episodeNumber}',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Title & Duration
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${ep.episodeNumber}. ${ep.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent
                                            ? AppColors.brandRed
                                            : AppColors.textPrimary,
                                        fontSize: 12.5,
                                        fontWeight: isCurrent
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${ep.duration.inMinutes > 0 ? ep.duration.inMinutes : 24}m',
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (isCurrent)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandRed.withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: AppColors.brandRed.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'PLAYING',
                                    style: TextStyle(
                                      color: AppColors.brandRed,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchMessageScaffold({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: DesktopPageBackdrop(
        child: SafeArea(
          child: DesktopEmptyState(
            icon: icon,
            title: title,
            message: message,
            action: action,
          ),
        ),
      ),
    );
  }

  void _selectProvider(VideoProviderSource provider) {
    _releaseTorrentStreams();
    setState(() {
      _userExplicitlySelectedProvider = true;
      final targetName = provider.name.toLowerCase().trim();
      _failedProviderKeys.removeWhere((key) => key.startsWith('$targetName|'));
      _failedProviderKeys.remove(_providerFailureKey(provider));
      _selectedProviderName = provider.name;
      _extractedUrls.clear();
      _extractedSubtitleUrls.clear();
      _extractedSubtitleTracks.clear();
      _playerReloadIndex++;
    });
    unawaited(
      ref
          .read(storageServiceProvider)
          .setDefaultServerPreference(provider.name),
    );
  }

  void _showDnsPicker() {
    final storageService = ref.read(storageServiceProvider);
    final currentDns = storageService.getDnsModePreference();
    final dnsOptions = [
      (
        name: 'Cloudflare 1.1.1.1',
        value: '1.1.1.1',
        desc: 'Fastest streaming & anti-throttling DNS (Recommended)',
        icon: Icons.flash_on_rounded,
      ),
      (
        name: 'Google 8.8.8.8',
        value: '8.8.8.8',
        desc: 'High reliability global public DNS',
        icon: Icons.public_rounded,
      ),
      (
        name: 'Quad9 9.9.9.9',
        value: '9.9.9.9',
        desc: 'Security-focused public DNS',
        icon: Icons.security_rounded,
      ),
      (
        name: 'System Default',
        value: 'Off',
        desc: 'Use your device network settings',
        icon: Icons.dns_rounded,
      ),
    ];

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (sheetContext) {
        return _watchSheetSurface(
          sheetContext: sheetContext,
          title: 'DNS Stream Resolver',
          subtitle: 'Choose the resolver used for stream requests.',
          icon: Icons.bolt_rounded,
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: dnsOptions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final option = dnsOptions[index];
              final isSelected = currentDns == option.value;
              return DesktopFocusWrapper(
                debugLabel: 'DNS ${option.name}',
                autofocus:
                    isSelected ||
                    (index == 0 &&
                        !dnsOptions.any((o) => o.value == currentDns)),
                onTap: () async {
                  if (Navigator.of(sheetContext).canPop()) {
                    Navigator.of(sheetContext).pop();
                  }
                  await storageService.setDnsModePreference(option.value);
                  if (!mounted) return;
                  setState(() {
                    _failedProviderKeys.clear();
                    _providerFailureMessages.clear();
                    _extractedUrls.clear();
                    _extractedSubtitleUrls.clear();
                    _extractedSubtitleTracks.clear();
                    _playerReloadIndex++;
                  });
                },
                borderRadius: AppRadii.control,
                focusedScale: 1,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.elevatedSurface
                        : AppColors.surface,
                    borderRadius: AppRadii.control,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.brandRed
                          : AppColors.borderSubtle,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        option.icon,
                        color: isSelected
                            ? AppColors.brandRed
                            : AppColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              option.desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandRed.withValues(alpha: 0.15),
                            borderRadius: AppRadii.control,
                            border: Border.all(
                              color: AppColors.brandRed.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: AppColors.brandRed,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openEpisode(Anime anime, Episode episode, {required bool isCurrent}) {
    if (isCurrent) {
      _setPlayerFullscreen(true);
      return;
    }
    context.replace('/watch/${anime.id}/${episode.id}');
  }

  void _toggleWatchLanguage() {
    _releaseTorrentStreams();
    setState(() {
      _selectedLanguage = _selectedLanguage == 'SUB' ? 'DUB' : 'SUB';
      _selectedProviderName = 'Gojo';
      _failedProviderKeys.clear();
      _providerFailureMessages.clear();
    });
  }

  Widget _watchSheetSurface({
    required BuildContext sheetContext,
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
    Widget? trailingHeaderBadge,
  }) {
    return Dialog(
      backgroundColor: AppColors.secondaryBg,
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: PlayerPopupFocus(
        child: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height - 80,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
                  child: Row(
                    children: [
                      Icon(icon, size: 24, color: AppColors.textSecondary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ?trailingHeaderBadge,
                      IconButton(
                        tooltip: 'Close player menu',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEpisodePicker({
    required Anime anime,
    required Episode activeEpisode,
    required List<Episode> episodes,
  }) {
    String filterQuery = '';
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (sheetContext) {
        Widget buildEpisodeList(List<Episode> list) {
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final episode = list[index];
              final isCurrent = episode.id == activeEpisode.id;
              return DesktopFocusWrapper(
                debugLabel: 'Player episode ${episode.episodeNumber}',
                autofocus: isCurrent,
                onTap: () {
                  if (Navigator.of(sheetContext).canPop()) {
                    Navigator.of(sheetContext).pop();
                  }
                  _openEpisode(anime, episode, isCurrent: isCurrent);
                },
                borderRadius: AppRadii.control,
                focusedScale: 1,
                showDefaultFocusBorder: false,
                builder: (context, isFocused, isHovered) {
                  final isActive = isFocused || isHovered;

                  final Color cardBg;
                  final Color borderColor;

                  if (isCurrent && isActive) {
                    cardBg = AppColors.activeState;
                    borderColor = AppColors.brandRed;
                  } else if (isCurrent) {
                    cardBg = AppColors.brandRed.withValues(alpha: 0.12);
                    borderColor = AppColors.brandRed;
                  } else if (isActive) {
                    cardBg = AppColors.hoverState;
                    borderColor = AppColors.borderStrong;
                  } else {
                    cardBg = AppColors.surface;
                    borderColor = AppColors.border;
                  }

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 110),
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: AppRadii.control,
                      border: Border.all(color: borderColor, width: 1.0),
                    ),
                    child: Row(
                      children: [
                        // Episode Number Tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppColors.brandRed
                                : (isActive
                                      ? AppColors.surface
                                      : AppColors.primaryBg),
                            borderRadius: AppRadii.control,
                            border: Border.all(
                              color: isCurrent
                                  ? AppColors.brandRed
                                  : AppColors.borderSubtle,
                            ),
                          ),
                          child: Text(
                            'EP ${episode.episodeNumber.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: isCurrent
                                  ? Colors.white
                                  : (isActive
                                        ? AppColors.textPrimary
                                        : AppColors.textMuted),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Title
                        Expanded(
                          child: Text(
                            episode.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent || isActive
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),

                        // Equalizer / Play Icon
                        Icon(
                          isCurrent
                              ? Icons.equalizer_rounded
                              : (isActive
                                    ? Icons.play_arrow_rounded
                                    : Icons.play_arrow_outlined),
                          color: isCurrent || isActive
                              ? AppColors.brandRed
                              : AppColors.textMuted,
                          size: 18,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        }

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final query = filterQuery.trim().toLowerCase();
            final filteredEpisodes = query.isEmpty
                ? episodes
                : episodes.where((ep) {
                    final epNum = ep.episodeNumber.toString();
                    final title = ep.title.toLowerCase();
                    return epNum.contains(query) || title.contains(query);
                  }).toList();

            return _watchSheetSurface(
              sheetContext: sheetContext,
              title: 'Episodes',
              subtitle: 'Select an episode to watch',
              icon: Icons.video_library_rounded,
              trailingHeaderBadge: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.accentPrimary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${episodes.length} EPS',
                  style: const TextStyle(
                    color: AppColors.accentPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              child: episodes.length <= 8
                  ? buildEpisodeList(filteredEpisodes)
                  : Column(
                      children: [
                        Container(
                          height: 38,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadii.control,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: TextField(
                            onChanged: (val) {
                              setDialogState(() {
                                filterQuery = val;
                              });
                            },
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Filter episode number or title...',
                              hintStyle: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                              suffixIcon: query.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 14,
                                      ),
                                      color: AppColors.textMuted,
                                      onPressed: () {
                                        setDialogState(() {
                                          filterQuery = '';
                                        });
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        Expanded(
                          child: filteredEpisodes.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Text(
                                      'No matching episodes found',
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                )
                              : buildEpisodeList(filteredEpisodes),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  void _showServerPicker({
    required List<VideoProviderSource> providers,
    required VideoProviderSource? activeProvider,
  }) {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (sheetContext) {
        final isSub = _selectedLanguage == 'SUB';
        return _watchSheetSurface(
          sheetContext: sheetContext,
          title: '$_selectedLanguage servers',
          subtitle: 'Select a server for best streaming speed & stability',
          icon: Icons.dns_rounded,
          trailingHeaderBadge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSub
                  ? AppColors.accentPrimary.withValues(alpha: 0.18)
                  : AppColors.accentSecondary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSub
                    ? AppColors.accentPrimary.withValues(alpha: 0.4)
                    : AppColors.accentSecondary.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              isSub ? 'SUBTITLED' : 'DUBBED',
              style: TextStyle(
                color: isSub
                    ? AppColors.accentPrimary
                    : AppColors.accentSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          child: providers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No servers are available for this audio track.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: providers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final provider = providers[index];
                    final currentServerName =
                        activeProvider?.name ?? _selectedProviderName;
                    final isSelected =
                        currentServerName?.toLowerCase() ==
                        provider.name.toLowerCase();
                    return DesktopFocusWrapper(
                      debugLabel: 'Player server ${provider.name}',
                      autofocus:
                          isSelected ||
                          (currentServerName == null && index == 0),
                      onTap: () {
                        if (Navigator.of(sheetContext).canPop()) {
                          Navigator.of(sheetContext).pop();
                        }
                        _selectProvider(provider);
                      },
                      borderRadius: AppRadii.control,
                      focusedScale: 1,
                      showDefaultFocusBorder: false,
                      builder: (context, isFocused, isHovered) {
                        final isActive = isFocused || isHovered;

                        final Color cardBg;
                        final Color borderColor;

                        if (isSelected && isActive) {
                          cardBg = AppColors.activeState;
                          borderColor = AppColors.brandRed;
                        } else if (isSelected) {
                          cardBg = AppColors.brandRed.withValues(alpha: 0.12);
                          borderColor = AppColors.brandRed;
                        } else if (isActive) {
                          cardBg = AppColors.hoverState;
                          borderColor = AppColors.borderStrong;
                        } else {
                          cardBg = AppColors.surface;
                          borderColor = AppColors.border;
                        }

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 110),
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: AppRadii.control,
                            border: Border.all(color: borderColor, width: 1.0),
                          ),
                          child: Row(
                            children: [
                              // Left Status Badge
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  borderRadius: AppRadii.control,
                                  color: isSelected
                                      ? AppColors.brandRed
                                      : (isActive
                                            ? AppColors.surface
                                            : AppColors.primaryBg),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.brandRed
                                        : AppColors.borderSubtle,
                                  ),
                                ),
                                child: Icon(
                                  isSelected
                                      ? Icons.check_rounded
                                      : Icons.dns_rounded,
                                  color: isSelected
                                      ? Colors.white
                                      : (isActive
                                            ? AppColors.textPrimary
                                            : AppColors.textMuted),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Center Metadata
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      provider.name,
                                      style: TextStyle(
                                        color: isSelected || isActive
                                            ? AppColors.textPrimary
                                            : AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isSelected
                                                ? AppColors.success
                                                : (provider.speedStatus
                                                              .contains(
                                                                'Fast',
                                                              ) ||
                                                          provider.speedStatus
                                                              .contains(
                                                                'Stable',
                                                              )
                                                      ? AppColors.success
                                                      : AppColors.textMuted),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          provider.speedStatus.isEmpty
                                              ? 'Stable Stream'
                                              : provider.speedStatus,
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Right Active Badge / Arrow
                              if (isSelected)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandRed.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: AppRadii.control,
                                    border: Border.all(
                                      color: AppColors.brandRed.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      color: AppColors.brandRed,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                )
                              else if (isActive)
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.textMuted,
                                  size: 18,
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildPlayerPlaceholder(
    String message, {
    bool showRetry = false,
    bool isError = false,
    VoidCallback? onRetry,
    VoidCallback? onShowEpisodes,
    VoidCallback? onShowServers,
    VoidCallback? onToggleLanguage,
  }) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned(
              top: 10,
              left: 10,
              child: DesktopFocusWrapper(
                debugLabel: 'Back',
                autofocus: true,
                onTap: () => _handleExitWatch(context),
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
            Center(
              child: RepaintBoundary(
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isError)
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: AppColors.accentPrimary,
                          size: 36,
                        )
                      else
                        const DottedSpinner(
                          size: 30,
                          color: AppColors.accentPrimary,
                        ),
                      const SizedBox(height: 14),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (showRetry) ...[
                        const SizedBox(height: 16),
                        DesktopFocusWrapper(
                          debugLabel: 'Retry stream',
                          autofocus: true,
                          onTap: () {
                            if (onRetry != null) {
                              onRetry();
                            } else {
                              ref.invalidate(videoProvidersProvider);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          focusedScale: 1.03,
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentPrimary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                  color: Colors.black,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Retry',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (onShowEpisodes != null ||
                          onShowServers != null ||
                          onToggleLanguage != null) ...[
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onShowEpisodes != null)
                              _buildPlaceholderAction(
                                icon: Icons.video_library_rounded,
                                label: 'Open episodes',
                                autofocus: !showRetry,
                                onTap: onShowEpisodes,
                              ),
                            if (onShowEpisodes != null && onShowServers != null)
                              const SizedBox(width: 8),
                            if (onShowServers != null)
                              _buildPlaceholderAction(
                                icon: Icons.dns_rounded,
                                label: 'Switch server',
                                autofocus: !showRetry && onShowEpisodes == null,
                                onTap: onShowServers,
                              ),
                            if ((onShowEpisodes != null ||
                                    onShowServers != null) &&
                                onToggleLanguage != null)
                              const SizedBox(width: 8),
                            if (onToggleLanguage != null)
                              _buildPlaceholderAction(
                                icon: _selectedLanguage == 'DUB'
                                    ? Icons.mic_rounded
                                    : Icons.subtitles_rounded,
                                label: _selectedLanguage,
                                onTap: onToggleLanguage,
                              ),
                            const SizedBox(width: 8),
                            _buildPlaceholderAction(
                              icon: Icons.bolt_rounded,
                              label:
                                  'DNS: ${ref.read(storageServiceProvider).getDnsModePreference()}',
                              onTap: _showDnsPicker,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool autofocus = false,
  }) {
    return DesktopFocusWrapper(
      debugLabel: 'Player $label',
      autofocus: autofocus,
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      focusedScale: 1.03,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: AppColors.elevatedSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textPrimary, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
