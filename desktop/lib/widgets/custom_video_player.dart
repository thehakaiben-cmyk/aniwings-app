import 'subtitle_delay_control.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import '../core/focus/desktop_navigation_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/services/playback_clock.dart';
import '../models/video_provider.dart';
import '../models/episode_skip_times.dart';
import 'desktop_focus_wrapper.dart';
import 'player_popup_focus.dart';

class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

class _ResolvedVideoSource {
  final String url;
  final String label;
  final String preference;
  final int? height;
  final int? bandwidth;

  const _ResolvedVideoSource({
    required this.url,
    required this.label,
    required this.preference,
    this.height,
    this.bandwidth,
  });
}

class _HlsSubtitleSegment {
  final Uri uri;
  final Duration offset;

  const _HlsSubtitleSegment({required this.uri, required this.offset});
}

class _SubtitleLanguageChoice {
  final String label;
  final String preference;
  final List<String> aliases;

  const _SubtitleLanguageChoice({
    required this.label,
    required this.preference,
    required this.aliases,
  });
}

class CustomVideoPlayer extends StatefulWidget {
  final List<String> videoUrls;
  final EpisodeSkipTimes skipTimes;
  final Future<EpisodeSkipTimes> Function(Duration duration)? loadSkipTimes;
  final String animeTitle;
  final String episodeTitle;
  final Duration initialPosition;
  final VoidCallback? onVideoEnded;
  final VoidCallback? onPlayNext;
  final VoidCallback? onPlayPrev;
  final VoidCallback? onPlaybackFailed;
  final ValueChanged<String>? onPlaybackError;
  final Function(Duration position)? onPositionChanged;
  final Map<String, String>? headers;
  final VoidCallback? onBack;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;
  final String? subtitleUrl;
  final List<SubtitleTrack>? subtitleTracks;
  final String? preferredVideoQuality;
  final String? preferredSubtitleLanguage;
  final double subtitleFontSize;
  final String subtitleTextStyle;
  final int subtitleTextColor;
  final int? subtitleBackgroundColor;
  final double subtitleBottomPosition;
  final double subtitleTextShadow;
  final double subtitleBackgroundOpacity;
  final double initialPlaybackSpeed;
  final String initialVideoDisplayMode;
  final ValueChanged<String>? onQualityPreferenceChanged;
  final ValueChanged<String>? onSubtitlePreferenceChanged;
  final ValueChanged<double>? onPlaybackSpeedChanged;
  final ValueChanged<String>? onVideoDisplayModeChanged;

  /// Opens the episode picker from the player overlay.
  final VoidCallback? onShowEpisodes;

  /// Opens the server picker from the player overlay.
  final VoidCallback? onShowServers;

  /// Switches between the currently available SUB and DUB streams.
  final VoidCallback? onToggleLanguage;
  final String languageLabel;
  final String? serverLabel;
  final bool autofocus;
  final bool autoPlayNext;
  final bool alwaysShowControls;
  final bool autoSkipIntroOutro;
  final bool showSkipButtons;
  final bool showTopBarInWindowed;

  const CustomVideoPlayer({
    super.key,
    required this.videoUrls,
    this.skipTimes = const EpisodeSkipTimes(),
    this.loadSkipTimes,
    required this.animeTitle,
    required this.episodeTitle,
    this.initialPosition = Duration.zero,
    this.onVideoEnded,
    this.onPlayNext,
    this.onPlayPrev,
    this.onPlaybackFailed,
    this.onPlaybackError,
    this.onPositionChanged,
    this.headers,
    this.onBack,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.subtitleUrl,
    this.subtitleTracks,
    this.preferredVideoQuality,
    this.preferredSubtitleLanguage,
    this.subtitleFontSize = 14.0,
    this.subtitleTextStyle = 'normal',
    this.subtitleTextColor = 0xFFFFFFFF,
    this.subtitleBackgroundColor = 0xFF000000,
    this.subtitleBottomPosition = 0.0,
    this.subtitleTextShadow = 0.55,
    this.subtitleBackgroundOpacity = 0.78,
    this.initialPlaybackSpeed = 1.0,
    this.initialVideoDisplayMode = 'fit_16_9',
    this.onQualityPreferenceChanged,
    this.onSubtitlePreferenceChanged,
    this.onPlaybackSpeedChanged,
    this.onVideoDisplayModeChanged,
    this.onShowEpisodes,
    this.onShowServers,
    this.onToggleLanguage,
    this.languageLabel = 'SUB',
    this.serverLabel,
    this.autofocus = true,
    this.autoPlayNext = true,
    this.alwaysShowControls = false,
    this.autoSkipIntroOutro = false,
    this.showSkipButtons = true,
    this.showTopBarInWindowed = false,
  });

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  static const List<_SubtitleLanguageChoice> _preferredSubtitleLanguages = [
    _SubtitleLanguageChoice(
      label: 'English',
      preference: 'English',
      aliases: ['en', 'eng', 'english'],
    ),
    _SubtitleLanguageChoice(
      label: 'Portuguese',
      preference: 'Portuguese',
      aliases: ['pt', 'pt-br', 'por', 'portuguese', 'portugues', 'brazilian'],
    ),
    _SubtitleLanguageChoice(
      label: 'Spanish',
      preference: 'Spanish',
      aliases: ['es', 'spa', 'spanish', 'espanol', 'castilian', 'castellano'],
    ),
  ];

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isBuffering = false;
  final bool _isLocked = false;
  bool _hasError = false;
  bool _isSlowLoad = false; // true after 8s to show 'Slow connection...' hint
  bool _hasReportedPlaybackFailure = false;
  String? _playbackClockError;
  int _selectedQualityIndex = 0;
  int _selectedSubtitleTrackIndex = 0;
  bool _subtitlesEnabled = true;
  double _playbackSpeed = 1.0;
  int _subtitleDelayMilliseconds = 0;
  String _videoDisplayMode = 'fit_16_9';
  Size _lastVideoSize = Size.zero;
  List<SubtitleCue> _subCues = [];
  SubtitleCue? _currentCue;
  DateTime _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  List<_ResolvedVideoSource> _qualitySources = const [];
  List<SubtitleTrack> _hlsSubtitleTracks = const [];
  String _subtitleLanguagePreference = 'English';
  String? _qualitySourceSignature;
  int _subtitleLoadToken = 0;
  int _playerLoadToken = 0;

  // Guard to prevent calling onVideoEnded more than once per video
  bool _hasCalledOnEnded = false;

  Timer? _hideControlsTimer;
  Timer? _loadingTimeoutTimer;
  Timer? _slowLoadTimer;
  Duration _currentPosition = Duration.zero;
  Duration _duration = Duration.zero;
  EpisodeSkipTimes _skipTimes = const EpisodeSkipTimes();
  final Set<int> _automaticallySkipped = {};
  bool _skipSeekInFlight = false;
  Duration? _pendingSeekPosition;
  Timer? _pendingSeekDebounce;

  // Double-tap feedback states
  bool _showRewindIndicator = false;
  bool _showForwardIndicator = false;
  Timer? _rewindTimer;
  Timer? _forwardTimer;
  late final FocusNode _playerFocusNode;
  late final FocusNode _playPauseFocusNode;
  late final FocusNode _topBackFocusNode;
  late final FocusNode _episodesFocusNode;
  late final FocusNode _serverFocusNode;
  late final FocusNode _languageFocusNode;
  late final FocusNode _speedFocusNode;
  late final FocusNode _subtitleFocusNode;
  late final FocusNode _settingsFocusNode;
  late final FocusNode _lockFocusNode;
  late final FocusNode _rewindFocusNode;
  late final FocusNode _previousFocusNode;
  late final FocusNode _nextFocusNode;
  late final FocusNode _forwardFocusNode;
  late final FocusNode _fullscreenFocusNode;
  late final FocusNode _skipIntroFocusNode;
  late final FocusNode _skipOutroFocusNode;
  late final FocusNode _autoNextPlayFocusNode;
  bool _dismissedAutoNext = false;
  bool _playerHasFocus = false;
  double _volume = 1.0;
  bool _isMuted = false;
  double _preMuteVolume = 1.0;

  void _toggleMute() {
    setState(() {
      if (_isMuted) {
        _isMuted = false;
        _volume = _preMuteVolume > 0.05 ? _preMuteVolume : 1.0;
      } else {
        _preMuteVolume = _volume;
        _isMuted = true;
        _volume = 0.0;
      }
    });
    _controller?.setVolume(_volume);
    _interactWithControls();
  }

  void _setVolume(double newVolume) {
    setState(() {
      _volume = newVolume.clamp(0.0, 1.0);
      _isMuted = _volume == 0.0;
    });
    _controller?.setVolume(_volume);
    _interactWithControls();
  }

  void _adjustVolume(double delta) {
    _setVolume(_volume + delta);
  }

