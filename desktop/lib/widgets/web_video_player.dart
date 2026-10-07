import 'subtitle_delay_control.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'desktop_webview.dart';

import '../core/theme/app_colors.dart';
import '../models/video_provider.dart';
import 'desktop_focus_wrapper.dart';
import 'player_popup_focus.dart';
import '../core/focus/desktop_navigation_controller.dart';

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

class WebVideoPlayer extends StatefulWidget {
  final String embedUrl;
  final Map<String, String>? headers;
  final Function(String videoUrl)? onVideoExtracted;
  final ValueChanged<SubtitleTrack>? onSubtitleExtracted;
  final String animeTitle;
  final String episodeTitle;
  final VoidCallback? onVideoEnded;
  final VoidCallback? onPlayNext;
  final VoidCallback? onPlayPrev;
  final VoidCallback? onPlaybackFailed;
  final bool isStableProvider;
  final Duration initialPosition;
  final Function(Duration position)? onPositionChanged;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onBack;
  final bool isFullscreen;
  final String? preferredSubtitleLanguage;
  final double initialPlaybackSpeed;
  final ValueChanged<String>? onSubtitlePreferenceChanged;
  final ValueChanged<double>? onPlaybackSpeedChanged;

  /// Opens the episode picker from the player overlay.
  final VoidCallback? onShowEpisodes;

  /// Opens the server picker from the player overlay.
  final VoidCallback? onShowServers;

  /// Switches between the currently available SUB and DUB streams.
  final VoidCallback? onToggleLanguage;
  final String languageLabel;
  final String? serverLabel;
  final bool alwaysShowControls;
  final bool preferFlutterFullscreen;
  final bool autofocus;

  const WebVideoPlayer({
    super.key,
    required this.embedUrl,
    required this.animeTitle,
    required this.episodeTitle,
    this.headers,
    this.onVideoExtracted,
    this.onSubtitleExtracted,
    this.onVideoEnded,
    this.onPlayNext,
    this.onPlayPrev,
    this.onPlaybackFailed,
    this.isStableProvider = false,
    this.initialPosition = Duration.zero,
    this.onPositionChanged,
    this.onToggleFullscreen,
    this.onBack,
    this.isFullscreen = false,
    this.preferredSubtitleLanguage,
    this.initialPlaybackSpeed = 1.0,
    this.initialVideoDisplayMode = 'fit_16_9',
    this.onSubtitlePreferenceChanged,
    this.onPlaybackSpeedChanged,
    this.onVideoDisplayModeChanged,
    this.onShowEpisodes,
    this.onShowServers,
    this.onToggleLanguage,
    this.languageLabel = 'SUB',
    this.serverLabel,
    this.alwaysShowControls = false,
    this.preferFlutterFullscreen = false,
    this.autofocus = true,
  });

  final String initialVideoDisplayMode;
  final ValueChanged<String>? onVideoDisplayModeChanged;

  @override
  State<WebVideoPlayer> createState() => _WebVideoPlayerState();
}

class _WebVideoPlayerState extends State<WebVideoPlayer> {
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

  DesktopWebViewController? _controller;
  bool _isLoading = true;
  bool _isWebViewSupported = true;
  Timer? _loadTimeoutTimer;
  Timer? _postPageLoadTimer;
  bool _hasTimedOut = false;
  bool _hasReportedPlaybackFailure = false;
  bool _hasCalledOnEnded = false;
  bool _showControls = true;
  final bool _isLocked = false;
  bool _isMuted = false;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  String _subtitleLanguagePreference = 'English';
  int _subtitleDelayMilliseconds = 0;
  String _videoDisplayMode = 'fit_16_9';
  bool _hasUserSelectedSubtitleTrack = false;
  Timer? _hideControlsTimer;
  Duration _currentPosition = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _pendingSeekPosition;
  Timer? _pendingSeekDebounce;
  DateTime _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
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
  bool _playerHasFocus = false;

  // Set to true once the WebView HTML shell has finished loading.
  // We use a short secondary timer after this to keep the loading indicator
  // visible while the embedded iframe/player initialises.

  bool _pageLoadCompleted = false;

  bool _receivedVideoStatus = false;

  bool get _usesCustomControls => true;

  bool get _controlsVisible => widget.alwaysShowControls || _showControls;

  void _reportPlaybackFailure() {
    if (_hasReportedPlaybackFailure) return;
    _hasReportedPlaybackFailure = true;
    widget.onPlaybackFailed?.call();
  }

  double _normalizedPlaybackSpeed(double speed) {
    if (speed.isNaN || speed.isInfinite) return 1.0;
    return speed.clamp(0.25, 2.0).toDouble();
  }

  bool _subtitlePreferenceDisablesCaptions() {
    final preference = _subtitleLanguagePreference.toLowerCase().trim();
    return preference == 'off' ||
        preference == 'none' ||
        preference == 'disabled';
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

  bool _detectedTrackMatchesSubtitleLanguage(
    Map<String, dynamic> track,
    _SubtitleLanguageChoice choice,
  ) {
    final language = _normalizedSubtitleSearchText(
      track['language'] as String? ?? '',
    );
    final label = _normalizedSubtitleSearchText(
      track['label'] as String? ?? '',
    );

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

  int _detectedSubtitleTrackIndexForLanguage(_SubtitleLanguageChoice choice) {
    return _detectedSubtitleTracks.indexWhere(
      (track) => _detectedTrackMatchesSubtitleLanguage(track, choice),
    );
  }

  _SubtitleLanguageChoice? _subtitleLanguageChoiceForDetectedTrack(
    Map<String, dynamic> track,
  ) {
    for (final choice in _preferredSubtitleLanguages) {
      if (_detectedTrackMatchesSubtitleLanguage(track, choice)) return choice;
    }
    return null;
  }

  /// Returns true only for http(s) URLs. Rejects javascript:, data:, file:,
  /// content:, intent: and other non-web schemes that could be used for
  /// injection or to trick the WebView into loading local content.
  static bool _isSafeHttpUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _looksLikeSubtitleResourceUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.vtt') ||
        lower.contains('.srt') ||
        lower.contains('.ass') ||
        lower.contains('.ssa') ||
        lower.contains('subtitle') ||
        lower.contains('subtitles') ||
        lower.contains('caption') ||
        lower.contains('captions') ||
        RegExp(
          r'[?&](type|format|kind)=(vtt|srt|ass|ssa|subtitle|subtitles|caption|captions)',
        ).hasMatch(lower);
  }

  String _languageFromSubtitleText(String text) {
    final lower = _normalizedSubtitleSearchText(text);
    if (RegExp(r'(^|[^a-z])(en|eng|english)([^a-z]|$)').hasMatch(lower)) {
      return 'en';
    }
    if (RegExp(
      r'(^|[^a-z])(pt|pt-br|por|portuguese|portugues|brazilian)([^a-z]|$)',
    ).hasMatch(lower)) {
      return 'pt';
    }
    if (RegExp(
      r'(^|[^a-z])(es|spa|spanish|espanol|castilian|castellano)([^a-z]|$)',
    ).hasMatch(lower)) {
      return 'es';
    }
    return '';
  }

  String _labelForSubtitleLanguage(String language, String url) {
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
    return fileName.isNotEmpty ? fileName : 'Subtitle';
  }

  SubtitleTrack? _subtitleTrackFromExtractorMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;

    String url = trimmed;
    String label = '';
    String language = '';

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final data = Map<String, dynamic>.from(decoded);
          url = (data['url'] ?? data['file'] ?? data['src'] ?? '').toString();
          label = (data['label'] ?? data['name'] ?? data['title'] ?? '')
              .toString()
              .trim();
          language = (data['language'] ?? data['lang'] ?? data['srclang'] ?? '')
              .toString()
              .trim();
        }
      } catch (_) {
        url = trimmed;
      }
    }

    if (!_isSafeHttpUrl(url)) return null;
    language = language.isNotEmpty
        ? language
        : _languageFromSubtitleText('$label $url');
    label = label.isNotEmpty ? label : _labelForSubtitleLanguage(language, url);

    return SubtitleTrack(label: label, language: language, url: url);
  }

  void _loadUrl() {
    if (!_isWebViewSupported || _controller == null) return;
    _hasReportedPlaybackFailure = false;
    if (!_isSafeHttpUrl(widget.embedUrl)) {
      if (mounted) {
        setState(() {
          _hasTimedOut = true;
          _isLoading = false;
        });
      } else {
        _hasTimedOut = true;
        _isLoading = false;
      }
      _reportPlaybackFailure();
      return;
    }
    _hasTimedOut = false;
    _pageLoadCompleted = false;
    _loadTimeoutTimer?.cancel();
    _postPageLoadTimer?.cancel();
    _receivedVideoStatus = false;

    // Hard outer timeout: if page fails to load in 20s, show the error UI.
    _loadTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && !_receivedVideoStatus && !_isPlaying) {
        setState(() {
          _hasTimedOut = true;
          _isLoading = false;
        });
        _reportPlaybackFailure();
      }
    });

    final headers = Map<String, String>.from(widget.headers ?? {});
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
    }
    final reqUri = Uri.tryParse(widget.embedUrl);
    final reqHost = reqUri?.host.toLowerCase() ?? '';
    if (reqHost == 'megaplay.buzz' || reqHost.endsWith('.megaplay.buzz')) {
      headers.putIfAbsent('Referer', () => 'https://megaplay.buzz/');
      headers.putIfAbsent('Origin', () => 'https://megaplay.buzz');
    } else if (reqHost == 'ani.megaplay.su' ||
        reqHost.endsWith('.megaplay.su')) {
      headers.putIfAbsent('Referer', () => 'https://ani.megaplay.su/');
      headers.putIfAbsent('Origin', () => 'https://ani.megaplay.su');
    }

    // Load the provider as the top-level document. A synthetic iframe shell
    // drops request headers and hides cross-origin players from our controls.
    _controller!.loadRequest(Uri.parse(widget.embedUrl), headers: headers);
  }

  void _injectExtractor() {
    if ((widget.onVideoExtracted == null &&
            widget.onSubtitleExtracted == null) ||
        _controller == null) {
      return;
    }
    const js = r'''
(function() {
  // Embedded providers sometimes attach pop-under links to the first player
  // tap. Keep all playback interaction inside this WebView.
  try {
    window.open = function() { return null; };
    document.addEventListener('click', function(event) {
      var link = event.target && event.target.closest
        ? event.target.closest('a[target="_blank"]')
        : null;
      if (link) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    }, true);
  } catch (e) {}

  var sentMediaUrls = window.__aniwingsSentMediaUrls = window.__aniwingsSentMediaUrls || {};
  var sentSubtitleUrls = window.__aniwingsSentSubtitleUrls = window.__aniwingsSentSubtitleUrls || {};

  function absoluteUrl(url) {
    try {
      url = String(url || '').replace(/\\u002f/ig, '/').replace(/\\\//g, '/');
      if (!url || url.startsWith('blob:')) return '';
      return new URL(url, document.baseURI).href;
    } catch(e) {
      return url || '';
    }
  }

  function lowerText(value) {
    var text = String(value || '').toLowerCase().replace(/_/g, '-');
    if (text.normalize) {
      text = text.normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
    }
    return text;
  }

  function looksLikeSubtitleUrl(url) {
    var lower = lowerText(url);
    return lower.indexOf('.vtt') !== -1 ||
      lower.indexOf('.srt') !== -1 ||
      lower.indexOf('.ass') !== -1 ||
      lower.indexOf('.ssa') !== -1 ||
      lower.indexOf('subtitle') !== -1 ||
      lower.indexOf('subtitles') !== -1 ||
      lower.indexOf('caption') !== -1 ||
      lower.indexOf('captions') !== -1 ||
      /[?&](type|format|kind)=(vtt|srt|ass|ssa|subtitle|subtitles|caption|captions)/i.test(lower);
  }

  function hasSubtitleKind(kind) {
    var lower = lowerText(kind);
    return lower.indexOf('subtitle') !== -1 || lower.indexOf('caption') !== -1;
  }

  function isNonSubtitleKind(kind) {
    var lower = lowerText(kind);
    return lower.indexOf('thumbnail') !== -1 ||
      lower.indexOf('thumb') !== -1 ||
      lower.indexOf('chapter') !== -1 ||
      lower.indexOf('metadata') !== -1;
  }

  function hasUsefulTrackHint(label, language) {
    var hint = lowerText(label) + ' ' + lowerText(language);
    return hint.indexOf('english') !== -1 ||
      hint.indexOf(' eng') !== -1 ||
      hint.indexOf(' en') !== -1 ||
      hint.indexOf('portuguese') !== -1 ||
      hint.indexOf(' portugues') !== -1 ||
      hint.indexOf(' brazilian') !== -1 ||
      hint.indexOf(' por') !== -1 ||
      hint.indexOf(' pt') !== -1 ||
      hint.indexOf('spanish') !== -1 ||
      hint.indexOf(' espanol') !== -1 ||
      hint.indexOf(' castellano') !== -1 ||
      hint.indexOf(' spa') !== -1 ||
      hint.indexOf(' es') !== -1;
  }

  function mediaUrlScore(url) {
    var lower = lowerText(url);
    if (lower.indexOf('.m3u8') === -1 && lower.indexOf('.mp4') === -1) return 0;
    var score = lower.indexOf('.m3u8') !== -1 ? 2000 : 1000;
    if (
      lower.indexOf('master') !== -1 ||
      lower.indexOf('playlist') !== -1 ||
      lower.indexOf('index.m3u8') !== -1
    ) {
      score += 2000;
    }
    var match = lower.match(/(?:^|[^0-9])(2160|1440|1080|720|480|360|240)(?:p|[^0-9]|$)/);
    if (match) score += parseInt(match[1], 10) || 0;
    return score;
  }

  function flushBestMediaUrl() {
    window.__aniwingsMediaFlushTimer = null;
    var pending = window.__aniwingsPendingMediaUrls || [];
    if (!pending.length) return;

    var best = '';
    var bestScore = -1;
    for (var i = 0; i < pending.length; i++) {
      var candidate = pending[i];
      var score = mediaUrlScore(candidate);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    pending.length = 0;

    var lastSent = window.__aniwingsLastSentMediaUrl || '';
    var lastScore = window.__aniwingsBestSentMediaScore || 0;
    if (!best || (lastSent && bestScore <= lastScore)) return;

    window.__aniwingsLastSentMediaUrl = best;
    window.__aniwingsBestSentMediaScore = bestScore;
    if (window.VideoExtractor) {
      window.VideoExtractor.postMessage(best);
    }
  }

  function sendMediaUrl(url) {
    url = absoluteUrl(url);
    if (url && (url.indexOf('.m3u8') !== -1 || url.indexOf('.mp4') !== -1) && !url.startsWith('blob:')) {
      if (sentMediaUrls[url]) return;
      sentMediaUrls[url] = true;
      var pending = window.__aniwingsPendingMediaUrls = window.__aniwingsPendingMediaUrls || [];
      pending.push(url);
      if (!window.__aniwingsMediaFlushTimer) {
        window.__aniwingsMediaFlushTimer = setTimeout(flushBestMediaUrl, 250);
      }
    }
  }

  function sendSubtitleTrack(url, label, language, kind) {
    url = absoluteUrl(url);
    label = String(label || '');
    language = String(language || '');
    kind = String(kind || '');
    if (!url || url.startsWith('blob:')) return;
    if (isNonSubtitleKind(kind)) return;
    if (!hasSubtitleKind(kind) && !looksLikeSubtitleUrl(url) && !hasUsefulTrackHint(label, language)) return;
    if (sentSubtitleUrls[url]) return;
    sentSubtitleUrls[url] = true;
    if (window.SubtitleExtractor) {
      window.SubtitleExtractor.postMessage(JSON.stringify({
        url: url,
        label: label,
        language: language,
        kind: kind
      }));
    }
  }

  function sendSubtitleUrl(url) {
    sendSubtitleTrack(url, '', '', '');
  }

  function scanTextForResources(text) {
    try {
      if (!text || text.length > 2000000) return;
      text = String(text).replace(/\\u002f/ig, '/').replace(/\\\//g, '/');
      var urlRegex = /https?:\/\/[^"'<>\s)]+/ig;
      var match;
      while ((match = urlRegex.exec(text)) !== null) {
        inspectUrl(match[0]);
      }

      var fieldRegex = /["'](?:file|url|src)["']\s*:\s*["']([^"']+)["']/ig;
      while ((match = fieldRegex.exec(text)) !== null) {
        if (looksLikeSubtitleUrl(match[1])) {
          sendSubtitleTrack(match[1], '', '', '');
        } else {
          inspectUrl(match[1]);
        }
      }
    } catch (_) {}
  }

  function inspectTrackObject(track) {
    try {
      if (!track) return;
      var url = track.file || track.url || track.src || track.sources;
      if (Array.isArray(url)) {
        for (var i = 0; i < url.length; i++) inspectTrackObject(url[i]);
        return;
      }
      if (!url) return;
      sendSubtitleTrack(
        url,
        track.label || track.name || track.title || '',
        track.language || track.lang || track.srclang || '',
        track.kind || track.type || track.trackKind || ''
      );
    } catch (_) {}
  }

  function inspectCandidateObject(value, depth) {
    try {
      if (!value || depth > 3) return;
      if (Array.isArray(value)) {
        for (var i = 0; i < value.length; i++) {
          inspectCandidateObject(value[i], depth + 1);
        }
        return;
      }
      if (typeof value !== 'object') return;

      if (value.file || value.url || value.src) {
        var url = value.file || value.url || value.src;
        inspectUrl(url);
        inspectTrackObject(value);
      }

      var trackContainers = ['tracks', 'captions', 'subtitles', 'cc', 'textTracks'];
      for (var t = 0; t < trackContainers.length; t++) {
        inspectCandidateObject(value[trackContainers[t]], depth + 1);
      }

      var mediaContainers = ['sources', 'levels', 'allSources', 'playlist'];
      for (var m = 0; m < mediaContainers.length; m++) {
        inspectCandidateObject(value[mediaContainers[m]], depth + 1);
      }
    } catch (_) {}
  }

  function inspectKnownPlayers() {
    if (window.jwplayer && typeof window.jwplayer === 'function') {
      try {
        var jw = window.jwplayer();
        if (jw && typeof jw.getPlaylist === 'function') {
          inspectCandidateObject(jw.getPlaylist(), 0);
        }
        if (jw && typeof jw.getCaptionsList === 'function') {
          inspectCandidateObject(jw.getCaptionsList(), 0);
        }
        if (jw && typeof jw.getConfig === 'function') {
          inspectCandidateObject(jw.getConfig(), 0);
        }
      } catch (_) {}
    }

    var names = ['player', 'videojs', 'art', 'artplayer', 'plyr', 'hls', 'shakaPlayer'];
    for (var n = 0; n < names.length; n++) {
      try {
        inspectCandidateObject(window[names[n]], 0);
      } catch (_) {}
    }
  }

  function inspectDomTracks() {
    try {
      var tracks = document.querySelectorAll('track');
      for (var t = 0; t < tracks.length; t++) {
        if (tracks[t].src) {
          sendSubtitleTrack(
            tracks[t].src,
            tracks[t].label || '',
            tracks[t].srclang || tracks[t].lang || '',
            tracks[t].kind || ''
          );
        }
      }
    } catch (_) {}
  }

  function inspectDocumentTextOnce() {
    if (window.__aniwingsDocumentTextScanned) return;
    window.__aniwingsDocumentTextScanned = true;
    try {
      if (document.documentElement) {
        scanTextForResources(document.documentElement.innerHTML || '');
      }
    } catch (_) {}
  }

  function inspectUrl(url) {
    sendMediaUrl(url);
    sendSubtitleUrl(url);
  }

  function checkPerformance() {
    try {
      if (window.performance && window.performance.getEntriesByType) {
        var entries = window.performance.getEntriesByType('resource');
        for (var k = 0; k < entries.length; k++) {
          if (entries[k].name) {
            inspectUrl(entries[k].name);
          }
        }
      }
    } catch (_) {}
  }

  checkPerformance();
  inspectDomTracks();
  inspectKnownPlayers();
  inspectDocumentTextOnce();

  if (!window.hasVideoExtractorRun) {
    window.hasVideoExtractorRun = true;

    var open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__aniwingsRequestUrl = url;
      inspectUrl(url);
      return open.apply(this, arguments);
    };

    var send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function() {
      try {
        this.addEventListener('load', function() {
          inspectUrl(this.responseURL || this.__aniwingsRequestUrl || '');
          var contentType = '';
          try { contentType = this.getResponseHeader('content-type') || ''; } catch(e) {}
          if (/json|text|javascript|html/i.test(contentType)) {
            scanTextForResources(this.responseText || '');
          }
        });
      } catch(e) {}
      return send.apply(this, arguments);
    };

    var origFetch = window.fetch;
    window.fetch = function() {
      var args = arguments;
      var url = '';
      if (typeof args[0] === 'string') {
        url = args[0];
      } else if (args[0] && args[0].url) {
        url = args[0].url;
      }
      inspectUrl(url);
      return origFetch.apply(this, arguments).then(function(response) {
        try {
          inspectUrl(response.url || '');
          var contentType = response.headers ? (response.headers.get('content-type') || '') : '';
          if (/json|text|javascript|html/i.test(contentType)) {
            response.clone().text().then(scanTextForResources).catch(function() {});
          }
        } catch(e) {}
        return response;
      });
    };
  }

  var interval = setInterval(function() {
    checkPerformance();
    inspectDomTracks();
    inspectKnownPlayers();
    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      if (videos[i].src && !videos[i].src.startsWith('blob:')) {
        inspectUrl(videos[i].src);
      }
      var sources = videos[i].querySelectorAll('source');
      for (var j = 0; j < sources.length; j++) {
        if (sources[j].src) {
          inspectUrl(sources[j].src);
        }
      }
      var tracks = videos[i].querySelectorAll('track');
      for (var t = 0; t < tracks.length; t++) {
        if (tracks[t].src) {
          sendSubtitleTrack(
            tracks[t].src,
            tracks[t].label || '',
            tracks[t].srclang || tracks[t].lang || '',
            tracks[t].kind || ''
          );
        }
      }
    }
  }, 400);

  setTimeout(function() {
    clearInterval(interval);
  }, 30000);
})();
''';
    _controller!.runJavaScript(js).catchError((_) {});
  }

  List<Map<String, dynamic>> _detectedSubtitleTracks = [];
  int _selectedSubtitleTrackIndex = 0;

  void _injectVideoController() {
    if (_controller == null || !_usesCustomControls) return;
    final initialSeconds = (widget.initialPosition.inMilliseconds / 1000)
        .toStringAsFixed(3);
    final muted = _isMuted ? 'true' : 'false';
    final playbackSpeed = _playbackSpeed.toStringAsFixed(2);
    final subtitleTrackIndex = _selectedSubtitleTrackIndex;
    final js =
        '''
(function() {
  var initialPosition = $initialSeconds;
  var initialMuted = $muted;
  var initialPlaybackSpeed = $playbackSpeed;
  window.__aniwingsSelectedSubtitleTrack = $subtitleTrackIndex;


  function injectCSS(doc) {
    if (!doc || !doc.head) return;
    if (doc.getElementById('aniwings-hide-controls')) return;
    var style = doc.createElement('style');
    style.id = 'aniwings-hide-controls';
    style.textContent = `
      video::-webkit-media-controls { display: none !important; }
      video::-webkit-media-controls-enclosure { display: none !important; }
      video::-webkit-media-controls-panel { display: none !important; }
      video::-webkit-media-controls-play-button { display: none !important; }
      video::-webkit-media-controls-volume-control-container { display: none !important; }
      video::-webkit-media-controls-timeline { display: none !important; }
      video::-webkit-media-controls-mute-button { display: none !important; }
      video::-webkit-media-controls-fullscreen-button { display: none !important; }
      
      .jw-controlbar, .jw-display-icon-container, .jw-preview, .jw-settings-menu { display: none !important; }
      .vjs-control-bar, .vjs-big-play-button, .vjs-loading-spinner, .vjs-modal-dialog { display: none !important; }
      .plyr__controls, .plyr__control--overlaid, .plyr__video-control, .plyr__poster { display: none !important; }
      .fluid_controls_container, .fluid_initial_play_button, .fluid_html5_play { display: none !important; }
      .art-controls, .art-bottom, .art-layer-play, .art-mask { display: none !important; }

      /* Hide extra embed overlay buttons, ad popups, watermarks */
      [class*="ad-"], [id*="ad-"], [class*="popup"], [class*="overlay-button"],
      .anikoto-logo, .anikoto-fullscreen, .anikoto-btn,
      .jw-logo, .vjs-watermark, .fp-logo,
      a[target="_blank"],
      svg[class*="fullscreen"], div[class*="fullscreen-btn"] {
        display: none !important;
        visibility: hidden !important;
        pointer-events: none !important;
        opacity: 0 !important;
      }
      
      video::-webkit-media-text-track-container,
      video::-webkit-media-text-track-display,
      video::cue {
        display: block !important;
        opacity: 0 !important;
        display: none !important;
        z-index: 2147483647 !important;
      }
      
      .jw-captions,
      .jw-display-captions,
      .jw-text-track-display,
      .vjs-text-track-display,
      .plyr__captions,
      .art-subtitle,
      .art-subtitles,
      .shaka-text-container,
      [class*="caption"],
      [class*="subtitle"] {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
        z-index: 2147483646 !important;
      }
      
      body, html { overflow: hidden !important; margin: 0 !important; padding: 0 !important; width: 100% !important; height: 100% !important; background: #000 !important; }
      iframe, video { width: 100% !important; height: 100% !important; object-fit: contain !important; border: 0 !important; }
    `;
    doc.head.appendChild(style);
  }

  function findVideoInTree(win) {
    try {
      if (!win) return null;
      var v = null;
      try { v = win.document ? win.document.querySelector('video') : null; } catch(e) {}
      if (v) return v;
      var iframes = [];
      try { iframes = win.document ? win.document.getElementsByTagName('iframe') : []; } catch(e) {}
      for (var i = 0; i < iframes.length; i++) {
        try {
          var childV = findVideoInTree(iframes[i].contentWindow);
          if (childV) return childV;
        } catch(e) {}
      }
    } catch(e) {}
    return null;
  }

  function getSubtitles(v) {
    var tracks = [];
    try {
      if (v && v.textTracks) {
        for (var i = 0; i < v.textTracks.length; i++) {
          var t = v.textTracks[i];
          tracks.push({
            index: i,
            label: t.label || t.language || ('Subtitle ' + (i + 1)),
            language: t.language || '',
            mode: t.mode || 'disabled'
          });
        }
      }
    } catch(e) {}
    return tracks;
  }

  function applySubtitleSelection(video) {
    try {
      if (video && video.textTracks && video.textTracks.length > 0) {
        var selectedTrack = window.__aniwingsSelectedSubtitleTrack;
        if (typeof selectedTrack !== 'number') selectedTrack = 0;
        if (selectedTrack < 0) {
          for (var d = 0; d < video.textTracks.length; d++) {
            video.textTracks[d].mode = 'disabled';
          }
          return;
        }
        var targetTrack = selectedTrack < video.textTracks.length ? selectedTrack : 0;
        for (var i = 0; i < video.textTracks.length; i++) {
          video.textTracks[i].mode = i === targetTrack ? 'showing' : 'disabled';
        }
      }
    } catch(e) {}
  }

  var attempts = 0;
  function setupController() {
    attempts++;
    var video = findVideoInTree(window) || document.querySelector('video');
    if (!video) {
      if (attempts < 60) {
        setTimeout(setupController, 500);
      }
      return;
    }

    try { injectCSS(video.ownerDocument || document); } catch(e) {}

    if (!video.dataset.hasAniwingsController) {
      video.dataset.hasAniwingsController = 'true';
      video.controls = false;
      video.muted = initialMuted;
      video.playbackRate = initialPlaybackSpeed;
      video.style.setProperty('object-fit', video.dataset.awDisplayFit || 'contain', 'important');
    video.style.setProperty('transform', 'none', 'important');
    video.style.setProperty('zoom', '1', 'important');

      applySubtitleSelection(video);

      if (!video.dataset.aniwingsInitialSeekDone) {
        video.dataset.aniwingsInitialSeekDone = 'true';
        if (initialPosition > 0 && (!video.duration || initialPosition < video.duration)) {
          try {
            video.currentTime = initialPosition;
          } catch (e) {}
        }
      }

      function sendStatus() {
        applySubtitleSelection(video);
        if (window.VideoStatus) {
          window.VideoStatus.postMessage(JSON.stringify({
            currentTime: video.currentTime || 0,
            duration: video.duration || 0,
            paused: video.paused !== false,
            ended: !!video.ended,
            muted: !!video.muted,
            playbackRate: video.playbackRate || 1,
            subtitles: getSubtitles(video)
          }));
        }
      }

      video.addEventListener('play', sendStatus);
      video.addEventListener('pause', sendStatus);
      video.addEventListener('timeupdate', sendStatus);
      video.addEventListener('durationchange', sendStatus);
      video.addEventListener('ended', sendStatus);
      video.addEventListener('playing', sendStatus);

      video.play().catch(function() {});
      setInterval(sendStatus, 800);
      sendStatus();
    }
  }

  setupController();
})();
''';
    _controller!.runJavaScript(js).catchError((_) {});
  }

  void _injectStableWebControls() {
    if (_controller == null || !widget.isStableProvider) return;
    final preferredSubtitleLanguage = jsonEncode(_subtitleLanguagePreference);
    final js =
        '''
(function() {
  window.__aniwingsPreferredSubtitleLanguage = $preferredSubtitleLanguage;
  if (window.hasAniwingsStableControlsRun) {
    applyAllVideos();
    return;
  }
  window.hasAniwingsStableControlsRun = true;

  function notify(msg) {
    if (window.StableFullscreen) {
      window.StableFullscreen.postMessage(msg);
    }
  }

  function normalizeSubtitleText(value) {
    var text = String(value || '').toLowerCase().trim().replace(/_/g, '-');
    if (text.normalize) {
      text = text.normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
    }
    return text;
  }

  function subtitleAliases() {
    var pref = normalizeSubtitleText(window.__aniwingsPreferredSubtitleLanguage || 'English');
    if (pref === 'off' || pref === 'none' || pref === 'disabled') return null;
    if (pref.indexOf('portuguese') !== -1 || pref === 'pt' || pref === 'pt-br' || pref === 'por' || pref === 'brazilian') {
      return ['pt', 'pt-br', 'por', 'portuguese', 'portugues', 'brazilian'];
    }
    if (pref.indexOf('spanish') !== -1 || pref === 'es' || pref === 'spa' || pref === 'castellano') {
      return ['es', 'spa', 'spanish', 'espanol', 'castilian', 'castellano'];
    }
    return ['en', 'eng', 'english'];
  }

  function trackMatches(track, aliases) {
    var language = normalizeSubtitleText(track.language || '');
    var label = normalizeSubtitleText(track.label || '');
    for (var a = 0; a < aliases.length; a++) {
      var alias = aliases[a];
      if (alias.length <= 3) {
        if (language === alias || language.indexOf(alias + '-') === 0) return true;
      } else if (language === alias || label.indexOf(alias) !== -1) {
        return true;
      }
    }
    return false;
  }

  function applyPreferredSubtitles(video) {
    try {
      if (!video || !video.textTracks || video.textTracks.length === 0) return;
      var aliases = subtitleAliases();
      var selected = -1;
      if (aliases) {
        for (var i = 0; i < video.textTracks.length; i++) {
          if (trackMatches(video.textTracks[i], aliases)) {
            selected = i;
            break;
          }
        }
      }
      for (var j = 0; j < video.textTracks.length; j++) {
        video.textTracks[j].mode = j === selected ? 'showing' : 'disabled';
      }
    } catch(e) {}
  }

  function visitVideos(win, callback) {
    try {
      if (!win || !win.document) return;
      var videos = win.document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) callback(videos[i]);
      var iframes = win.document.getElementsByTagName('iframe');
      for (var j = 0; j < iframes.length; j++) {
        try {
          visitVideos(iframes[j].contentWindow, callback);
        } catch(e) {}
      }
    } catch(e) {}
  }

  function enableVideo(video) {
    video.controls = false;
    video.removeAttribute('controls');
    video.setAttribute('playsinline', 'playsinline');
    video.setAttribute('webkit-playsinline', 'webkit-playsinline');
    video.style.setProperty('object-fit', video.dataset.awDisplayFit || 'contain', 'important');
    video.style.setProperty('transform', 'none', 'important');
    video.style.setProperty('zoom', '1', 'important');
    applyPreferredSubtitles(video);
    if (video.paused && !video.dataset.aniwingsAutoPlayTried) {
      video.dataset.aniwingsAutoPlayTried = 'true';
      video.play().catch(function() {});
    }
  }

  function applyAllVideos() {
    visitVideos(window, enableVideo);
  }

  var style = document.createElement('style');
  style.id = 'aniwings-stable-web-controls';
  style.textContent = `
    html, body {
      margin: 0 !important;
      padding: 0 !important;
      width: 100% !important;
      height: 100% !important;
      background: #000 !important;
      overflow: hidden !important;
    }
    video {
      width: 100% !important;
      height: 100% !important;
      object-fit: contain !important;
      background: #000 !important;
    }
    video::-webkit-media-controls,
    video::-webkit-media-controls-enclosure,
    video::-webkit-media-controls-panel {
      display: none !important;
      opacity: 0 !important;
    }
  `;
  if (document.head && !document.getElementById(style.id)) {
    document.head.appendChild(style);
  }

  var preferFlutterFullscreen = ${widget.preferFlutterFullscreen ? 'true' : 'false'};

  function hook(obj, name, msg) {
    if (!obj) return;
    var orig = obj[name];
    if (typeof orig === 'function' && !obj['_aw_' + name]) {
      obj['_aw_' + name] = orig;
      obj[name] = function() {
        notify(msg);
        if (preferFlutterFullscreen) {
          return Promise.resolve();
        }
        try {
          return orig.apply(this, arguments);
        } catch(e) {
          return Promise.resolve();
        }
      };
    }
  }

  ['requestFullscreen', 'webkitRequestFullscreen', 'webkitRequestFullScreen', 'mozRequestFullScreen', 'msRequestFullscreen'].forEach(function(m) {
    hook(Element.prototype, m, 'enter');
  });

  ['exitFullscreen', 'webkitExitFullscreen', 'webkitCancelFullScreen', 'mozCancelFullScreen', 'msExitFullscreen'].forEach(function(m) {
    hook(Document.prototype, m, 'exit');
  });

  if (window.HTMLVideoElement) {
    ['webkitEnterFullscreen', 'webkitEnterFullScreen'].forEach(function(m) {
      hook(HTMLVideoElement.prototype, m, 'enter');
    });
    ['webkitExitFullscreen', 'webkitExitFullScreen'].forEach(function(m) {
      hook(HTMLVideoElement.prototype, m, 'exit');
    });
  }

  function onFSChange() {
    var isFS = !!(document.fullscreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement);
    notify(isFS ? 'enter' : 'exit');
  }

  document.addEventListener('fullscreenchange', onFSChange, true);
  document.addEventListener('webkitfullscreenchange', onFSChange, true);
  document.addEventListener('mozfullscreenchange', onFSChange, true);
  document.addEventListener('MSFullscreenChange', onFSChange, true);

  applyAllVideos();
  setInterval(applyAllVideos, 1500);
  if (document.documentElement) {
    new MutationObserver(applyAllVideos).observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }
})();
''';
    _controller!.runJavaScript(js).catchError((_) {});
  }

  void _toggleFullscreen() {
    widget.onToggleFullscreen?.call();
  }

  void _requestPlayerFocus(FocusNode node) {
    if (mounted && node.canRequestFocus) node.requestFocus();
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
    final isBackKey =
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.gameButtonSelect;
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

    // Desktop Hotkeys (F for fullscreen):
    if (key == LogicalKeyboardKey.keyF) {
      widget.onToggleFullscreen?.call();
      return KeyEventResult.handled;
    }

    // 2. Media transport keys:
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (key == LogicalKeyboardKey.mediaPlay && !_isPlaying) {
        if (_usesCustomControls) _togglePlay();
      } else if (key == LogicalKeyboardKey.mediaPause && _isPlaying) {
        if (_usesCustomControls) _togglePlay();
      } else if (key == LogicalKeyboardKey.mediaPlayPause) {
        if (_usesCustomControls) {
          _togglePlay();
        } else {
          _toggleControlsVisibility();
        }
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaRewind) {
      if (_usesCustomControls) _seekBy(-10);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaFastForward) {
      if (_usesCustomControls) _seekBy(10);
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
        if (_usesCustomControls) {
          _togglePlay();
        } else {
          _toggleControlsVisibility();
        }
        return KeyEventResult.handled;
      }

      // If a control button already has focus, let the focused button handle Enter/Select!
      return KeyEventResult.ignored;
    }

    // 4. Left / Right Arrow keys (Seeking):
    // When controls are hidden or when player has primary focus: seek by 10 seconds!
    if (_usesCustomControls &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.gameButtonLeft1)) {
      if (!_showControls || !controlsHavePrimaryFocus) {
        _seekBy(-10);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_usesCustomControls &&
        (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.gameButtonRight1)) {
      if (!_showControls || !controlsHavePrimaryFocus) {
        _seekBy(10);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 5. Up / Down Arrow keys:
    // Open controls and focus Play/Pause button
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (!_showControls) {
        _interactWithControls();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showControls) {
            _playPauseFocusNode.requestFocus();
          }
        });
        return KeyEventResult.handled;
      }
      if (node.hasPrimaryFocus && _usesCustomControls) {
        _playPauseFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  void _retryWebViewLoad() {
    if (!_isWebViewSupported || _controller == null) return;
    setState(() {
      _hasTimedOut = false;
      _isLoading = true;
      _receivedVideoStatus = false;
      _hasReportedPlaybackFailure = false;
    });
    _loadUrl();
  }

  Widget _buildWebErrorOverlay() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
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
              'This player did not start.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Retry this server or choose another one.',
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
              onPressed: _retryWebViewLoad,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runVideoCommand(String command) async {
    if (_controller == null) return;
    await _controller!
        .runJavaScript('''
(function() {
  function findVideoInTree(win) {
    try {
      if (!win || !win.document) return null;
      var v = win.document.querySelector('video');
      if (v) return v;
      var iframes = win.document.getElementsByTagName('iframe');
      for (var i = 0; i < iframes.length; i++) {
        try {
          var childV = findVideoInTree(iframes[i].contentWindow);
          if (childV) return childV;
        } catch(e) {}
      }
    } catch(e) {}
    return null;
  }
  var video = findVideoInTree(window) || document.querySelector('video');
  if (!video) return;
  $command
})();
''')
        .catchError((_) {});
  }

  void _setSubtitleTrack(int trackIndex) {
    _runVideoCommand('''
      window.__aniwingsSelectedSubtitleTrack = $trackIndex;
      if (video && video.textTracks) {
        for (var i = 0; i < video.textTracks.length; i++) {
          if ($trackIndex === -1) {
            video.textTracks[i].mode = 'disabled';
          } else if (i === $trackIndex) {
            video.textTracks[i].mode = 'showing';
          } else {
            video.textTracks[i].mode = 'disabled';
          }
        }
      }
    ''');
  }

  void _setSubtitleLanguagePreference(String preference) {
    final encodedPreference = jsonEncode(preference);
    _runVideoCommand('''
      window.__aniwingsPreferredSubtitleLanguage = $encodedPreference;
      function normalizeSubtitleText(value) {
        var text = String(value || '').toLowerCase().trim().replace(/_/g, '-');
        if (text.normalize) {
          text = text.normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
        }
        return text;
      }
      function subtitleAliases() {
        var pref = normalizeSubtitleText(window.__aniwingsPreferredSubtitleLanguage || 'English');
        if (pref === 'off' || pref === 'none' || pref === 'disabled') return null;
        if (pref.indexOf('portuguese') !== -1 || pref === 'pt' || pref === 'pt-br' || pref === 'por' || pref === 'brazilian') {
          return ['pt', 'pt-br', 'por', 'portuguese', 'portugues', 'brazilian'];
        }
        if (pref.indexOf('spanish') !== -1 || pref === 'es' || pref === 'spa' || pref === 'castellano') {
          return ['es', 'spa', 'spanish', 'espanol', 'castilian', 'castellano'];
        }
        return ['en', 'eng', 'english'];
      }
      function trackMatches(track, aliases) {
        var language = normalizeSubtitleText(track.language || '');
        var label = normalizeSubtitleText(track.label || '');
        for (var a = 0; a < aliases.length; a++) {
          var alias = aliases[a];
          if (alias.length <= 3) {
            if (language === alias || language.indexOf(alias + '-') === 0) return true;
          } else if (language === alias || label.indexOf(alias) !== -1) {
            return true;
          }
        }
        return false;
      }
      var aliases = subtitleAliases();
      var selected = -1;
      if (aliases && video.textTracks) {
        for (var i = 0; i < video.textTracks.length; i++) {
          if (trackMatches(video.textTracks[i], aliases)) {
            selected = i;
            break;
          }
        }
      }
      if (video.textTracks) {
        for (var j = 0; j < video.textTracks.length; j++) {
          video.textTracks[j].mode = j === selected ? 'showing' : 'disabled';
        }
      }
    ''');
    _injectStableWebControls();
  }

  String _subtitlePreferenceLabelForIndex(int trackIndex) {
    if (trackIndex < 0) return 'Off';
    if (trackIndex < _detectedSubtitleTracks.length) {
      final track = _detectedSubtitleTracks[trackIndex];
      final language = track['language'] as String?;
      final label = track['label'] as String?;
      if (language != null && language.isNotEmpty) return language;
      if (label != null && label.isNotEmpty) return label;
    }
    return 'On';
  }

  String _subtitleStatusLabel() {
    if (_selectedSubtitleTrackIndex < 0) return 'Off';
    final preferenceChoice = _subtitleLanguageChoiceForPreference(
      _subtitleLanguagePreference,
    );
    if (preferenceChoice != null) return preferenceChoice.label;

    if (_selectedSubtitleTrackIndex < _detectedSubtitleTracks.length) {
      final track = _detectedSubtitleTracks[_selectedSubtitleTrackIndex];
      final choice = _subtitleLanguageChoiceForDetectedTrack(track);
      if (choice != null) return choice.label;
      return 'On';
    }
    return 'On';
  }

  void _changeSubtitleTrack(int trackIndex, {String? preferenceLabel}) {
    _hasUserSelectedSubtitleTrack = true;
    setState(() => _selectedSubtitleTrackIndex = trackIndex);
    _subtitleLanguagePreference =
        preferenceLabel ?? _subtitlePreferenceLabelForIndex(trackIndex);
    if (trackIndex < 0) {
      _setSubtitleLanguagePreference(_subtitleLanguagePreference);
    } else {
      _setSubtitleTrack(trackIndex);
    }
    widget.onSubtitlePreferenceChanged?.call(_subtitleLanguagePreference);
  }

  void _changeSubtitleLanguage(_SubtitleLanguageChoice choice) {
    final detectedIndex = _detectedSubtitleTrackIndexForLanguage(choice);
    _hasUserSelectedSubtitleTrack = true;
    setState(() {
      _subtitleLanguagePreference = choice.preference;
      _selectedSubtitleTrackIndex = detectedIndex == -1 ? 0 : detectedIndex;
    });
    _setSubtitleLanguagePreference(choice.preference);
    widget.onSubtitlePreferenceChanged?.call(choice.preference);
  }

  void _showSubtitlesSheet(BuildContext context) {
    _showDesktopOptionsPopup(
      context: context,
      useRootNavigator: true,

      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isEnabled = _selectedSubtitleTrackIndex != -1;
          return _buildFloatingSheetSurface(
            ctx,
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SubtitleDelayControl(
                      initialMilliseconds: _subtitleDelayMilliseconds,
                      onChanged: (value) {
                        setState(() => _subtitleDelayMilliseconds = value);
                        _applySubtitleDelay();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Subtitles / Captions',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close player menu',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Master Toggle Switch
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
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
                                    ? AppColors.accentPrimary
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                isEnabled
                                    ? 'Subtitles Enabled (ON)'
                                    : 'Subtitles Disabled (OFF)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: isEnabled,
                            activeTrackColor: AppColors.accentPrimary,
                            onChanged: (val) {
                              if (val) {
                                final preferenceChoice =
                                    _subtitleLanguageChoiceForPreference(
                                      _subtitleLanguagePreference,
                                    );
                                _changeSubtitleLanguage(
                                  preferenceChoice ??
                                      _preferredSubtitleLanguages.first,
                                );
                              } else {
                                _changeSubtitleTrack(
                                  -1,
                                  preferenceLabel: 'Off',
                                );
                              }
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white12),

                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Subtitle Language',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    ..._preferredSubtitleLanguages.map((choice) {
                      final idx = _detectedSubtitleTrackIndexForLanguage(
                        choice,
                      );
                      final track = idx == -1
                          ? null
                          : _detectedSubtitleTracks[idx];
                      final preferenceChoice =
                          _subtitleLanguageChoiceForPreference(
                            _subtitleLanguagePreference,
                          );
                      final isShowing =
                          isEnabled &&
                          preferenceChoice?.preference == choice.preference;
                      return _buildSheetFocusItem(
                        label: 'Subtitle ${choice.label}',
                        autofocus: isShowing,
                        onTap: () {
                          _changeSubtitleLanguage(choice);
                          Navigator.pop(ctx);
                        },
                        child: ListTile(
                          leading: Icon(
                            Icons.subtitles_rounded,
                            color: isShowing
                                ? AppColors.accentPrimary
                                : Colors.white54,
                          ),
                          title: Text(
                            choice.label,
                            style: TextStyle(
                              color: isShowing ? Colors.white : Colors.white70,
                              fontWeight: isShowing
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            track == null
                                ? (_detectedSubtitleTracks.isEmpty
                                      ? 'Select when available'
                                      : 'Not available for this stream')
                                : choice.label,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isShowing
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.accentPrimary,
                                )
                              : null,
                          onTap: null,
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _startHideControlsTimer() {
    if (_openPopups > 0) return;
    if (!_usesCustomControls) return;
    _hideControlsTimer?.cancel();
    if (!_isPlaying || _isLocked || widget.alwaysShowControls) return;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying && !_isLocked) {
        _hideControlsForPlayback();
      }
    });
  }

  void _hideControlsForPlayback() {
    if (_openPopups > 0) return;
    if (!mounted || !_showControls) return;
    setState(() => _showControls = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_showControls) {
        _playerFocusNode.requestFocus();
      }
    });
  }

  void _interactWithControls() {
    if (_isLocked || !_usesCustomControls) return;
    if (mounted && !_showControls) {
      setState(() => _showControls = true);
    }
    if (widget.alwaysShowControls) return;
    _startHideControlsTimer();
  }

  void _toggleControlsVisibility() {
    if (!_usesCustomControls) return;
    if (widget.alwaysShowControls && !_isLocked) {
      if (!_showControls) {
        setState(() => _showControls = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showControls) {
            _playPauseFocusNode.requestFocus();
          }
        });
      }
      return;
    }
    if (_isLocked) {
      // When locked, allow briefly showing the lock icon to unlock
      if (!_showControls) {
        setState(() => _showControls = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _isLocked) setState(() => _showControls = false);
        });
      } else {
        setState(() => _showControls = false);
      }
      return;
    }
    final willShow = !_showControls;
    setState(() => _showControls = willShow);
    if (willShow) {
      _startHideControlsTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showControls) {
          _playPauseFocusNode.requestFocus();
        }
      });
    } else {
      _hideControlsTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_showControls) {
          _playerFocusNode.requestFocus();
        }
      });
    }
  }

  void _togglePlay() {
    if (!_usesCustomControls) return;
    _interactWithControls();
    _loadTimeoutTimer?.cancel();
    _postPageLoadTimer?.cancel();
    if (_isPlaying) {
      _runVideoCommand('video.pause();');
      setState(() {
        _isPlaying = false;
        _isLoading = false;
      });
    } else {
      _runVideoCommand('video.play().catch(function() {});');
      setState(() {
        _isPlaying = true;
      });
    }
    _startHideControlsTimer();
  }

  void _seekBy(int seconds) {
    if (!_usesCustomControls) return;
    _interactWithControls();

    final base = _pendingSeekPosition ?? _currentPosition;
    final max = _duration > Duration.zero
        ? _duration
        : const Duration(hours: 5);
    final targetMs = (base.inMilliseconds + seconds * 1000).clamp(
      0,
      max.inMilliseconds,
    );
    final target = Duration(milliseconds: targetMs);

    setState(() {
      _pendingSeekPosition = target;
      _currentPosition = target;
    });

    _pendingSeekDebounce?.cancel();
    _pendingSeekDebounce = Timer(const Duration(milliseconds: 300), () {
      final seekTarget = _pendingSeekPosition;
      _pendingSeekDebounce = null;
      if (seekTarget != null) {
        _seekTo(seekTarget);
      }
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _pendingSeekDebounce == null) {
          _pendingSeekPosition = null;
        }
      });
    });
  }

  void _seekTo(Duration position) {
    if (!_usesCustomControls) return;
    final seconds = (position.inMilliseconds / 1000).toStringAsFixed(3);
    _runVideoCommand(
      'video.currentTime = Math.max(0, Math.min(video.duration || 0, $seconds));',
    );
    _interactWithControls();
  }

  void _changeSpeed(double speed) {
    final nextSpeed = _normalizedPlaybackSpeed(speed);
    setState(() => _playbackSpeed = nextSpeed);
    _runVideoCommand('video.playbackRate = $nextSpeed;');
    widget.onPlaybackSpeedChanged?.call(nextSpeed);
    _interactWithControls();
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

  int _openPopups = 0;

  void _showDesktopOptionsPopup({
    required BuildContext context,
    required WidgetBuilder builder,
    bool useRootNavigator = true,
  }) {
    final opener = FocusManager.instance.primaryFocus;
    _openPopups++;
    _hideControlsTimer?.cancel();
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: useRootNavigator,
        barrierColor: Colors.black.withValues(alpha: 0.65),
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: PlayerPopupFocus(
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) {
                if (DesktopNavigationController.isDesktopBackKey(event)) {
                  Navigator.of(ctx).pop();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: SingleChildScrollView(child: builder(ctx)),
            ),
          ),
        ),
      ).whenComplete(() {
        _openPopups--;
        if (!mounted || _openPopups > 0) return;
        _interactWithControls();
        if (opener?.context != null && opener!.canRequestFocus) {
          opener.requestFocus();
        } else {
          _playPauseFocusNode.requestFocus();
        }
      }),
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused
                  ? Colors.white
                  : hovered
                  ? Colors.white54
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFloatingSheetSurface(BuildContext context, Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: Material(
          color: AppColors.secondaryBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white24),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context) {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    _showDesktopOptionsPopup(
      context: context,
      useRootNavigator: true,

      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) => _buildFloatingSheetSurface(
          innerCtx,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Playback Speed',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close player menu',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ...speeds.map((speed) {
                final isSelected = _playbackSpeed == speed;
                return _buildSheetFocusItem(
                  label: 'Playback speed ${speed}x',
                  autofocus: isSelected,
                  onTap: () {
                    _changeSpeed(speed);
                    setSheetState(() {});
                    Navigator.of(ctx).pop();
                  },
                  child: ListTile(
                    title: Text(
                      speed == 1.0 ? 'Normal (1.0x)' : '${speed}x',
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.accentPrimary
                            : Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.accentPrimary,
                          )
                        : null,
                    onTap: null,
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext sheetContext) {
    _showDesktopOptionsPopup(
      context: sheetContext,
      useRootNavigator: true,

      builder: (ctx) {
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        final safeBottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(
            bottom: bottomInset + safeBottom + 28,
            left: 14,
            right: 14,
          ),
          child: _buildFloatingSheetSurface(
            ctx,
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Player Settings',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close player menu',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildSheetFocusItem(
                  label: 'Stream quality',
                  autofocus: true,
                  onTap: () => Navigator.of(ctx).pop(),
                  child: const ListTile(
                    leading: Icon(Icons.hd_rounded, color: Colors.white70),
                    title: Text(
                      'Stream Quality',
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: Text(
                      'Auto (Adaptive)',
                      style: TextStyle(
                        color: AppColors.accentPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: null,
                  ),
                ),
                _buildSheetFocusItem(
                  label: 'Aspect ratio setting',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Future.delayed(const Duration(milliseconds: 120), () {
                      if (mounted) _showAspectRatioSheet(context);
                    });
                  },
                  child: ListTile(
                    leading: const Icon(
                      Icons.aspect_ratio_rounded,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'Aspect Ratio / Display',
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: Text(
                      _videoDisplayModeLabel(_videoDisplayMode),
                      style: const TextStyle(
                        color: AppColors.accentPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: null,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
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

  void _applySubtitleDelay() {
    _runVideoCommand("""
      if (video) {
        video.dataset.awSubtitleDelay = '${_subtitleDelayMilliseconds / 1000}';
        if (!video.awDelayTimer) video.awDelayTimer = setInterval(function() {
          for (var track of video.textTracks) {
            for (var cue of (track.cues || [])) {
              if (cue.awStart === undefined) { cue.awStart = cue.startTime; cue.awEnd = cue.endTime; }
              var delay = Number(video.dataset.awSubtitleDelay || 0);
              cue.startTime = Math.max(0, cue.awStart + delay);
              cue.endTime = Math.max(cue.startTime + 0.001, cue.awEnd + delay);
            }
          }
        }, 250);
      }
    """);
  }

  void _applyVideoDisplayMode(String mode) {
    final objectFit = (mode == 'stretch')
        ? 'fill'
        : (mode == 'zoom')
        ? 'cover'
        : 'contain';
    _runVideoCommand('''
      if (video) {
        video.dataset.awDisplayFit = '$objectFit';
        video.style.setProperty('object-fit', '$objectFit', 'important');
      }
    ''');
  }

  void _showAspectRatioSheet(BuildContext context) {
    _showDesktopOptionsPopup(
      context: context,
      useRootNavigator: true,

      builder: (ctx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom:
                  MediaQuery.viewInsetsOf(innerCtx).bottom +
                  MediaQuery.paddingOf(innerCtx).bottom +
                  28,
              left: 14,
              right: 14,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.secondaryBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Aspect Ratio / Display Mode',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close player menu',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._aspectRatioOptions.map((opt) {
                    final id = opt['id']!;
                    final label = opt['label']!;
                    final desc = opt['desc']!;
                    final isSelected = _videoDisplayMode == id;
                    return _buildSheetFocusItem(
                      label: 'Aspect ratio $label',
                      autofocus: isSelected,
                      onTap: () {
                        setState(() => _videoDisplayMode = id);
                        _applyVideoDisplayMode(id);
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
                        title: Text(
                          label,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.accentPrimary
                                : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          desc,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.accentPrimary,
                              )
                            : null,
                        onTap: null,
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Player actions need a dedicated focus treatment on desktop. The platform's
  /// default IconButton focus state is not reliably visible over video.
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
        borderRadius: BorderRadius.circular((buttonSize + 8) / 2),
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

  Widget _buildTopBar() {
    if (!widget.isFullscreen) return const SizedBox.shrink();
    final isFull = widget.isFullscreen;

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
                Colors.black.withValues(alpha: 0.82),
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
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                directionalKeyHandlers: _playerDirections(
                  right: widget.onToggleFullscreen != null
                      ? _fullscreenFocusNode
                      : null,
                  down: _playPauseFocusNode,
                ),
              ),
              SizedBox(width: isFull ? 16 : 10),
              Expanded(
                child: Text(
                  '${widget.animeTitle} · ${widget.episodeTitle}',
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

  Widget _buildBottomControls() {
    final isFull = widget.isFullscreen;
    final maxMs = _duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final currentMs = _currentPosition.inMilliseconds.toDouble().clamp(
      0.0,
      maxMs,
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
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
                        onChanged: (value) =>
                            _seekTo(Duration(milliseconds: value.toInt())),
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
              SizedBox(
                height: isFull ? 60 : 52,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTransportButton(
                          icon: Icons.skip_previous_rounded,
                          size: isFull ? 30 : 24,
                          onPressed: widget.onPlayPrev,
                          enabled: widget.onPlayPrev != null,
                          focusNode: _previousFocusNode,
                          rightFocusNode: _rewindFocusNode,
                          upFocusNode: _topBackFocusNode,
                        ),
                        _buildTransportButton(
                          icon: Icons.replay_10_rounded,
                          size: isFull ? 28 : 22,
                          onPressed: () => _seekBy(-10),
                          focusNode: _rewindFocusNode,
                          leftFocusNode: widget.onPlayPrev != null
                              ? _previousFocusNode
                              : null,
                          rightFocusNode: _playPauseFocusNode,
                          upFocusNode: widget.onShowEpisodes != null
                              ? _episodesFocusNode
                              : _topBackFocusNode,
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isFull ? 10 : 6,
                          ),
                          child: _buildRemoteIconControl(
                            focusNode: _playPauseFocusNode,
                            icon: _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            label: _isPlaying ? 'Pause' : 'Play',
                            size: isFull ? 46 : 34,
                            buttonSize: isFull ? 52 : 44,
                            onTap: _togglePlay,
                            directionalKeyHandlers: _playerDirections(
                              left: _rewindFocusNode,
                              right: _forwardFocusNode,
                              up: widget.onShowEpisodes != null
                                  ? _episodesFocusNode
                                  : _settingsFocusNode,
                            ),
                          ),
                        ),
                        _buildTransportButton(
                          icon: Icons.forward_10_rounded,
                          size: isFull ? 28 : 22,
                          onPressed: () => _seekBy(10),
                          focusNode: _forwardFocusNode,
                          leftFocusNode: _playPauseFocusNode,
                          rightFocusNode: widget.onPlayNext != null
                              ? _nextFocusNode
                              : null,
                          upFocusNode: _settingsFocusNode,
                        ),
                        _buildTransportButton(
                          icon: Icons.skip_next_rounded,
                          size: isFull ? 30 : 24,
                          onPressed: widget.onPlayNext,
                          enabled: widget.onPlayNext != null,
                          focusNode: _nextFocusNode,
                          leftFocusNode: _forwardFocusNode,
                          upFocusNode: _settingsFocusNode,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: isFull ? 6 : 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.onToggleLanguage != null &&
                        widget.isFullscreen) ...[
                      _buildRemoteIconControl(
                        focusNode: _languageFocusNode,
                        icon: widget.languageLabel.toUpperCase() == 'DUB'
                            ? Icons.mic_rounded
                            : Icons.subtitles_rounded,
                        label: 'Audio: ${widget.languageLabel.toUpperCase()}',
                        size: isFull ? 22 : 18,
                        onTap: widget.onToggleLanguage,
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (widget.onShowServers != null &&
                        widget.isFullscreen) ...[
                      _buildRemoteIconControl(
                        focusNode: _serverFocusNode,
                        icon: Icons.dns_rounded,
                        label: widget.serverLabel == null
                            ? 'Servers'
                            : 'Server: ${widget.serverLabel}',
                        size: isFull ? 22 : 18,
                        onTap: widget.onShowServers,
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (widget.onShowEpisodes != null &&
                        widget.isFullscreen) ...[
                      _buildRemoteIconControl(
                        focusNode: _episodesFocusNode,
                        icon: Icons.video_library_rounded,
                        label: 'Episodes',
                        size: isFull ? 22 : 18,
                        onTap: widget.onShowEpisodes,
                      ),
                      const SizedBox(width: 4),
                    ],
                    _buildRemoteIconControl(
                      focusNode: _speedFocusNode,
                      icon: Icons.speed_rounded,
                      label: 'Playback speed (${_playbackSpeed}x)',
                      size: isFull ? 22 : 18,
                      onTap: () => _showSpeedSheet(context),
                    ),
                    const SizedBox(width: 4),
                    _buildRemoteIconControl(
                      focusNode: _subtitleFocusNode,
                      icon: Icons.subtitles_rounded,
                      label: 'Player subtitles (${_subtitleStatusLabel()})',
                      size: isFull ? 22 : 18,
                      onTap: () => _showSubtitlesSheet(context),
                    ),
                    const SizedBox(width: 4),
                    _buildRemoteIconControl(
                      focusNode: _settingsFocusNode,
                      icon: Icons.settings_rounded,
                      label: 'Player settings',
                      size: isFull ? 22 : 18,
                      onTap: () => _showSettingsSheet(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransportButton({
    required IconData icon,
    required double size,
    required VoidCallback? onPressed,
    bool enabled = true,
    FocusNode? focusNode,
    FocusNode? leftFocusNode,
    FocusNode? rightFocusNode,
    FocusNode? upFocusNode,
  }) {
    return _buildRemoteIconControl(
      icon: icon,
      label: switch (icon) {
        Icons.replay_10_rounded => 'Rewind 10 seconds',
        Icons.skip_previous_rounded => 'Previous episode',
        Icons.skip_next_rounded => 'Next episode',
        Icons.forward_10_rounded => 'Forward 10 seconds',
        _ => 'Playback control',
      },
      size: size,
      onTap: onPressed,
      enabled: enabled,
      focusNode: focusNode,
      directionalKeyHandlers: _playerDirections(
        left: leftFocusNode,
        right: rightFocusNode,
        up: upFocusNode,
      ),
    );
  }

  Widget _buildCustomControlsOverlay() {
    return Positioned.fill(
      child: RepaintBoundary(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _controlsVisible ? 1 : 0,
          child: ExcludeFocus(
            excluding: !_controlsVisible,
            child: ExcludeSemantics(
              excluding: !_controlsVisible,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Stack(
                  children: [_buildTopBar(), _buildBottomControls()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _playerFocusNode = FocusNode(debugLabel: 'Web video player');
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
    _playbackSpeed = _normalizedPlaybackSpeed(widget.initialPlaybackSpeed);
    _videoDisplayMode = widget.initialVideoDisplayMode;
    _subtitleLanguagePreference = _normalizedSubtitlePreference(
      widget.preferredSubtitleLanguage,
    );
    _selectedSubtitleTrackIndex = _subtitlePreferenceDisablesCaptions()
        ? -1
        : 0;
    _isWebViewSupported = Platform.isWindows || Platform.isAndroid;
    if (!_isWebViewSupported) {
      _isLoading = false;
      return;
    }

    _controller = DesktopWebViewController()
      ..setUserAgent(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      )
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        DesktopNavigationDelegate(
          onNavigationRequest: (DesktopNavigationRequest request) {
            final url = request.url;
            if (!_isSafeHttpUrl(url)) {
              return DesktopNavigationDecision.prevent;
            }
            // Always allow direct stream URLs through — embed players load
            // m3u8/mp4 segments from CDN domains that differ from the page host.
            if (_looksLikeSubtitleResourceUrl(url)) {
              final subtitleTrack = _subtitleTrackFromExtractorMessage(url);
              if (subtitleTrack != null) {
                widget.onSubtitleExtracted?.call(subtitleTrack);
              }
              return DesktopNavigationDecision.navigate;
            }
            if (url.contains('.m3u8') || url.contains('.mp4')) {
              widget.onVideoExtracted?.call(url);
              return DesktopNavigationDecision.navigate;
            }
            final initialHost = Uri.tryParse(widget.embedUrl)?.host ?? '';
            final reqUri = Uri.tryParse(url);
            if (reqUri != null &&
                reqUri.host.isNotEmpty &&
                initialHost.isNotEmpty) {
              // Derive eTLD+1 by taking the last two domain parts.
              String eTldPlusOne(String host) {
                final parts = host.split('.');
                return parts.length >= 2
                    ? parts.sublist(parts.length - 2).join('.')
                    : host;
              }

              final initialEtld = eTldPlusOne(initialHost);
              final reqEtld = eTldPlusOne(reqUri.host);
              // Allow same eTLD+1 (covers subdomains like player.megaplay.buzz)
              // and allow well-known video CDN / subtitle domains.
              final isRelated = reqEtld == initialEtld;
              const allowedDomains = {
                'akamaized.net',
                'cloudfront.net',
                'fastly.net',
                'cdn77.org',
                'bunnycdn.com',
                'jwplatform.com',
                'jwpcdn.com',
                'vimeo.com',
                'dailymotion.com',
                'streamtape.com',
                'filemoon.in',
                'vidstream.pro',
              };
              final isKnownCdn = allowedDomains.any(
                (d) => reqUri.host.endsWith(d) || reqUri.host == d,
              );
              if (request.isMainFrame && !isRelated && !isKnownCdn) {
                // A player page must never turn into Google, an ad landing
                // page, or an external browser-style page inside the app.
                return DesktopNavigationDecision.prevent;
              }
            }
            return DesktopNavigationDecision.navigate;
          },
          onProgress: (int progress) {
            _injectExtractor();
            if (progress > 60) {
              _injectVideoController();
              _injectStableWebControls();
            }
          },
          onPageStarted: (String url) {
            _pageLoadCompleted = false;
            _injectExtractor();
            _postPageLoadTimer?.cancel();
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasTimedOut = false;
              });
            }
          },
          onPageFinished: (String url) {
            _pageLoadCompleted = true;
            // Reveal provider UI after loading, while the media watchdog keeps
            // running until real media arrives (or this server fails).
            _postPageLoadTimer?.cancel();
            _postPageLoadTimer = Timer(const Duration(milliseconds: 600), () {
              if (mounted && _isLoading) {
                setState(() => _isLoading = false);
              }
            });
            _injectExtractor();
            _injectVideoController();
            _injectStableWebControls();
          },
          onWebResourceError: (DesktopWebResourceError error) {
            debugPrint('Web view resource error: ${error.description}');
            if (error.isForMainFrame == true && !_receivedVideoStatus) {
              _reportPlaybackFailure();
            }
          },
        ),
      );

    if (widget.onVideoExtracted != null) {
      _controller!.addJavaScriptChannel(
        'VideoExtractor',
        onMessageReceived: (DesktopJavaScriptMessage message) {
          final url = message.message;
          // Only forward http(s) URLs extracted from the page. The content of
          // third-party embed pages is untrusted and must not trigger the app
          // to load arbitrary (e.g. local/file) resources.
          if (url.isNotEmpty && _isSafeHttpUrl(url)) {
            widget.onVideoExtracted!(url);
          }
        },
      );
    }

    if (widget.onSubtitleExtracted != null) {
      _controller!.addJavaScriptChannel(
        'SubtitleExtractor',
        onMessageReceived: (DesktopJavaScriptMessage message) {
          final subtitleTrack = _subtitleTrackFromExtractorMessage(
            message.message,
          );
          if (subtitleTrack != null) {
            widget.onSubtitleExtracted!(subtitleTrack);
          }
        },
      );
    }

    _controller!.addJavaScriptChannel(
      'VideoStatus',
      onMessageReceived: (DesktopJavaScriptMessage message) {
        _postPageLoadTimer?.cancel();
        if (_isLoading && mounted) {
          setState(() => _isLoading = false);
        }
        try {
          final data = jsonDecode(message.message);
          if (data is! Map<String, dynamic>) return;
          // Empty video elements send status before any media is available.
          // Only cancel the watchdog once the provider has loaded real media.
          if ((data['duration'] as num? ?? 0) > 0 ||
              (data['currentTime'] as num? ?? 0) > 0) {
            _receivedVideoStatus = true;
            _loadTimeoutTimer?.cancel();
          }
          if (mounted) {
            final pos = Duration(
              milliseconds: ((data['currentTime'] as num? ?? 0) * 1000).toInt(),
            );
            final duration = Duration(
              milliseconds: ((data['duration'] as num? ?? 0) * 1000).toInt(),
            );
            final isPaused = data['paused'] as bool? ?? true;
            final isEnded = data['ended'] as bool? ?? false;
            final muted = data['muted'] as bool? ?? _isMuted;
            final speed =
                (data['playbackRate'] as num?)?.toDouble() ?? _playbackSpeed;
            final wasPlaying = _isPlaying;

            if (data['subtitles'] is List) {
              _detectedSubtitleTracks = List<Map<String, dynamic>>.from(
                (data['subtitles'] as List).whereType<Map>().map(
                  (e) => Map<String, dynamic>.from(e),
                ),
              );
              if (!_hasUserSelectedSubtitleTrack &&
                  _selectedSubtitleTrackIndex >= 0) {
                final preferenceChoice =
                    _subtitleLanguageChoiceForPreference(
                      _subtitleLanguagePreference,
                    ) ??
                    _preferredSubtitleLanguages.first;
                final preferredIndex = _detectedSubtitleTrackIndexForLanguage(
                  preferenceChoice,
                );
                if (preferredIndex != -1 &&
                    preferredIndex != _selectedSubtitleTrackIndex) {
                  _selectedSubtitleTrackIndex = preferredIndex;
                  _setSubtitleTrack(preferredIndex);
                } else if (preferredIndex == -1) {
                  _setSubtitleLanguagePreference(preferenceChoice.preference);
                }
              }
            }

            final newPlaying = !isPaused && !isEnded;
            final playingChanged = newPlaying != _isPlaying;
            final durationChanged = duration != _duration;
            final mutedChanged = muted != _isMuted;
            final speedChanged = speed != _playbackSpeed;
            final posSecChanged = pos.inSeconds != _currentPosition.inSeconds;

            final now = DateTime.now();
            final shouldUpdateUi =
                playingChanged ||
                durationChanged ||
                mutedChanged ||
                speedChanged ||
                (_controlsVisible &&
                    posSecChanged &&
                    now.difference(_lastPositionUiUpdate).inMilliseconds >=
                        250);

            if (_pendingSeekPosition != null) {
              _duration = duration;
              _isPlaying = newPlaying;
              _isMuted = muted;
              _playbackSpeed = speed;
              return;
            }

            _currentPosition = pos;
            _duration = duration;
            _isPlaying = newPlaying;
            _isMuted = muted;
            _playbackSpeed = speed;

            if (shouldUpdateUi) {
              _lastPositionUiUpdate = now;
              setState(() {});
            }
            if (!wasPlaying && _isPlaying && _controlsVisible) {
              _startHideControlsTimer();
            }

            if (pos > Duration.zero) {
              widget.onPositionChanged?.call(pos);
            }

            if (isEnded && widget.onVideoEnded != null && !_hasCalledOnEnded) {
              _hasCalledOnEnded = true;
              widget.onVideoEnded!();
            }
          }
        } catch (_) {}
      },
    );

    _controller!.addJavaScriptChannel(
      'StableFullscreen',
      onMessageReceived: (DesktopJavaScriptMessage message) {
        final action = message.message.toLowerCase().trim();
        if (action == 'enter') {
          if (!widget.isFullscreen) {
            _toggleFullscreen();
          }
        } else if (action == 'exit') {
          if (widget.isFullscreen) {
            _toggleFullscreen();
          }
        } else {
          _toggleFullscreen();
        }
      },
    );

    _loadUrl();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _playerFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    _postPageLoadTimer?.cancel();
    _hideControlsTimer?.cancel();
    _pendingSeekDebounce?.cancel();
    unawaited(_controller?.dispose());
    _controller = null;
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
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WebVideoPlayer oldWidget) {
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

    if (oldWidget.initialPlaybackSpeed != widget.initialPlaybackSpeed) {
      final nextSpeed = _normalizedPlaybackSpeed(widget.initialPlaybackSpeed);
      if (nextSpeed != _playbackSpeed) {
        setState(() => _playbackSpeed = nextSpeed);
        _runVideoCommand('video.playbackRate = $nextSpeed;');
      }
    }

    if (oldWidget.preferredSubtitleLanguage !=
        widget.preferredSubtitleLanguage) {
      _subtitleLanguagePreference = _normalizedSubtitlePreference(
        widget.preferredSubtitleLanguage,
      );
      final nextTrack = _subtitlePreferenceDisablesCaptions() ? -1 : 0;
      _hasUserSelectedSubtitleTrack = false;
      if (nextTrack != _selectedSubtitleTrackIndex) {
        setState(() => _selectedSubtitleTrackIndex = nextTrack);
      }
      _setSubtitleLanguagePreference(_subtitleLanguagePreference);
    }

    if (oldWidget.initialVideoDisplayMode != widget.initialVideoDisplayMode) {
      final nextMode = widget.initialVideoDisplayMode;
      if (nextMode != _videoDisplayMode) {
        setState(() => _videoDisplayMode = nextMode);
        _applyVideoDisplayMode(nextMode);
      }
    }

    if (_isWebViewSupported &&
        (oldWidget.embedUrl != widget.embedUrl ||
            oldWidget.isStableProvider != widget.isStableProvider)) {
      _loadTimeoutTimer?.cancel();
      _postPageLoadTimer?.cancel();
      _pendingSeekDebounce?.cancel();
      _pendingSeekPosition = null;
      _hasCalledOnEnded = false;
      _hasTimedOut = false;
      _hasReportedPlaybackFailure = false;
      _receivedVideoStatus = false;
      _hasUserSelectedSubtitleTrack = false;
      _subtitleLanguagePreference = _normalizedSubtitlePreference(
        widget.preferredSubtitleLanguage,
      );
      _isLoading = true;
      _showControls = true;
      _isPlaying = false;
      _currentPosition = Duration.zero;
      _duration = Duration.zero;

      if (_controller != null) {
        _loadUrl();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isWebViewSupported) {
      return const Center(
        child: Text(
          'This embedded server requires Windows WebView2. Choose a native streaming server.',
        ),
      );
    }

    final playerStack = Stack(
      children: [
        if (_controller != null)
          RepaintBoundary(child: DesktopWebView(controller: _controller!)),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_isLoading || _hasTimedOut,
            child: AnimatedOpacity(
              opacity: (_isLoading && !_hasTimedOut) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: RepaintBoundary(
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
                          _pageLoadCompleted
                              ? 'Starting player…'
                              : 'Loading stream…',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_hasTimedOut) _buildWebErrorOverlay(),
        // Removed: the old opaque Positioned.fill GestureDetector that blocked
        // ALL WebView touches has been replaced by the translucent one below.

        // Bug 1 fix: The gesture interceptor must NOT be opaque when the custom
        // controls are hidden — otherwise the WebView never receives touch
        // events and the embedded player can't be interacted with.
        //
        // Strategy:
        //  • When controls are VISIBLE   → the controls overlay handles buttons;
        //    the WebView below receives all other touches (transparent pass-through).
        //  • When controls are HIDDEN    → a translucent tap-target sits over the
        //    player so a single tap brings the controls back.
        //  Double-tap seek gestures work in both states via the GestureDetector
        //  on the controls overlay itself (rendered last = highest priority).
        if (_usesCustomControls && !_controlsVisible)
          Positioned.fill(
            child: GestureDetector(
              // transparent — lets pointer events through to the WebView
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControlsVisibility,
              child: const SizedBox.expand(),
            ),
          ),
        if (!_usesCustomControls && widget.isFullscreen)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  tooltip: 'Exit fullscreen',
                  icon: const Icon(Icons.fullscreen_exit_rounded),
                  onPressed: _toggleFullscreen,
                ),
              ),
            ),
          ),
        // The custom controls overlay renders on top but only intercepts touches
        // when visible (IgnorePointer wraps it when hidden).
        if (_usesCustomControls && !_isLoading && !_hasTimedOut)
          _buildCustomControlsOverlay(),
      ],
    );
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
      child: _usesCustomControls
          ? MouseRegion(
              cursor: (_showControls || !_isPlaying)
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              onHover: (_) => _interactWithControls(),
              child: playerStack,
            )
          : playerStack,
    );

    if (widget.isFullscreen) {
      return SizedBox.expand(
        child: ColoredBox(color: Colors.black, child: playerWidget),
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