  @override
  void initState() {
    super.initState();
    _playerFocusNode = FocusNode(debugLabel: 'Video player');
    _playPauseFocusNode = FocusNode(debugLabel: 'Play or pause');
    _topBackFocusNode = FocusNode(debugLabel: 'Player back');
    _episodesFocusNode = FocusNode(debugLabel: 'Player episodes');
    _serverFocusNode = FocusNode(debugLabel: 'Player server');
    _languageFocusNode = FocusNode(debugLabel: 'Player audio language');
    _speedFocusNode = FocusNode(debugLabel: 'Playback speed');
    _subtitleFocusNode = FocusNode(debugLabel: 'Player subtitles');
    _settingsFocusNode = FocusNode(debugLabel: 'Player settings');
    _lockFocusNode = FocusNode(debugLabel: 'Lock controls');
    _rewindFocusNode = FocusNode(debugLabel: 'Rewind 10 seconds');
    _previousFocusNode = FocusNode(debugLabel: 'Previous episode');
    _nextFocusNode = FocusNode(debugLabel: 'Next episode');
    _forwardFocusNode = FocusNode(debugLabel: 'Forward 10 seconds');
    _fullscreenFocusNode = FocusNode(debugLabel: 'Fullscreen');
    _skipIntroFocusNode = FocusNode(debugLabel: 'Skip Intro');
    _skipOutroFocusNode = FocusNode(debugLabel: 'Skip Outro');
    _autoNextPlayFocusNode = FocusNode(debugLabel: 'Auto Next Play');
    _subtitleLanguagePreference = _normalizedSubtitlePreference(
      widget.preferredSubtitleLanguage,
    );
    _selectedQualityIndex = _qualityIndexForPreference();
    _selectedSubtitleTrackIndex = _subtitleTrackIndexForPreference();
    _subtitlesEnabled = !_subtitlePreferenceDisablesCaptions();
    _playbackSpeed = _normalizedPlaybackSpeed(widget.initialPlaybackSpeed);
    _videoDisplayMode = widget.initialVideoDisplayMode;
    _initializePlayer();
    unawaited(_loadSubtitles());
    _startHideControlsTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus) {
        _playerFocusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CustomVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.isFullscreen && widget.isFullscreen) ||
        (!oldWidget.autofocus && widget.autofocus)) {
      _showControls = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _playerFocusNode.requestFocus();
        _startHideControlsTimer();
      });
    } else if (oldWidget.alwaysShowControls && !widget.alwaysShowControls) {
      _startHideControlsTimer();
    }

    if (!listEquals(oldWidget.videoUrls, widget.videoUrls) ||
        oldWidget.episodeTitle != widget.episodeTitle) {
      _videoDisplayMode = 'fit_16_9';
      _hasCalledOnEnded = false;
      _hasReportedPlaybackFailure = false;
      _subCues.clear();
      _qualitySources = const [];
      _hlsSubtitleTracks = const [];
      _qualitySourceSignature = null;
      _subtitleLanguagePreference = _normalizedSubtitlePreference(
        widget.preferredSubtitleLanguage,
      );
      _selectedQualityIndex = _qualityIndexForPreference();
      _selectedSubtitleTrackIndex = _subtitleTrackIndexForPreference();
      _subtitlesEnabled = !_subtitlePreferenceDisablesCaptions();
      _deinitializePlayer();
      _initializePlayer();
      unawaited(_loadSubtitles());
    } else if (oldWidget.subtitleUrl != widget.subtitleUrl ||
        _subtitleTracksSignature(oldWidget.subtitleTracks) !=
            _subtitleTracksSignature(widget.subtitleTracks) ||
        oldWidget.preferredSubtitleLanguage !=
            widget.preferredSubtitleLanguage) {
      _subCues.clear();
      _subtitleLanguagePreference = _normalizedSubtitlePreference(
        widget.preferredSubtitleLanguage,
      );
      _selectedSubtitleTrackIndex = _subtitleTrackIndexForPreference();
      _subtitlesEnabled = !_subtitlePreferenceDisablesCaptions();
      unawaited(_loadSubtitles());
    }

    if (oldWidget.initialPlaybackSpeed != widget.initialPlaybackSpeed) {
      final nextSpeed = _normalizedPlaybackSpeed(widget.initialPlaybackSpeed);
      if (nextSpeed != _playbackSpeed) {
        setState(() => _playbackSpeed = nextSpeed);
        final controller = _controller;
        if (controller != null) {
          unawaited(controller.setPlaybackSpeed(nextSpeed));
        }
      }
    }

    if (oldWidget.preferredVideoQuality != widget.preferredVideoQuality &&
        widget.videoUrls.length > 1) {
      final nextIndex = _qualityIndexForPreference();
      if (nextIndex != _selectedQualityIndex) {
        _changeQuality(nextIndex, notifyPreference: false);
      }
    }
  }

  @override
  void dispose() {
    _deinitializePlayer();
    _hideControlsTimer?.cancel();
    _loadingTimeoutTimer?.cancel();
    _slowLoadTimer?.cancel();
    _rewindTimer?.cancel();
    _forwardTimer?.cancel();
    _pendingSeekDebounce?.cancel();
    _playerFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _topBackFocusNode.dispose();
    _episodesFocusNode.dispose();
    _serverFocusNode.dispose();
    _languageFocusNode.dispose();
    _speedFocusNode.dispose();
    _subtitleFocusNode.dispose();
    _settingsFocusNode.dispose();
    _lockFocusNode.dispose();
    _rewindFocusNode.dispose();
    _previousFocusNode.dispose();
    _nextFocusNode.dispose();
    _forwardFocusNode.dispose();
    _fullscreenFocusNode.dispose();
    _skipIntroFocusNode.dispose();
    _skipOutroFocusNode.dispose();
    _autoNextPlayFocusNode.dispose();
    super.dispose();
  }

  int _activeSkipType(Duration position) {
    if (_skipTimes.intro?.contains(position) == true) return 1;
    if (_skipTimes.outro?.contains(position) == true) return 2;
    return 0;
  }

  Future<void> _loadSkipTimes(int loadToken, Duration duration) async {
    final supplied = widget.skipTimes.validatedFor(duration);
    if (_isActivePlayerLoad(loadToken)) setState(() => _skipTimes = supplied);
    final loader = widget.loadSkipTimes;
    if (loader == null || (supplied.intro != null && supplied.outro != null)) {
      return;
    }
    try {
      final fetched = (await loader(duration)).validatedFor(duration);
      if (!_isActivePlayerLoad(loadToken)) return;
      setState(() {
        _skipTimes = EpisodeSkipTimes(
          intro: supplied.intro ?? fetched.intro,
          outro: supplied.outro ?? fetched.outro,
        );
      });
    } catch (_) {
      // Missing timing data must never block playback or create a guessed skip.
    }
  }

  void _skipIntro() => unawaited(_seekPastInterval(_skipTimes.intro));
  void _skipOutro() => unawaited(_seekPastInterval(_skipTimes.outro));

  Future<void> _seekPastInterval(SkipInterval? interval) async {
    final controller = _controller;
    if (interval == null ||
        controller == null ||
        !_isInitialized ||
        _skipSeekInFlight ||
        !interval.isValidFor(_duration) ||
        !interval.contains(_currentPosition)) {
      return;
    }
    final loadToken = _playerLoadToken;
    _interactWithControls();
    _skipSeekInFlight = true;
    try {
      await controller.seekTo(interval.end);
    } finally {
      _skipSeekInFlight = false;
    }
    if (!_isActiveController(loadToken, controller)) return;
    final skipHadFocus =
        _skipIntroFocusNode.hasFocus || _skipOutroFocusNode.hasFocus;
    setState(() => _currentPosition = interval.end);
    if (skipHadFocus) _playPauseFocusNode.requestFocus();
  }

  bool get _showAutoNextOverlay =>
      widget.autoPlayNext &&
      _isInitialized &&
      _duration.inSeconds > 60 &&
      _currentPosition >= _duration - const Duration(seconds: 35) &&
      widget.onPlayNext != null &&
      !_dismissedAutoNext;

  Widget _buildSkipAction(bool intro) {
    return Positioned(
      bottom:
          (_showControls ? 120.0 : 50.0) + (_showAutoNextOverlay ? 180.0 : 0.0),
      right: 36,
      child: DesktopFocusWrapper(
        key: ValueKey(intro ? 'skip-intro' : 'skip-outro'),
        focusNode: intro ? _skipIntroFocusNode : _skipOutroFocusNode,
        onTap: intro ? _skipIntro : _skipOutro,
        directionalKeyHandlers: _playerDirections(
          left: _playPauseFocusNode,
          down: _playPauseFocusNode,
          up: _settingsFocusNode,
        ),
        borderRadius: AppRadii.control,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xEE161822),
            borderRadius: AppRadii.control,
            border: Border.all(color: AppColors.borderStrong, width: 1.0),
            boxShadow: const [AppColors.shadowSoft],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.fast_forward_rounded,
                color: AppColors.brandRed,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                intro ? 'Skip Intro' : 'Skip Outro',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _normalizedPlaybackSpeed(double speed) {
    if (speed.isNaN || speed.isInfinite) return 1.0;
    return speed.clamp(0.25, 4.0).toDouble();
  }

  List<_ResolvedVideoSource> _fallbackQualitySources() {
    if (widget.videoUrls.isEmpty) return const [];

    if (widget.videoUrls.length <= 1) {
      return [
        _ResolvedVideoSource(
          url: widget.videoUrls.first,
          label: _isHlsUrl(widget.videoUrls.first)
              ? 'Auto (Adaptive HLS)'
              : 'Auto',
          preference: 'Auto',
        ),
      ];
    }

    const labels = ['1080p (FHD)', '720p (HD)', '480p (SD)', '360p (Low)'];
    const values = ['1080p', '720p', '480p', '360p'];

    return List.generate(
      widget.videoUrls.length,
      (i) => _ResolvedVideoSource(
        url: widget.videoUrls[i],
        label: i < labels.length ? labels[i] : 'Source ${i + 1}',
        preference: i < values.length ? values[i] : 'Source ${i + 1}',
        height: i < values.length
            ? int.tryParse(values[i].replaceAll('p', ''))
            : null,
      ),
    );
  }

  List<_ResolvedVideoSource> _availableQualitySources() {
    return _qualitySources.isNotEmpty
        ? _qualitySources
        : _fallbackQualitySources();
  }

  List<SubtitleTrack> _availableSubtitleTracks() {
    final tracks = <SubtitleTrack>[];
    final seenUrls = <String>{};

    void addTrack(SubtitleTrack track) {
      final url = track.url.trim();
      if (url.isEmpty || !seenUrls.add(url)) return;
      tracks.add(track);
    }

    for (final track in widget.subtitleTracks ?? const <SubtitleTrack>[]) {
      addTrack(track);
    }
    for (final track in _hlsSubtitleTracks) {
      addTrack(track);
    }

    final subtitleUrl = widget.subtitleUrl?.trim();
    if (subtitleUrl != null && subtitleUrl.isNotEmpty) {
      final existingIndex = tracks.indexWhere(
        (track) => track.url.trim() == subtitleUrl,
      );
      if (existingIndex == -1) {
        addTrack(
          SubtitleTrack(label: 'English', language: 'en', url: subtitleUrl),
        );
      } else if (tracks[existingIndex].label.isEmpty &&
          tracks[existingIndex].language.isEmpty) {
        tracks[existingIndex] = SubtitleTrack(
          label: 'English',
          language: 'en',
          url: subtitleUrl,
        );
      }
    }

    return tracks;
  }

  List<String> _qualityOptions() {
    final sources = _availableQualitySources();
    if (sources.isEmpty) return const ['Auto'];
    return sources.map((source) => source.label).toList();
  }

  int _qualityIndexForPreference() {
    final sources = _availableQualitySources();
    if (sources.length <= 1) return 0;

    final preference = widget.preferredVideoQuality?.toLowerCase().trim() ?? '';
    if (preference.isEmpty || preference.contains('auto')) return 0;

    final exactIndex = sources.indexWhere((source) {
      return source.preference.toLowerCase() == preference ||
          source.label.toLowerCase() == preference;
    });
    if (exactIndex != -1) return exactIndex;

    final heightMatch = RegExp(
      r'(2160|1440|1080|720|480|360|240)',
    ).firstMatch(preference);
    if (heightMatch != null) {
      final height = heightMatch.group(1)!;
      final heightIndex = sources.indexWhere((source) {
        return source.preference.contains(height) ||
            source.label.contains(height);
      });
      if (heightIndex != -1) return heightIndex;
    }

    final fuzzyIndex = sources.indexWhere((source) {
      final label = source.label.toLowerCase();
      final sourcePreference = source.preference.toLowerCase();
      return label.contains(preference) ||
          sourcePreference.contains(preference);
    });
    if (fuzzyIndex != -1) return fuzzyIndex;

    return 0;
  }

  String _qualityPreferenceForIndex(int index) {
    final sources = _availableQualitySources();
    if (sources.isEmpty || index >= sources.length) return 'Auto';
    return sources[index].preference;
  }

  String _subtitleTracksSignature(List<SubtitleTrack>? tracks) {
    if (tracks == null || tracks.isEmpty) return '';
    return tracks
        .map((track) => '${track.language}|${track.label}|${track.url}')
        .join('\n');
  }

  String _normalizedSubtitlePreference(String? preference) {
    final trimmed = preference?.trim();
    if (trimmed == null || trimmed.isEmpty) return 'English';
    return trimmed;
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

  bool _subtitlePreferenceDisablesCaptions() {
    final preference = _subtitleLanguagePreference.toLowerCase().trim();
    return preference == 'off' ||
        preference == 'none' ||
        preference == 'disabled';
  }

  _SubtitleLanguageChoice? _subtitleLanguageChoiceForPreference(
    String preference,
  ) {
    final normalizedPreference = _normalizedSubtitleSearchText(preference);
    for (final choice in _preferredSubtitleLanguages) {
      if (choice.preference.toLowerCase() == normalizedPreference ||
          choice.label.toLowerCase() == normalizedPreference ||
          choice.aliases.contains(normalizedPreference)) {
        return choice;
      }
    }
    return null;
  }

  bool _trackMatchesSubtitleLanguage(
    SubtitleTrack track,
    _SubtitleLanguageChoice choice,
  ) {
    final language = _normalizedSubtitleSearchText(track.language);
    final label = _normalizedSubtitleSearchText(track.label);

    for (final alias in choice.aliases) {
      if (alias.length <= 3) {
        if (language == alias || language.startsWith('$alias-')) {
          return true;
        }
        continue;
      }

      if (language == alias || label.contains(alias)) {
        return true;
      }
    }

    return false;
  }

  _SubtitleLanguageChoice? _subtitleLanguageChoiceForTrack(
    SubtitleTrack track,
  ) {
    for (final choice in _preferredSubtitleLanguages) {
      if (_trackMatchesSubtitleLanguage(track, choice)) return choice;
    }
    return null;
  }

  int _subtitleTrackIndexForLanguage(
    List<SubtitleTrack> tracks,
    _SubtitleLanguageChoice choice,
  ) {
    return tracks.indexWhere(
      (track) => _trackMatchesSubtitleLanguage(track, choice),
    );
  }

  bool _isEnglishSubtitleTrack(SubtitleTrack track) {
    return _trackMatchesSubtitleLanguage(
      track,
      _preferredSubtitleLanguages.first,
    );
  }

  int _englishSubtitleTrackIndex(List<SubtitleTrack> tracks) {
    return tracks.indexWhere(_isEnglishSubtitleTrack);
  }

  bool _isGenericSubtitlePreference(String preference) {
    return preference == 'on' ||
        preference == 'enabled' ||
        preference == 'true' ||
        preference == 'auto' ||
        preference == 'default' ||
        preference == 'subtitles' ||
        preference == 'captions';
  }

  int _subtitleTrackIndexForPreference() {
    final tracks = _availableSubtitleTracks();
    if (tracks.isEmpty) return 0;

    final preference = _normalizedSubtitleSearchText(
      _subtitleLanguagePreference,
    );
    if (preference.isNotEmpty &&
        !_isGenericSubtitlePreference(preference) &&
        !_subtitlePreferenceDisablesCaptions()) {
      final exactIndex = tracks.indexWhere((track) {
        return _normalizedSubtitleSearchText(track.language) == preference ||
            _normalizedSubtitleSearchText(track.label) == preference;
      });
      if (exactIndex != -1) return exactIndex;

      final languageChoice = _subtitleLanguageChoiceForPreference(preference);
      if (languageChoice != null) {
        final languageIndex = _subtitleTrackIndexForLanguage(
          tracks,
          languageChoice,
        );
        if (languageIndex != -1) return languageIndex;
        return -1;
      }

      final fuzzyIndex = tracks.indexWhere((track) {
        final language = _normalizedSubtitleSearchText(track.language);
        final label = _normalizedSubtitleSearchText(track.label);
        return (language.isNotEmpty && language.contains(preference)) ||
            (label.isNotEmpty && label.contains(preference)) ||
            (language.isNotEmpty && preference.contains(language)) ||
            (label.isNotEmpty && preference.contains(label));
      });
      if (fuzzyIndex != -1) return fuzzyIndex;
    }

    final englishIndex = _englishSubtitleTrackIndex(tracks);
    if (englishIndex != -1) return englishIndex;

    final subtitleUrl = widget.subtitleUrl;
    if (subtitleUrl != null && subtitleUrl.isNotEmpty) {
      final urlIndex = tracks.indexWhere((track) => track.url == subtitleUrl);
      if (urlIndex != -1) return urlIndex;
    }

    return 0;
  }

  String? _selectedSubtitleUrl() {
    if (!_subtitlesEnabled) return null;

    final tracks = _availableSubtitleTracks();
    if (tracks.isNotEmpty) {
      if (_selectedSubtitleTrackIndex < 0) return null;
      if (_selectedSubtitleTrackIndex >= 0 &&
          _selectedSubtitleTrackIndex < tracks.length) {
        return tracks[_selectedSubtitleTrackIndex].url;
      }
      final englishIndex = _englishSubtitleTrackIndex(tracks);
      return englishIndex == -1
          ? (widget.subtitleUrl ?? tracks.first.url)
          : tracks[englishIndex].url;
    }

    final languageChoice = _subtitleLanguageChoiceForPreference(
      _subtitleLanguagePreference,
    );
    return languageChoice == null ? widget.subtitleUrl : null;
  }

  String _selectedSubtitlePreferenceLabel() {
    final tracks = _availableSubtitleTracks();
    if (tracks.isNotEmpty &&
        _selectedSubtitleTrackIndex >= 0 &&
        _selectedSubtitleTrackIndex < tracks.length) {
      final track = tracks[_selectedSubtitleTrackIndex];
      final choice = _subtitleLanguageChoiceForTrack(track);
      if (choice != null) return choice.preference;
      if (track.language.isNotEmpty) return track.language;
      if (track.label.isNotEmpty) return track.label;
    }

    return _subtitleLanguagePreference;
  }

  String _subtitleStatusLabel() {
    if (!_subtitlesEnabled) return 'Off';
    final preferenceChoice = _subtitleLanguageChoiceForPreference(
      _subtitleLanguagePreference,
    );
    if (preferenceChoice != null) return preferenceChoice.label;

    final tracks = _availableSubtitleTracks();
    if (tracks.isNotEmpty &&
        _selectedSubtitleTrackIndex >= 0 &&
        _selectedSubtitleTrackIndex < tracks.length) {
      final track = tracks[_selectedSubtitleTrackIndex];
      final choice = _subtitleLanguageChoiceForTrack(track);
      if (choice != null) return choice.label;
      return 'On';
    }
    return _subtitleLanguagePreference.toLowerCase() == 'off' ? 'Off' : 'On';
  }

  Uri? _resolveSubtitleUri(String url) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return null;
    if (trimmedUrl.startsWith('//')) {
      return Uri.tryParse('https:$trimmedUrl');
    }

    final parsed = Uri.tryParse(trimmedUrl);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;

    String? activeVideoUrl;
    final sources = _availableQualitySources();
    if (sources.isNotEmpty) {
      final activeVideoIndex = _selectedQualityIndex
          .clamp(0, sources.length - 1)
          .toInt();
      activeVideoUrl = sources[activeVideoIndex].url;
    }
    final activeVideoUri = activeVideoUrl == null
        ? null
        : Uri.tryParse(activeVideoUrl);
    if (activeVideoUri != null &&
        activeVideoUri.hasScheme &&
        activeVideoUri.hasAuthority) {
      return activeVideoUri.resolve(trimmedUrl);
    }

    return null;
  }

  Future<void> _loadSubtitles() async {
    final loadToken = ++_subtitleLoadToken;
    final subUrl = _selectedSubtitleUrl();
    final uri = subUrl == null ? null : _resolveSubtitleUri(subUrl);

    if (uri == null) {
      if (mounted && _subCues.isNotEmpty) {
        setState(() => _subCues = []);
      }
      return;
    }

    try {
      if (uri.scheme == 'file') {
        final body = await File.fromUri(uri).readAsString();
        if (mounted && loadToken == _subtitleLoadToken) {
          setState(() {
            _subCues = _parseVttOrSrt(body);
            _currentCue = _subCues
                .where(
                  (cue) =>
                      _currentPosition >= cue.start &&
                      _currentPosition <= cue.end,
                )
                .firstOrNull;
          });
        }
        return;
      }
      final headers = Map<String, String>.from(widget.headers ?? {});
      if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
      }
      headers.putIfAbsent(
        'Accept',
        () =>
            'text/vtt, application/x-subrip, application/vnd.apple.mpegurl, */*',
      );

      final res = await _getSubtitleResponse(uri, headers);

      if (res != null &&
          res.statusCode == 200 &&
          mounted &&
          loadToken == _subtitleLoadToken) {
        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final parsed = _looksLikeHlsPlaylist(body)
            ? await _loadHlsSubtitleCues(uri, headers, body)
            : _parseVttOrSrt(body);
        if (!mounted || loadToken != _subtitleLoadToken) return;
        setState(() {
          _subCues = parsed;
        });
      } else if (mounted && loadToken == _subtitleLoadToken) {
        setState(() => _subCues = []);
      }
    } catch (error) {
      debugPrint('Subtitle load failed: $error');
    }
  }

  Future<http.Response?> _getSubtitleResponse(
    Uri uri,
    Map<String, String> headers,
  ) async {
    http.Response? lastResponse;
    try {
      lastResponse = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (lastResponse.statusCode == 200) return lastResponse;
    } catch (_) {}

    MapEntry<String, String>? userAgentEntry;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'user-agent') {
        userAgentEntry = entry;
        break;
      }
    }
    final fallbackHeaders = <String, String>{
      if (userAgentEntry != null) 'User-Agent': userAgentEntry.value,
      'Accept':
          'text/vtt, application/x-subrip, application/vnd.apple.mpegurl, */*',
    };

    try {
      final fallbackResponse = await http
          .get(uri, headers: fallbackHeaders)
          .timeout(const Duration(seconds: 8));
      return fallbackResponse.statusCode == 200
          ? fallbackResponse
          : lastResponse ?? fallbackResponse;
    } catch (_) {
      return lastResponse;
    }
  }

  bool _isHlsUrl(String url) {
    final lowerUrl = url.toLowerCase();
    final parsed = Uri.tryParse(url);
    return lowerUrl.contains('.m3u8') ||
        (parsed?.path.toLowerCase().endsWith('.m3u8') ?? false);
  }

  bool _looksLikeHlsPlaylist(String content) {
    return content.contains('#EXTM3U') &&
        (content.contains('#EXT-X-STREAM-INF') ||
            content.contains('#EXT-X-MEDIA') ||
            content.contains('#EXTINF'));
  }

  Future<void> _ensureQualitySources(int loadToken) async {
    final signature = widget.videoUrls.join('\n');
    if (_qualitySourceSignature == signature) return;

    _qualitySourceSignature = signature;
    _qualitySources = const [];
    _hlsSubtitleTracks = const [];

    if (widget.videoUrls.length != 1 || !_isHlsUrl(widget.videoUrls.first)) {
      return;
    }

    final uri = Uri.tryParse(widget.videoUrls.first);
    if (uri == null || !uri.hasScheme) return;

    final headers = Map<String, String>.from(widget.headers ?? {});
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
    }
    headers.putIfAbsent(
      'Accept',
      () => 'application/vnd.apple.mpegurl, application/x-mpegURL, */*',
    );

    try {
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 5));
      if (!mounted || loadToken != _playerLoadToken) return;
      _playbackClockError = playbackClockError(
        response.headers['date'],
        DateTime.now(),
        responseAge: response.headers['age'],
      );
      if (response.statusCode != 200) return;

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (!body.contains('#EXTM3U')) return;

      final parsedSources = _parseHlsQualitySources(body, uri);
      final parsedSubtitleTracks = _parseHlsSubtitleTracks(body, uri);
      if (parsedSources.length <= 1 && parsedSubtitleTracks.isEmpty) return;

      setState(() {
        if (parsedSources.length > 1) {
          _qualitySources = parsedSources;
          _selectedQualityIndex = _qualityIndexForPreference();
        }
        if (parsedSubtitleTracks.isNotEmpty) {
          _hlsSubtitleTracks = parsedSubtitleTracks;
          if (widget.subtitleTracks == null || widget.subtitleTracks!.isEmpty) {
            _selectedSubtitleTrackIndex = _subtitleTrackIndexForPreference();
            _subtitlesEnabled = !_subtitlePreferenceDisablesCaptions();
          }
        }
      });

      if (_isInitialized && _controller != null && parsedSources.length > 1) {
        final desiredIndex = _qualityIndexForPreference();
        if (desiredIndex != 0 && desiredIndex != _selectedQualityIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_isActivePlayerLoad(loadToken)) {
              _changeQuality(desiredIndex, notifyPreference: false);
            }
          });
        }
      }

      if (parsedSubtitleTracks.isNotEmpty) {
        unawaited(_loadSubtitles());
      }
    } catch (_) {}
  }

  List<_ResolvedVideoSource> _parseHlsQualitySources(
    String playlist,
    Uri playlistUri,
  ) {
    final variants = <_ResolvedVideoSource>[];
    final seenUrls = <String>{};
    final lines = playlist.split(RegExp(r'\r?\n'));

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

      String? variantPath;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (candidate.startsWith('#')) continue;
        variantPath = candidate;
        break;
      }
      if (variantPath == null) continue;

      final attrs = line.substring(line.indexOf(':') + 1);
      final resolution = _readHlsAttribute(attrs, 'RESOLUTION');
      final name = _readHlsAttribute(attrs, 'NAME');
      final bandwidth = int.tryParse(
        _readHlsAttribute(attrs, 'BANDWIDTH') ?? '',
      );
      final height = resolution == null
          ? null
          : int.tryParse(resolution.split('x').last.trim());
      final url = playlistUri.resolve(variantPath).toString();
      if (!seenUrls.add(url)) continue;

      final label = height != null
          ? '${height}p'
          : (name != null && name.isNotEmpty)
          ? name
          : bandwidth != null
          ? '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps'
          : 'Source ${variants.length + 1}';

      variants.add(
        _ResolvedVideoSource(
          url: url,
          label: label,
          preference: height != null ? '${height}p' : label,
          height: height,
          bandwidth: bandwidth,
        ),
      );
    }

    if (variants.isEmpty) return const [];
    variants.sort((a, b) {
      final heightCompare = (b.height ?? 0).compareTo(a.height ?? 0);
      if (heightCompare != 0) return heightCompare;
      return (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0);
    });

    return [
      _ResolvedVideoSource(
        url: widget.videoUrls.first,
        label: 'Auto (Adaptive HLS)',
        preference: 'Auto',
      ),
      ...variants,
    ];
  }

  List<SubtitleTrack> _parseHlsSubtitleTracks(
    String playlist,
    Uri playlistUri,
  ) {
    final tracks = <SubtitleTrack>[];
    final seenUrls = <String>{};

    for (final rawLine in playlist.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (!line.startsWith('#EXT-X-MEDIA')) continue;
      final attrs = line.substring(line.indexOf(':') + 1);
      final type = _readHlsAttribute(attrs, 'TYPE')?.toUpperCase();
      final uri = _readHlsAttribute(attrs, 'URI');
      if (type != 'SUBTITLES' || uri == null || uri.isEmpty) continue;

      final resolvedUrl = playlistUri.resolve(uri).toString();
      if (!seenUrls.add(resolvedUrl)) continue;

      final name = _readHlsAttribute(attrs, 'NAME');
      final language = _readHlsAttribute(attrs, 'LANGUAGE');
      tracks.add(
        SubtitleTrack(
          label: name?.isNotEmpty == true
              ? name!
              : language?.isNotEmpty == true
              ? language!
              : 'Subtitle ${tracks.length + 1}',
          language: language ?? '',
          url: resolvedUrl,
        ),
      );
    }

    return tracks;
  }

  String? _readHlsAttribute(String attrs, String key) {
    final quoted = RegExp(
      '$key="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(attrs);
    if (quoted != null) return quoted.group(1);

    final plain = RegExp(
      '$key=([^,]*)',
      caseSensitive: false,
    ).firstMatch(attrs);
    return plain?.group(1)?.trim();
  }

  Future<List<SubtitleCue>> _loadHlsSubtitleCues(
    Uri playlistUri,
    Map<String, String> headers,
    String playlistBody,
  ) async {
    final segments = _parseHlsSubtitleSegments(playlistBody, playlistUri);
    if (segments.isEmpty) return _parseVttOrSrt(playlistBody);

    final cues = <SubtitleCue>[];
    for (final segment in segments.take(160)) {
      try {
        final response = await _getSubtitleResponse(segment.uri, headers);
        if (response == null || response.statusCode != 200) continue;
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        final segmentCues = _parseVttOrSrt(body);
        if (segmentCues.isEmpty) continue;

        final shouldShift =
            segment.offset > const Duration(seconds: 30) &&
            segmentCues.last.end < segment.offset - const Duration(seconds: 5);
        cues.addAll(
          shouldShift
              ? segmentCues.map(
                  (cue) => SubtitleCue(
                    start: cue.start + segment.offset,
                    end: cue.end + segment.offset,
                    text: cue.text,
                  ),
                )
              : segmentCues,
        );
      } catch (_) {}
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  List<_HlsSubtitleSegment> _parseHlsSubtitleSegments(
    String playlist,
    Uri playlistUri,
  ) {
    final segments = <_HlsSubtitleSegment>[];
    var runningOffset = Duration.zero;
    var pendingDuration = Duration.zero;

    for (final rawLine in playlist.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        pendingDuration = _parseHlsDuration(line);
        continue;
      }

      if (line.startsWith('#')) continue;

      segments.add(
        _HlsSubtitleSegment(
          uri: playlistUri.resolve(line),
          offset: runningOffset,
        ),
      );
      runningOffset += pendingDuration;
      pendingDuration = Duration.zero;
    }

    return segments;
  }

  Duration _parseHlsDuration(String extInfLine) {
    final value = extInfLine
        .substring('#EXTINF:'.length)
        .split(',')
        .first
        .trim();
    final seconds = double.tryParse(value) ?? 0;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  List<SubtitleCue> _parseVttOrSrt(String content) {
    final cues = <SubtitleCue>[];
    if (content.isEmpty) return cues;

    if (content.contains('[Events]') && content.contains('Dialogue:')) {
      return _parseAssSubtitles(content);
    }

    final cleaned = content
        .replaceFirst('\uFEFF', '')
        .replaceAll(RegExp(r'^WEBVTT.*$', multiLine: true), '')
        .replaceAll(RegExp(r'^NOTE\b.*$', multiLine: true), '')
        .replaceAll(RegExp(r'^STYLE\b.*$', multiLine: true), '');

    final blocks = cleaned.split(RegExp(r'\r?\n\r?\n'));

    final timestampRegex = RegExp(
      r'(?:(\d{1,2}):)?(\d{2}):(\d{2})[.,](\d{1,3})\s*-->\s*(?:(\d{1,2}):)?(\d{2}):(\d{2})[.,](\d{1,3})',
    );

    for (final block in blocks) {
      final lines = block.trim().split(RegExp(r'\r?\n'));
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        final match = timestampRegex.firstMatch(line);
        if (match != null) {
          final startH = int.tryParse(match.group(1) ?? '0') ?? 0;
          final startM = int.parse(match.group(2)!);
          final startS = int.parse(match.group(3)!);
          final startMsStr = match.group(4)!.padRight(3, '0');
          final startMs = int.parse(startMsStr);

          final endH = int.tryParse(match.group(5) ?? '0') ?? 0;
          final endM = int.parse(match.group(6)!);
          final endS = int.parse(match.group(7)!);
          final endMsStr = match.group(8)!.padRight(3, '0');
          final endMs = int.parse(endMsStr);

          final startTime = Duration(
            hours: startH,
            minutes: startM,
            seconds: startS,
            milliseconds: startMs,
          );
          final endTime = Duration(
            hours: endH,
            minutes: endM,
            seconds: endS,
            milliseconds: endMs,
          );

          final textLines = lines
              .sublist(i + 1)
              .map((l) {
                return _cleanSubtitleText(l);
              })
              .where((l) => l.isNotEmpty)
              .toList();

          if (textLines.isNotEmpty) {
            cues.add(
              SubtitleCue(
                start: startTime,
                end: endTime,
                text: textLines.join('\n'),
              ),
            );
          }
          break;
        }
      }
    }

    return cues;
  }

  List<SubtitleCue> _parseAssSubtitles(String content) {
    final cues = <SubtitleCue>[];
    var format = <String>[];

    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.startsWith('Format:')) {
        format = line
            .substring('Format:'.length)
            .split(',')
            .map((field) => field.trim().toLowerCase())
            .toList();
        continue;
      }

      if (!line.startsWith('Dialogue:')) continue;

      final fieldCount = format.isEmpty ? 10 : format.length;
      final fields = _splitAssFields(
        line.substring('Dialogue:'.length).trim(),
        fieldCount,
      );
      final startIndex = format.isEmpty ? 1 : format.indexOf('start');
      final endIndex = format.isEmpty ? 2 : format.indexOf('end');
      final textIndex = format.isEmpty ? 9 : format.indexOf('text');

      if (startIndex == -1 ||
          endIndex == -1 ||
          textIndex == -1 ||
          fields.length <= textIndex) {
        continue;
      }

      final start = _parseAssTime(fields[startIndex]);
      final end = _parseAssTime(fields[endIndex]);
      final text = _cleanSubtitleText(fields[textIndex]);

      if (start != null && end != null && text.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: text));
      }
    }

    return cues;
  }

  List<String> _splitAssFields(String value, int fieldCount) {
    final fields = <String>[];
    var remaining = value;
    for (var i = 0; i < fieldCount - 1; i++) {
      final commaIndex = remaining.indexOf(',');
      if (commaIndex == -1) break;
      fields.add(remaining.substring(0, commaIndex));
      remaining = remaining.substring(commaIndex + 1);
    }
    fields.add(remaining);
    return fields;
  }

  Duration? _parseAssTime(String value) {
    final match = RegExp(
      r'(\d+):(\d{2}):(\d{2})[.](\d{1,3})',
    ).firstMatch(value.trim());
    if (match == null) return null;

    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
      milliseconds: int.parse(match.group(4)!.padRight(3, '0')),
    );
  }

  String _cleanSubtitleText(String value) {
    return value
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  Widget _buildSubtitleOverlay() {
    if (!_subtitlesEnabled) return const SizedBox.shrink();
    if (_subCues.isEmpty) return const SizedBox.shrink();

    final activeCue = _currentCue;
    if (activeCue == null || activeCue.text.isEmpty) {
      return const SizedBox.shrink();
    }

    final isFull = widget.isFullscreen;
    final baseFontSize = widget.subtitleFontSize.clamp(10.0, 28.0).toDouble();
    final textStyle = widget.subtitleTextStyle.toLowerCase();
    final shadowIntensity = widget.subtitleTextShadow
        .clamp(0.0, 1.0)
        .toDouble();
    final backgroundOpacity = widget.subtitleBackgroundOpacity
        .clamp(0.0, 1.0)
        .toDouble();
    final backgroundColor = widget.subtitleBackgroundColor == null
        ? null
        : Color(
            widget.subtitleBackgroundColor!,
          ).withValues(alpha: backgroundOpacity);
    final defaultBottom = _showControls
        ? (isFull ? 90.0 : 64.0)
        : (isFull ? 30.0 : 16.0);
    final extraBottom =
        widget.subtitleBottomPosition.clamp(0.0, 1.0).toDouble() *
        (isFull ? 180.0 : 80.0);

    return Positioned(
      left: isFull ? 48 : 20,
      right: isFull ? 48 : 20,
      bottom: defaultBottom + extraBottom,
      child: RepaintBoundary(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              activeCue.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(widget.subtitleTextColor),
                fontSize: isFull ? baseFontSize + 3 : baseFontSize,
                fontWeight: textStyle == 'bold'
                    ? FontWeight.w800
                    : FontWeight.w600,
                fontStyle: textStyle == 'italic'
                    ? FontStyle.italic
                    : FontStyle.normal,
                shadows: shadowIntensity == 0
                    ? null
                    : [
                        Shadow(
                          color: Colors.black.withValues(
                            alpha: 0.88 * shadowIntensity,
                          ),
                          blurRadius: 8 * shadowIntensity,
                          offset: Offset(0, 2 * shadowIntensity),
                        ),
                      ],
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.accentPrimary,
              size: 38,
            ),
            const SizedBox(height: 10),
            const Text(
              'This stream stopped loading.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Retry this quality or switch to another server.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPrimary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              onPressed: _retryCurrentStream,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _deinitializePlayer() {
    _playerLoadToken++;
    _hideControlsTimer?.cancel();
    _hideControlsTimer = null;
    _pendingSeekDebounce?.cancel();
    _pendingSeekDebounce = null;
    _pendingSeekPosition = null;
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
    _slowLoadTimer?.cancel();
    _slowLoadTimer = null;
    _rewindTimer?.cancel();
    _rewindTimer = null;
    _forwardTimer?.cancel();
    _forwardTimer = null;
    if (_controller != null) {
      _controller!.removeListener(_playerListener);
      try {
        _controller!.pause().catchError((_) {});
      } catch (_) {}
      try {
        _controller!.dispose().catchError((_) {});
      } catch (_) {}
      _controller = null;
    }
    _isInitialized = false;
  }

  bool _isActivePlayerLoad(int loadToken) {
    return mounted && loadToken == _playerLoadToken;
  }

  bool _isActiveController(int loadToken, VideoPlayerController controller) {
    return _isActivePlayerLoad(loadToken) && identical(_controller, controller);
  }

  void _reportPlaybackFailure() {
    if (_hasReportedPlaybackFailure) return;
    _hasReportedPlaybackFailure = true;
    final clockError = _playbackClockError;
    if (clockError != null) widget.onPlaybackError?.call(clockError);
    widget.onPlaybackFailed?.call();
  }

  Future<void> _initializePlayer({Duration? startPosition}) async {
    final loadToken = ++_playerLoadToken;
    if (widget.videoUrls.isEmpty) {
      if (_isActivePlayerLoad(loadToken)) {
        setState(() {
          _hasError = true;
        });
        _reportPlaybackFailure();
      }
      return;
    }

    if (mounted) {
      _hasReportedPlaybackFailure = false;
      _playbackClockError = null;
      setState(() {
        _hasError = false;
        _isSlowLoad = false;
        _isInitialized = false;
        _skipTimes = const EpisodeSkipTimes();
        _automaticallySkipped.clear();
      });
    }

    // Resolve variant playlists in parallel in the background so video initialization
    // starts immediately on frame 1 without blocking playback startup.
    unawaited(_ensureQualitySources(loadToken));
    if (!_isActivePlayerLoad(loadToken)) return;

    final sources = _availableQualitySources();
    if (sources.isEmpty) {
      if (_isActivePlayerLoad(loadToken)) {
        setState(() {
          _controller = null;
          _isInitialized = false;
          _hasError = true;
        });
        _reportPlaybackFailure();
      }
      return;
    }

    // Show 'Slow connection...' hint after 8 seconds of loading.
    _slowLoadTimer?.cancel();
    _slowLoadTimer = Timer(const Duration(seconds: 8), () {
      if (_isActivePlayerLoad(loadToken) && !_isInitialized && !_hasError) {
        setState(() => _isSlowLoad = true);
      }
    });

    // Hard outer timeout at 30s — if no URL succeeds, show the error UI.
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_isActivePlayerLoad(loadToken) && !_isInitialized && !_hasError) {
        setState(() {
          _hasError = true;
          _isSlowLoad = false;
        });
        _reportPlaybackFailure();
      }
    });

    final startIndex = _selectedQualityIndex >= sources.length
        ? 0
        : _selectedQualityIndex;

    for (var offset = 0; offset < sources.length; offset++) {
      if (!_isActivePlayerLoad(loadToken)) return;

      final candidateIndex = (startIndex + offset) % sources.length;
      final activeSource = sources[candidateIndex];
      final activeUrl = activeSource.url;

      final headers = Map<String, String>.from(widget.headers ?? {});
      if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
      }

      VideoPlayerController controller = Uri.parse(activeUrl).scheme == 'file'
          ? VideoPlayerController.file(
              File.fromUri(Uri.parse(activeUrl)),
              viewType: VideoViewType.textureView,
            )
          : VideoPlayerController.networkUrl(
              Uri.parse(activeUrl),
              httpHeaders: headers,
              viewType: VideoViewType.textureView,
            );
      _controller = controller;

      try {
        try {
          await controller.initialize().timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw Exception('Video load timeout'),
          );
        } catch (_) {
          if (!_isActivePlayerLoad(loadToken)) return;
          try {
            await controller.dispose();
          } catch (_) {}
          // Fall back to a native surface only if the texture cannot initialize.
          controller = Uri.parse(activeUrl).scheme == 'file'
              ? VideoPlayerController.file(
                  File.fromUri(Uri.parse(activeUrl)),
                  viewType: VideoViewType.platformView,
                )
              : VideoPlayerController.networkUrl(
                  Uri.parse(activeUrl),
                  httpHeaders: headers,
                  viewType: VideoViewType.platformView,
                );
          _controller = controller;
          await controller.initialize().timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw Exception('Video load timeout'),
          );
        }

        if (!_isActiveController(loadToken, controller)) {
          return;
        }

        _loadingTimeoutTimer?.cancel();
        _loadingTimeoutTimer = null;
        _slowLoadTimer?.cancel();
        _slowLoadTimer = null;
        setState(() {
          _selectedQualityIndex = candidateIndex;
          _isInitialized = true;
          _isSlowLoad = false;
          _hasError = false;
          _duration = controller.value.duration;
        });

        unawaited(_loadSkipTimes(loadToken, controller.value.duration));
        final seekPos = startPosition ?? widget.initialPosition;
        if (seekPos > Duration.zero && seekPos < controller.value.duration) {
          await controller.seekTo(seekPos);
          if (!_isActiveController(loadToken, controller)) return;
        }

        await controller.setPlaybackSpeed(_playbackSpeed);
        if (!_isActiveController(loadToken, controller)) return;
        await controller.setVolume(1.0);
        if (!_isActiveController(loadToken, controller)) return;
        controller.addListener(_playerListener);
        await controller.play();
        if (!_isActiveController(loadToken, controller)) return;
        _startHideControlsTimer();
        return;
      } catch (e) {
        debugPrint('Failed to initialize stream candidate $activeUrl: $e');
        controller.removeListener(_playerListener);
        await controller.dispose();
        if (_isActiveController(loadToken, controller)) {
          _controller = null;
        }
        if (!_isActivePlayerLoad(loadToken)) return;
      }
    }

    if (!_isActivePlayerLoad(loadToken)) return;
    setState(() {
      _controller = null;
      _isInitialized = false;
      _hasError = true;
      _isSlowLoad = false;
    });
    _reportPlaybackFailure();
  }

  bool _lastPlaying = false;

  void _playerListener() {
    if (!mounted || _controller == null) return;
    final value = _controller!.value;
    if (value.hasError) {
      if (!_hasError) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
          _isBuffering = false;
          _isSlowLoad = false;
        });
        _reportPlaybackFailure();
      }
      return;
    }

    final playingChanged = _lastPlaying != value.isPlaying;
    _lastPlaying = value.isPlaying;
    final isBufferingNow = value.isBuffering;
    final pos = value.position;
    final dur = value.duration;

    // Guard with _hasCalledOnEnded to prevent multiple firings at video end
    if (!_hasCalledOnEnded &&
        dur > Duration.zero &&
        pos >= dur &&
        !value.isPlaying) {
      _hasCalledOnEnded = true;
      widget.onVideoEnded?.call();
      return;
    }

    // Subtitle timing is independent of playback and watch progress.
    final subtitlePos = subtitlePosition(
      pos,
      Duration(milliseconds: _subtitleDelayMilliseconds),
    );
    SubtitleCue? activeCue;
    if (_subtitlesEnabled && _subCues.isNotEmpty) {
      if (_currentCue != null &&
          subtitlePos >= _currentCue!.start &&
          subtitlePos <= _currentCue!.end) {
        activeCue = _currentCue;
      } else {
        for (final cue in _subCues) {
          if (subtitlePos >= cue.start && subtitlePos <= cue.end) {
            activeCue = cue;
            break;
          }
        }
      }
    }
    final videoSize = value.size;
    final sizeChanged =
        videoSize != _lastVideoSize &&
        videoSize.width > 0 &&
        videoSize.height > 0;
    if (sizeChanged) {
      _lastVideoSize = videoSize;
    }

    final cueChanged = activeCue != _currentCue;
    final bufferingChanged = isBufferingNow != _isBuffering;
    final durationChanged = dur != _duration;
    final skipWindowChanged =
        _activeSkipType(pos) != _activeSkipType(_currentPosition);

    if (skipWindowChanged &&
        (_skipIntroFocusNode.hasFocus || _skipOutroFocusNode.hasFocus)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _openPlayerPopups > 0) return;
        (_showControls ? _playPauseFocusNode : _playerFocusNode).requestFocus();
      });
    }

    final now = DateTime.now();
    final timeSinceLastUi = now.difference(_lastPositionUiUpdate);
    final positionSecondsChanged = pos.inSeconds != _currentPosition.inSeconds;

    // Controls need position updates at most once every ~250ms on second boundaries.
    // When controls are hidden, we do NOT trigger setState for time/slider progress!
    final shouldUpdateUi =
        playingChanged ||
        bufferingChanged ||
        durationChanged ||
        cueChanged ||
        sizeChanged ||
        skipWindowChanged ||
        (_showControls &&
            positionSecondsChanged &&
            timeSinceLastUi.inMilliseconds >= 250);

    if (_pendingSeekPosition != null) {
      _duration = dur;
      _isBuffering = isBufferingNow;
      _currentCue = activeCue;
      return;
    }

    final previousPosition = _currentPosition;
    _currentPosition = pos;
    _duration = dur;
    _isBuffering = isBufferingNow;
    _currentCue = activeCue;

    if (widget.autoSkipIntroOutro &&
        value.isPlaying &&
        _pendingSeekPosition == null &&
        !_skipSeekInFlight &&
        pos > previousPosition &&
        pos - previousPosition < const Duration(seconds: 2)) {
      if (_skipTimes.intro != null &&
          _skipTimes.intro!.isValidFor(_duration) &&
          _skipTimes.intro!.contains(pos) &&
          (previousPosition < _skipTimes.intro!.start ||
              (_skipTimes.intro!.start == Duration.zero &&
                  previousPosition == Duration.zero)) &&
          _automaticallySkipped.add(1)) {
        _skipIntro();
      } else if (_skipTimes.outro != null &&
          _skipTimes.outro!.isValidFor(_duration) &&
          _skipTimes.outro!.contains(pos) &&
          previousPosition < _skipTimes.outro!.start &&
          _automaticallySkipped.add(2)) {
        _skipOutro();
      }
    }

    if (shouldUpdateUi) {
      _lastPositionUiUpdate = now;
      setState(() {});
    }

    widget.onPositionChanged?.call(pos);
  }

  void _togglePlay() {
    if (_controller == null || !_isInitialized) return;
    _interactWithControls();
    _loadingTimeoutTimer?.cancel();
    _slowLoadTimer?.cancel();
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _hideControlsTimer?.cancel();
      } else {
        _controller!.play();
        _startHideControlsTimer();
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_openPlayerPopups > 0) return;
    if (widget.alwaysShowControls) {
      if (mounted && !_showControls) {
        setState(() => _showControls = true);
      }
      return;
    }
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false) && !_isLocked) {
        _hideControlsForPlayback();
      }
    });
  }

  void _hideControlsForPlayback() {
    if (!mounted || !_showControls) return;
    setState(() => _showControls = false);
    _hideControlsTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playerFocusNode.requestFocus();
      }
    });
  }

  void _interactWithControls() {
    if (_isLocked) return;
    if (mounted && !_showControls) {
      setState(() => _showControls = true);
    }
    if (!widget.alwaysShowControls) {
      _startHideControlsTimer();
    }
  }

  void _toggleControlsVisibility() {
    if (widget.alwaysShowControls && !_isLocked) {
      if (!_showControls) setState(() => _showControls = true);
      return;
    }
    if (_isLocked) {
      setState(() => _showControls = !_showControls);
      _hideControlsTimer?.cancel();
      if (_showControls) {
        _hideControlsTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _isLocked) setState(() => _showControls = false);
        });
      }
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showControls) {
          _playPauseFocusNode.requestFocus();
        }
      });
    } else {
      _hideControlsTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _playerFocusNode.requestFocus();
        }
      });
    }
  }

  void _rewind10() {
    if (_controller == null || !_isInitialized) return;
    final basePos = _pendingSeekPosition ?? _currentPosition;
    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0;
    final targetMs = (basePos.inMilliseconds - 10000).clamp(0, maxMs);
    final newPos = Duration(milliseconds: targetMs);
    _pendingSeekPosition = newPos;
    _currentPosition = newPos;
    setState(() {});
    _triggerRewindFeedback();
    _interactWithControls();

    _pendingSeekDebounce?.cancel();
    _pendingSeekDebounce = Timer(const Duration(milliseconds: 40), () {
      if (_controller != null &&
          _isInitialized &&
          _pendingSeekPosition != null) {
        _controller?.seekTo(_pendingSeekPosition!);
        _pendingSeekPosition = null;
      }
    });
  }

  void _forward10() {
    if (_controller == null || !_isInitialized) return;
    final basePos = _pendingSeekPosition ?? _currentPosition;
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : (basePos.inMilliseconds + 10000);
    final targetMs = (basePos.inMilliseconds + 10000).clamp(0, maxMs);
    final newPos = Duration(milliseconds: targetMs);
    _pendingSeekPosition = newPos;
    _currentPosition = newPos;
    setState(() {});
    _triggerForwardFeedback();
    _interactWithControls();

    _pendingSeekDebounce?.cancel();
    _pendingSeekDebounce = Timer(const Duration(milliseconds: 40), () {
      if (_controller != null &&
          _isInitialized &&
          _pendingSeekPosition != null) {
        _controller?.seekTo(_pendingSeekPosition!);
        _pendingSeekPosition = null;
      }
    });
  }

  void _triggerRewindFeedback() {
    setState(() => _showRewindIndicator = true);
    _rewindTimer?.cancel();
    _rewindTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) setState(() => _showRewindIndicator = false);
    });
  }

  void _triggerForwardFeedback() {
    setState(() => _showForwardIndicator = true);
    _forwardTimer?.cancel();
    _forwardTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) setState(() => _showForwardIndicator = false);
    });
  }

  void _changeQuality(int index, {bool notifyPreference = true}) {
    final sources = _availableQualitySources();
    if (index == _selectedQualityIndex || index >= sources.length) {
      return;
    }
    if (notifyPreference) {
      widget.onQualityPreferenceChanged?.call(
        _qualityPreferenceForIndex(index),
      );
    }
    setState(() {
      _selectedQualityIndex = index;
      _isInitialized = false;
      _hasError = false;
      _isSlowLoad = false;
    });
    final currentPos = _currentPosition;
    _deinitializePlayer();
    _initializePlayer(startPosition: currentPos);
  }

  void _retryCurrentStream() {
    final retryPosition = _currentPosition;
    _hasReportedPlaybackFailure = false;
    _qualitySourceSignature = null;
    _deinitializePlayer();
    _initializePlayer(startPosition: retryPosition);
  }

  void _changeSpeed(double speed) {
    final nextSpeed = _normalizedPlaybackSpeed(speed);
    setState(() => _playbackSpeed = nextSpeed);
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.setPlaybackSpeed(nextSpeed));
    }
    widget.onPlaybackSpeedChanged?.call(nextSpeed);
  }

  void _requestPlayerFocus(FocusNode node) {
    if (!mounted) return;
    if (!_showControls) {
      _showControls = true;
      if (mounted) setState(() {});
    }
    node.requestFocus();
  }

  Map<LogicalKeyboardKey, VoidCallback> _playerDirections({
    FocusNode? left,
    FocusNode? right,
    FocusNode? up,
    FocusNode? down,
  }) {
    final handlers = <LogicalKeyboardKey, VoidCallback>{};
    if (left != null) {
      handlers[LogicalKeyboardKey.arrowLeft] = () => _requestPlayerFocus(left);
    }
    if (right != null) {
      handlers[LogicalKeyboardKey.arrowRight] = () =>
          _requestPlayerFocus(right);
    }
    if (up != null) {
      handlers[LogicalKeyboardKey.arrowUp] = () => _requestPlayerFocus(up);
    }
    if (down != null) {
      handlers[LogicalKeyboardKey.arrowDown] = () => _requestPlayerFocus(down);
    }
    return handlers;
  }

  KeyEventResult _handleRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final controlsHavePrimaryFocus = !node.hasPrimaryFocus;

    // 1. Remote Back key:
    // If controls are currently visible, dismiss the controls overlay and return focus to the player.
    // If controls are already hidden, ignore so Back key bubbles up to WatchScreen to exit player.
    final isBackKey = DesktopNavigationController.isDesktopBackKey(event);
    if (isBackKey) {
      if (_showControls) {
        setState(() => _showControls = false);
        _hideControlsTimer?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playerFocusNode.requestFocus();
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Desktop Hotkeys (F for fullscreen, M for mute):
    if (key == LogicalKeyboardKey.keyF) {
      widget.onToggleFullscreen?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }

    // 2. Media transport keys:
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      final isPlaying = _controller?.value.isPlaying ?? false;
      if (key == LogicalKeyboardKey.mediaPlay && !isPlaying) {
        _togglePlay();
      } else if (key == LogicalKeyboardKey.mediaPause && isPlaying) {
        _togglePlay();
      } else if (key == LogicalKeyboardKey.mediaPlayPause) {
        _togglePlay();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _togglePlay();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaRewind) {
      _rewind10();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaFastForward) {
      _forward10();
      return KeyEventResult.handled;
    }

    // 3. Center D-pad (Select / Enter / Space / GameButtonA):
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;

      // If controls are hidden: reveal controls AND immediately focus the Play/Pause button!
      if (!_showControls) {
        _interactWithControls();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showControls) {
            _playPauseFocusNode.requestFocus();
          }
        });
        return KeyEventResult.handled;
      }

      // If controls are visible, but focus is still on player background:
      if (!controlsHavePrimaryFocus) {
        _playPauseFocusNode.requestFocus();
        _togglePlay();
        return KeyEventResult.handled;
      }

      // If a control button already has focus, let the focused button handle Enter/Select!
      return KeyEventResult.ignored;
    }

    // 4. Left / Right Arrow keys (Seeking):
    // When controls are hidden or when player has primary focus: seek by 10 seconds!
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.gameButtonLeft1) {
      if (!_showControls || !controlsHavePrimaryFocus) {
        _rewind10();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.gameButtonRight1) {
      if (!_showControls || !controlsHavePrimaryFocus) {
        _forward10();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 5. Up / Down Arrow keys (Volume control on desktop, or focus active skip button):
    if (key == LogicalKeyboardKey.arrowUp) {
      if (!controlsHavePrimaryFocus) {
        final skipType = _activeSkipType(_currentPosition);
        if (skipType == 1) {
          _skipIntroFocusNode.requestFocus();
          return KeyEventResult.handled;
        } else if (skipType == 2) {
          _skipOutroFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        _adjustVolume(0.05);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (!controlsHavePrimaryFocus) {
        _adjustVolume(-0.05);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (duration.inHours > 0) {
      return '${duration.inHours}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  // ─── Modal Bottom Sheets ──────────────────────────────────────────────────

  int _openPlayerPopups = 0;

  Future<void> _withPlayerPopup(Future<void> Function() open) async {
    final opener = FocusManager.instance.primaryFocus;
    _openPlayerPopups++;
    _hideControlsTimer?.cancel();
    try {
      await open();
    } finally {
      _openPlayerPopups--;
      if (mounted && _openPlayerPopups == 0) {
        _interactWithControls();
        if (opener?.context != null && opener!.canRequestFocus) {
          opener.requestFocus();
        } else {
          _playPauseFocusNode.requestFocus();
        }
      }
    }
  }

  void _showPlayerBottomSheet({
    required BuildContext context,
    required WidgetBuilder builder,
    bool useRootNavigator = true,
    bool isScrollControlled = true,
    Color? backgroundColor,
  }) {
    unawaited(
      _withPlayerPopup(() async {
        await showDialog<void>(
          context: context,
          useRootNavigator: useRootNavigator,
          barrierColor: Colors.black.withValues(alpha: 0.65),
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: _popupFocus(ctx, builder(ctx)),
          ),
        );
      }),
    );
  }

  Widget _popupFocus(BuildContext context, Widget child) {
    return PlayerPopupFocus(
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (DesktopNavigationController.isDesktopBackKey(event)) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          final direction = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowUp => TraversalDirection.up,
            LogicalKeyboardKey.arrowDown => TraversalDirection.down,
            LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
            LogicalKeyboardKey.arrowRight => TraversalDirection.right,
            _ => null,
          };
          if (direction == null) return KeyEventResult.ignored;
          FocusManager.instance.primaryFocus?.focusInDirection(direction);
          return KeyEventResult.handled;
        },
        child: child,
      ),
    );
  }

  Widget _buildSheetFocusItem({
    required String label,
    required VoidCallback onTap,
    required Widget child,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DesktopFocusWrapper.builder(
        debugLabel: label,
        autofocus: autofocus,
        onTap: onTap,
        focusedScale: 1,
        builder: (context, focused, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: focused
                ? AppColors.activeState
                : hovered
                ? AppColors.hoverState
                : AppColors.surface,
            borderRadius: AppRadii.control,
            border: Border.all(
              color: focused
                  ? AppColors.brandRed
                  : hovered
                  ? AppColors.borderStrong
                  : AppColors.border,
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFloatingSheetSurface({
    required BuildContext context,
    required String title,
    String? subtitle,
    required IconData icon,
    required Widget child,
    double maxWidth = 480,
    Key? closeKey,
    String closeDebugLabel = 'Close player menu',
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: Material(
          color: AppColors.secondaryBg,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.dialog,
            side: BorderSide(color: AppColors.borderStrong, width: 1.0),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
                child: Row(
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
                      child: Icon(icon, color: AppColors.brandRed, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (subtitle != null && subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    DesktopFocusWrapper(
                      key: closeKey,
                      debugLabel: closeDebugLabel,
                      borderRadius: AppRadii.control,
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadii.control,
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                color: AppColors.borderSubtle,
                height: 1.0,
                thickness: 1.0,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext sheetContext) {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    _showPlayerBottomSheet(
      context: sheetContext,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          return _buildFloatingSheetSurface(
            context: innerCtx,
            title: 'Playback Speed',
            icon: Icons.speed_rounded,
            closeDebugLabel: 'Close playback speed',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: speeds.map((s) {
                final isSelected = _playbackSpeed == s;
                return _buildSheetFocusItem(
                  label: 'Playback speed ${s}x',
                  autofocus: s == _playbackSpeed,
                  onTap: () {
                    _changeSpeed(s);
                    setSheetState(() {});
                    Navigator.of(ctx).pop();
                  },
                  child: ListTile(
                    dense: true,
                    title: Text(
                      s == 1.0 ? 'Normal (1.0×)' : '$s×',
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13.5,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.brandRed,
                            size: 18,
                          )
                        : null,
                    onTap: null,
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  void _showQualitySheet(BuildContext context) {
    final qualityOptions = _qualityOptions();
    final hasMultipleSources = _availableQualitySources().length > 1;

    _showPlayerBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          return _buildFloatingSheetSurface(
            context: innerCtx,
            title: 'Stream Quality',
            icon: Icons.hd_rounded,
            closeDebugLabel: 'Close stream quality',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(qualityOptions.length, (i) {
                final isSelected = _selectedQualityIndex == i;
                return _buildSheetFocusItem(
                  label: 'Stream quality ${qualityOptions[i]}',
                  autofocus: isSelected,
                  onTap: () {
                    if (hasMultipleSources) {
                      _changeQuality(i);
                    } else {
                      widget.onQualityPreferenceChanged?.call('Auto');
                      setState(() => _selectedQualityIndex = 0);
                    }
                    setSheetState(() {});
                    Navigator.pop(innerCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          hasMultipleSources
                              ? 'Quality set to: ${qualityOptions[i]}'
                              : 'Quality is adaptive for this stream',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: ListTile(
                    dense: true,
                    title: Text(
                      qualityOptions[i],
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      !hasMultipleSources
                          ? 'This stream controls resolution adaptively'
                          : 'Prefer ${qualityOptions[i]} resolution target',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.brandRed,
                            size: 18,
                          )
                        : null,
                    onTap: null,
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  static const List<Map<String, String>> _aspectRatioOptions = [
    {
      'id': 'fit_16_9',
      'label': 'Fit 16:9',
      'desc': 'Standard anime 16:9 uncropped fit (Uncropped desktop playback)',
    },
    {
      'id': 'original',
      'label': 'Original / Auto',
      'desc': 'Contain within stream native aspect ratio',
    },
    {
      'id': 'stretch',
      'label': 'Stretch (Fill Screen)',
      'desc': 'Stretch video to fill the full display bounds',
    },
    {
      'id': 'zoom',
      'label': 'Zoom (Crop to Fill)',
      'desc': 'Scale up to fill display without black bars',
    },
  ];

  String _videoDisplayModeLabel(String mode) {
    for (final opt in _aspectRatioOptions) {
      if (opt['id'] == mode) return opt['label']!;
    }
    return 'Fit 16:9';
  }

  void _showAspectRatioSheet(BuildContext context) {
    _showPlayerBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          return _buildFloatingSheetSurface(
            context: innerCtx,
            title: 'Aspect Ratio / Display Mode',
            icon: Icons.aspect_ratio_rounded,
            closeDebugLabel: 'Close aspect ratio',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _aspectRatioOptions.map((opt) {
                final id = opt['id']!;
                final label = opt['label']!;
                final desc = opt['desc']!;
                final isSelected = _videoDisplayMode == id;
                return _buildSheetFocusItem(
                  label: 'Aspect ratio $label',
                  autofocus: isSelected,
                  onTap: () {
                    setState(() => _videoDisplayMode = id);
                    widget.onVideoDisplayModeChanged?.call(id);
                    setSheetState(() {});
                    Navigator.pop(innerCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Aspect ratio set to: $label'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: ListTile(
                    dense: true,
                    title: Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      desc,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.brandRed,
                            size: 18,
                          )
                        : null,
                    onTap: null,
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  void _selectSubtitleLanguageChoice(
    _SubtitleLanguageChoice choice,
    List<SubtitleTrack> subtitleTracks,
  ) {
    final index = _subtitleTrackIndexForLanguage(subtitleTracks, choice);
    setState(() {
      _subtitlesEnabled = true;
      _subtitleLanguagePreference = choice.preference;
      _selectedSubtitleTrackIndex = index;
      _subCues.clear();
    });
    widget.onSubtitlePreferenceChanged?.call(choice.preference);
    unawaited(_loadSubtitles());
  }

  void _showSubtitlesSheet(BuildContext context) {
    _showPlayerBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          final isEnabled = _subtitlesEnabled;
          final subtitleTracks = _availableSubtitleTracks();
          return _buildFloatingSheetSurface(
            context: innerCtx,
            title: 'Subtitles / Captions',
            icon: Icons.subtitles_rounded,
            closeKey: const ValueKey('close-subtitles'),
            closeDebugLabel: 'Close subtitles',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SubtitleDelayControl(
                  initialMilliseconds: _subtitleDelayMilliseconds,
                  onChanged: (value) {
                    setState(() => _subtitleDelayMilliseconds = value);
                    _playerListener();
                  },
                ),
                // Quick Master Switch: Subtitles ON / OFF
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadii.control,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isEnabled
                                ? Icons.subtitles_rounded
                                : Icons.subtitles_off_rounded,
                            color: isEnabled
                                ? AppColors.brandRed
                                : AppColors.textMuted,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isEnabled
                                ? 'Subtitles Enabled (ON)'
                                : 'Subtitles Disabled (OFF)',
                            style: TextStyle(
                              color: isEnabled
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: isEnabled,
                        activeTrackColor: AppColors.brandRed,
                        onChanged: (val) {
                          setState(() {
                            _subtitlesEnabled = val;
                            if (val) {
                              if (_subtitlePreferenceDisablesCaptions()) {
                                _subtitleLanguagePreference = 'English';
                              }
                              _selectedSubtitleTrackIndex =
                                  _subtitleTrackIndexForPreference();
                              widget.onSubtitlePreferenceChanged?.call(
                                _selectedSubtitlePreferenceLabel(),
                              );
                              unawaited(_loadSubtitles());
                            } else {
                              _subCues.clear();
                              widget.onSubtitlePreferenceChanged?.call('Off');
                            }
                          });
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
                  child: Text(
                    'Subtitle Language',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                ..._preferredSubtitleLanguages.map((choice) {
                  final idx = _subtitleTrackIndexForLanguage(
                    subtitleTracks,
                    choice,
                  );
                  final track = idx == -1 ? null : subtitleTracks[idx];
                  final preferenceChoice = _subtitleLanguageChoiceForPreference(
                    _subtitleLanguagePreference,
                  );
                  final isSelected =
                      isEnabled &&
                      preferenceChoice?.preference == choice.preference;
                  return _buildSheetFocusItem(
                    label: 'Subtitle ${choice.label}',
                    autofocus: isSelected,
                    onTap: () {
                      _selectSubtitleLanguageChoice(choice, subtitleTracks);
                      setSheetState(() {});
                      Navigator.pop(innerCtx);
                      final availableText = track == null
                          ? 'No ${choice.label} subtitles on this stream'
                          : 'Selected ${choice.label} Subtitles';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(availableText),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.subtitles_rounded,
                        color: isSelected
                            ? AppColors.brandRed
                            : AppColors.textMuted,
                        size: 20,
                      ),
                      title: Text(
                        choice.label,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        track == null
                            ? 'Not available for this stream'
                            : choice.label,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.brandRed,
                              size: 18,
                            )
                          : null,
                      onTap: null,
                    ),
                  );
                }),

                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettingsSheet(BuildContext parentContext) {
    _showPlayerBottomSheet(
      context: parentContext,
      useRootNavigator: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final qualityOptions = _qualityOptions();
            final qualityLabel =
                qualityOptions[_selectedQualityIndex.clamp(
                  0,
                  qualityOptions.length - 1,
                )];

            return _buildFloatingSheetSurface(
              context: dialogContext,
              title: 'Player Settings',
              subtitle: widget.animeTitle.isNotEmpty
                  ? '${widget.animeTitle} · ${widget.episodeTitle}'
                  : null,
              icon: Icons.tune_rounded,
              maxWidth: 520,
              closeDebugLabel: 'Close Settings',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Option 1: Stream Quality
                  _buildSheetFocusItem(
                    label: 'Stream Quality Setting',
                    autofocus: true,
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      Future.delayed(const Duration(milliseconds: 120), () {
                        if (mounted) _showQualitySheet(context);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.hd_rounded,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Stream Quality',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brandRed.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.brandRed.withValues(
                                  alpha: 0.3,
                                ),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              qualityLabel,
                              style: const TextStyle(
                                color: AppColors.brandRed,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Option 2: Aspect Ratio / Display Mode
                  _buildSheetFocusItem(
                    label: 'Aspect Ratio Setting',
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      Future.delayed(const Duration(milliseconds: 120), () {
                        if (mounted) _showAspectRatioSheet(context);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.aspect_ratio_rounded,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Aspect Ratio / Display',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brandRed.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.brandRed.withValues(
                                  alpha: 0.3,
                                ),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              _videoDisplayModeLabel(_videoDisplayMode),
                              style: const TextStyle(
                                color: AppColors.brandRed,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Option 3: Playback Speed
                  _buildSheetFocusItem(
                    label: 'Playback Speed Setting',
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      Future.delayed(const Duration(milliseconds: 120), () {
                        if (mounted) _showSpeedSheet(context);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.speed_rounded,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Playback Speed',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.borderSubtle,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              _playbackSpeed == 1.0
                                  ? 'Normal (1.0x)'
                                  : '${_playbackSpeed}x',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Option 4: Subtitles & Captions
                  _buildSheetFocusItem(
                    label: 'Subtitle Setting',
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      Future.delayed(const Duration(milliseconds: 120), () {
                        if (mounted) _showSubtitlesSheet(context);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.subtitles_rounded,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Subtitles & Captions',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _subtitlesEnabled
                                  ? AppColors.brandRed.withValues(alpha: 0.15)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _subtitlesEnabled
                                    ? AppColors.brandRed.withValues(alpha: 0.3)
                                    : AppColors.borderSubtle,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              _subtitleStatusLabel(),
                              style: TextStyle(
                                color: _subtitlesEnabled
                                    ? AppColors.brandRed
                                    : AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Option 5: Audio Track (SUB / DUB) if available
                  if (widget.onToggleLanguage != null)
                    _buildSheetFocusItem(
                      label: 'Audio Track Setting',
                      onTap: () {
                        widget.onToggleLanguage?.call();
                        setDialogState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.audiotrack_rounded,
                              color: AppColors.textPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Audio Track',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brandRed.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.brandRed.withValues(
                                    alpha: 0.3,
                                  ),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                widget.languageLabel,
                                style: const TextStyle(
                                  color: AppColors.brandRed,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Option 6: Server Picker if available
                  if (widget.onShowServers != null)
                    _buildSheetFocusItem(
                      label: 'Server Setting',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        widget.onShowServers?.call();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.dns_rounded,
                              color: AppColors.textPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Streaming Server',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (widget.serverLabel != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.borderSubtle,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  widget.serverLabel!,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textMuted,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Header & Control UI Components ─────────────────────────────────────

  Widget _buildTopBar() {
    // In windowed desktop mode, the outer desktop shell already displays
    // a dedicated top navigation bar. Hiding the internal top bar eliminates
    // duplicate back buttons, duplicate titles, and duplicate fullscreen icons.
    if (!widget.isFullscreen && !widget.showTopBarInWindowed) {
      return const SizedBox.shrink();
    }

    final isFull = widget.isFullscreen;
    final titleText = '${widget.animeTitle} · ${widget.episodeTitle}';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isFull ? 24 : 14,
            vertical: isFull ? 16 : 8,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.85),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              _buildRemoteIconControl(
                focusNode: _topBackFocusNode,
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                size: isFull ? 24 : 22,
                onTap: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (widget.onToggleFullscreen != null &&
                      widget.isFullscreen) {
                    widget.onToggleFullscreen!();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                directionalKeyHandlers: _playerDirections(
                  down: _playPauseFocusNode,
                ),
              ),
              SizedBox(width: isFull ? 16 : 10),
              Expanded(
                child: Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isFull ? 18 : 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.onToggleFullscreen != null) ...[
                const SizedBox(width: 8),
                _buildRemoteIconControl(
                  icon: isFull
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  label: isFull ? 'Exit Fullscreen (F)' : 'Fullscreen (F)',
                  size: isFull ? 24 : 20,
                  onTap: widget.onToggleFullscreen,
                  focusNode: _fullscreenFocusNode,
                  directionalKeyHandlers: _playerDirections(
                    left: _topBackFocusNode,
                    down: _playPauseFocusNode,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Consistent keyboard focus feedback for desktop player controls.
  Widget _buildRemoteIconControl({
    required IconData icon,
    required String label,
    required double size,
    required VoidCallback? onTap,
    FocusNode? focusNode,
    bool enabled = true,
    double buttonSize = 36,
    Map<LogicalKeyboardKey, VoidCallback> directionalKeyHandlers = const {},
  }) {
    return Tooltip(
      message: label,
      child: DesktopFocusWrapper(
        focusNode: focusNode,
        canRequestFocus: enabled,
        onTap: enabled ? onTap : null,
        directionalKeyHandlers: directionalKeyHandlers,
        borderRadius: AppRadii.control,
        padding: const EdgeInsets.all(4),
        focusedScale: 1.0,
        child: Semantics(
          label: label,
          button: true,
          enabled: enabled,
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Center(
              child: Icon(
                icon,
                color: enabled ? Colors.white : Colors.white38,
                size: size,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final isPlaying = _controller?.value.isPlaying ?? false;
    final maxMs = _duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final currentMs = _currentPosition.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs,
    );
    final isFull = widget.isFullscreen;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            isFull ? 24 : 10,
            0,
            isFull ? 24 : 10,
            isFull ? 16 : 6,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, bounds) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: bounds.maxWidth.clamp(720.0, double.infinity),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isFull ? 16 : 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: isFull ? 5 : 3,
                              activeTrackColor: AppColors.accentPrimary,
                              inactiveTrackColor: Colors.white.withValues(
                                alpha: 0.32,
                              ),
                              thumbColor: Colors.white,
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius: isFull ? 8 : 5,
                              ),
                              overlayShape: RoundSliderOverlayShape(
                                overlayRadius: isFull ? 16 : 10,
                              ),
                              overlayColor: AppColors.accentPrimary.withValues(
                                alpha: 0.22,
                              ),
                            ),
                            child: Slider(
                              value: currentMs,
                              max: maxMs,
                              onChanged: (value) {
                                _controller?.seekTo(
                                  Duration(milliseconds: value.toInt()),
                                );
                                _interactWithControls();
                              },
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: isFull ? 16 : 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: isFull ? 8 : 4),

                    // Desktop Media Transport and Action Controls
                    SizedBox(
                      height: isFull ? 54 : 46,
                      child: Row(
                        children: [
                          // Transport controls: Prev, Rewind, Play/Pause, Forward, Next
                          if (widget.onPlayPrev != null)
                            IconButton(
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: Colors.white,
                              ),
                              tooltip: 'Previous episode',
                              onPressed: widget.onPlayPrev,
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.replay_10_rounded,
                              color: Colors.white,
                            ),
                            tooltip: 'Rewind 10s (Left Arrow)',
                            onPressed: _rewind10,
                          ),
                          Focus(
                            focusNode: _playPauseFocusNode,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                final skipType = _activeSkipType(
                                  _currentPosition,
                                );
                                if (skipType == 1) {
                                  _skipIntroFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                } else if (skipType == 2) {
                                  _skipOutroFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.select ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.space) {
                                _togglePlay();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: IconButton(
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                              tooltip: isPlaying
                                  ? 'Pause (Space)'
                                  : 'Play (Space)',
                              onPressed: _togglePlay,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.forward_10_rounded,
                              color: Colors.white,
                            ),
                            tooltip: 'Forward 10s (Right Arrow)',
                            onPressed: _forward10,
                          ),
                          if (widget.onPlayNext != null)
                            IconButton(
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: Colors.white,
                              ),
                              tooltip: 'Next episode',
                              onPressed: widget.onPlayNext,
                            ),

                          const SizedBox(width: 8),

                          // Volume Mute / Slider Control
                          IconButton(
                            icon: Icon(
                              _isMuted || _volume == 0
                                  ? Icons.volume_off_rounded
                                  : (_volume < 0.5
                                        ? Icons.volume_down_rounded
                                        : Icons.volume_up_rounded),
                              color: Colors.white,
                              size: 20,
                            ),
                            tooltip: _isMuted ? 'Unmute (M)' : 'Mute (M)',
                            onPressed: _toggleMute,
                          ),
                          SizedBox(
                            width: 80,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 10,
                                ),
                              ),
                              child: Slider(
                                value: _isMuted ? 0.0 : _volume,
                                max: 1.0,
                                onChanged: _setVolume,
                              ),
                            ),
                          ),

                          const Spacer(),

                          // Audio language (SUB / DUB) - only in fullscreen, outer desktop shell displays it in windowed
                          if (widget.onToggleLanguage != null &&
                              widget.isFullscreen)
                            _buildRemoteIconControl(
                              focusNode: _languageFocusNode,
                              icon: widget.languageLabel.toUpperCase() == 'DUB'
                                  ? Icons.mic_rounded
                                  : Icons.subtitles_rounded,
                              label:
                                  'Audio: ${widget.languageLabel.toUpperCase()}',
                              size: 20,
                              onTap: widget.onToggleLanguage,
                            ),

                          // Server Picker - only in fullscreen, outer quick action bar displays it in windowed
                          if (widget.onShowServers != null &&
                              widget.isFullscreen)
                            _buildRemoteIconControl(
                              focusNode: _serverFocusNode,
                              icon: Icons.dns_rounded,
                              label: widget.serverLabel == null
                                  ? 'Servers'
                                  : 'Server: ${widget.serverLabel}',
                              size: 20,
                              onTap: widget.onShowServers,
                            ),

                          // Episodes Picker - only in fullscreen, outer playlist sidebar displays it in windowed
                          if (widget.onShowEpisodes != null &&
                              widget.isFullscreen)
                            _buildRemoteIconControl(
                              focusNode: _episodesFocusNode,
                              icon: Icons.video_library_rounded,
                              label: 'Episodes',
                              size: 20,
                              onTap: widget.onShowEpisodes,
                            ),

                          // Playback speed
                          _buildRemoteIconControl(
                            focusNode: _speedFocusNode,
                            icon: Icons.speed_rounded,
                            label: 'Playback speed (${_playbackSpeed}x)',
                            size: 20,
                            onTap: () => _showSpeedSheet(context),
                          ),

                          // Subtitles & Audio
                          _buildRemoteIconControl(
                            focusNode: _subtitleFocusNode,
                            icon: Icons.subtitles_rounded,
                            label:
                                'Player subtitles (${_subtitleStatusLabel()})',
                            size: 20,
                            onTap: () => _showSubtitlesSheet(context),
                          ),

                          if (widget.onToggleFullscreen != null &&
                              !widget.isFullscreen &&
                              !widget.showTopBarInWindowed)
                            _buildRemoteIconControl(
                              focusNode: _fullscreenFocusNode,
                              icon: Icons.fullscreen_rounded,
                              label: 'Fullscreen (F)',
                              size: 22,
                              onTap: widget.onToggleFullscreen,
                            ),

                          // Settings & Quality
                          _buildRemoteIconControl(
                            focusNode: _settingsFocusNode,
                            icon: Icons.settings_rounded,
                            label: 'Player settings',
                            size: 20,
                            onTap: () => _showSettingsSheet(context),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerWidget = Focus(
      focusNode: _playerFocusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleRemoteKey,
      onFocusChange: (hasFocus) {
        if (_playerHasFocus != hasFocus && mounted) {
          setState(() => _playerHasFocus = hasFocus);
        }
        if (hasFocus) _interactWithControls();
      },
      child: MouseRegion(
        cursor: (_showControls || !(_controller?.value.isPlaying ?? false))
            ? SystemMouseCursors.basic
            : SystemMouseCursors.none,
        onHover: (_) => _interactWithControls(),
        child: GestureDetector(
          onTap: _toggleControlsVisibility,
          onDoubleTapDown: (details) {
            final box = context.findRenderObject() as RenderBox?;
            final width = box?.size.width ?? MediaQuery.of(context).size.width;
            final dx = details.localPosition.dx;
            if (dx < width * 0.35) {
              _rewind10();
            } else if (dx > width * 0.65) {
              _forward10();
            } else {
              _togglePlay();
            }
          },
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Video Player
                if (_isInitialized && _controller != null)
                  Positioned.fill(
                    child: _DesktopVideoViewport(
                      controller: _controller!,
                      displayMode: _videoDisplayMode,
                    ),
                  ),

                // Subtitle Overlay
                if (_isInitialized) _buildSubtitleOverlay(),

                // 3. Loading Spinner
                if (!_isInitialized && !_hasError)
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              color: AppColors.accentPrimary,
                              strokeWidth: 3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isSlowLoad
                                ? 'Slow connection — still trying…'
                                : 'Loading stream…',
                            style: TextStyle(
                              color: _isSlowLoad
                                  ? AppColors.accentPrimary.withValues(
                                      alpha: 0.8,
                                    )
                                  : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          if (_isSlowLoad) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'You can switch server below if this takes too long.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                if (_hasError) _buildErrorOverlay(),

                // 4. Buffering Spinner
                if (_isInitialized && _isBuffering)
                  const Center(
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          color: AppColors.accentPrimary,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  ),

                // 5. Double Tap Seek Ripple Indicators
                if (_showRewindIndicator)
                  Positioned(
                    left: 40,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fast_rewind_rounded,
                              color: AppColors.accentPrimary,
                              size: 24,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '-10s',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (_showForwardIndicator)
                  Positioned(
                    right: 40,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '+10s',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              Icons.fast_forward_rounded,
                              color: AppColors.accentPrimary,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 6. Controls Overlay
                if (_isInitialized)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _showControls ? 1.0 : 0.0,
                        child: ExcludeFocus(
                          excluding: !_showControls,
                          child: ExcludeSemantics(
                            excluding: !_showControls,
                            child: IgnorePointer(
                              ignoring: !_showControls,
                              child: Stack(
                                children: [
                                  _buildTopBar(),
                                  _buildBottomControls(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (widget.showSkipButtons &&
                    _isInitialized &&
                    _activeSkipType(_currentPosition) != 0)
                  _buildSkipAction(_activeSkipType(_currentPosition) == 1),

                // 8. Auto-Next Countdown Overlay
                if (_showAutoNextOverlay)
                  Positioned(
                    bottom: _showControls ? 110 : 45,
                    right: 36,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.accentPrimary,
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Color(0x4DFF2A54),
                            blurRadius: 16,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.playlist_play_rounded,
                            color: AppColors.accentPrimary,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'UP NEXT',
                                style: TextStyle(
                                  color: AppColors.secondaryRed,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              Text(
                                'Next Episode in ${(_duration.inSeconds - _currentPosition.inSeconds).clamp(1, 35)}s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          DesktopFocusWrapper(
                            focusNode: _autoNextPlayFocusNode,
                            onTap: () {
                              widget.onPlayNext?.call();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accentPrimary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Play Now',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textMuted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () {
                              setState(() => _dismissedAutoNext = true);
                            },
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.isFullscreen) {
      return SizedBox.expand(
        child: Container(color: Colors.black, child: playerWidget),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: playerWidget,
        ),
      ),
    );
  }
}

/// Keeps the native surface tied to viewport pixels, even before metadata arrives.
class _DesktopVideoViewport extends StatefulWidget {
  final VideoPlayerController controller;
  final String displayMode;
  const _DesktopVideoViewport({
    required this.controller,
    required this.displayMode,
  });

  @override
  State<_DesktopVideoViewport> createState() => _DesktopVideoViewportState();
}

class _DesktopVideoViewportState extends State<_DesktopVideoViewport> {
  Size _sourceSize = const Size(16, 9);
  int _rotation = 0;

  @override
  void initState() {
    super.initState();
    _readGeometry();
    widget.controller.addListener(_updateGeometry);
  }

  @override
  void didUpdateWidget(covariant _DesktopVideoViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateGeometry);
      _sourceSize = const Size(16, 9);
      _rotation = 0;
      _readGeometry();
      widget.controller.addListener(_updateGeometry);
    }
  }

  void _readGeometry() {
    final value = widget.controller.value;
    final size = value.size;
    if (size.width.isFinite &&
        size.height.isFinite &&
        size.width > 0 &&
        size.height > 0) {
      _sourceSize = size;
    }
    _rotation = value.rotationCorrection;
  }

  void _updateGeometry() {
    final previousSize = _sourceSize;
    final previousRotation = _rotation;
    _readGeometry();
    if (mounted &&
        (previousSize != _sourceSize || previousRotation != _rotation)) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateGeometry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quarterTurn = (_rotation ~/ 90).isOdd;
    final ratio = quarterTurn
        ? _sourceSize.height / _sourceSize.width
        : _sourceSize.width / _sourceSize.height;
    return LayoutBuilder(
      builder: (context, bounds) {
        final fillsScreen =
            widget.displayMode == 'stretch' || widget.displayMode == 'zoom';
        final viewportRatio = fillsScreen
            ? bounds.maxWidth / bounds.maxHeight
            : widget.displayMode == 'original'
            ? ratio
            : 16 / 9;
        return Center(
          child: AspectRatio(
            key: const ValueKey('player-video-viewport'),
            aspectRatio: viewportRatio.isFinite && viewportRatio > 0
                ? viewportRatio
                : 16 / 9,
            child: LayoutBuilder(
              builder: (context, viewport) {
                final area = Size(viewport.maxWidth, viewport.maxHeight);
                final fit = widget.displayMode == 'stretch'
                    ? BoxFit.fill
                    : widget.displayMode == 'zoom'
                    ? BoxFit.cover
                    : BoxFit.contain;
                final fitted = applyBoxFit(fit, Size(ratio, 1), area);
                final imageSize = fit == BoxFit.cover
                    ? Size(ratio, 1) *
                          (area.width / ratio > area.height
                              ? area.width / ratio
                              : area.height)
                    : fitted.destination;
                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    minWidth: imageSize.width,
                    maxWidth: imageSize.width,
                    minHeight: imageSize.height,
                    maxHeight: imageSize.height,
                    child: SizedBox(
                      key: const ValueKey('player-video-image'),
                      width: imageSize.width,
                      height: imageSize.height,
                      child: RepaintBoundary(
                        child: VideoPlayer(
                          widget.controller,
                          key: ObjectKey(widget.controller),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
