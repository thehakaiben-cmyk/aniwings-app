import 'dart:io';

/// Keeps the extension's zero-based batch index separate from libtorrent's magnet URI.
class TorrentRequest {
  final String url;
  final int? fileIndex;
  final bool isMagnet;

  const TorrentRequest({
    required this.url,
    this.fileIndex,
    required this.isMagnet,
  });

  static TorrentRequest parse(String value) {
    if (value.toLowerCase().startsWith('magnet:?')) {
      final query = value.substring(value.indexOf('?') + 1);
      final fields = query.split('&');
      final params = <String, String>{};
      int? fileIndex;

      for (final field in fields) {
        final split = field.indexOf('=');
        if (split > 0) {
          final k = Uri.decodeQueryComponent(field.substring(0, split));
          final v = Uri.decodeQueryComponent(field.substring(split + 1));
          if (k == 'index') {
            fileIndex = int.tryParse(v);
          } else {
            params[k] = v;
          }
        }
      }

      final xt = params['xt'] ?? '';
      final hashRegex = RegExp(
        r'^urn:btih:([a-f0-9]{40}|[a-z2-7]{32})$',
        caseSensitive: false,
      );
      if (!hashRegex.hasMatch(xt)) {
        throw ArgumentError('Invalid torrent info hash');
      }

      final filteredMagnet =
          'magnet:?${fields.where((f) {
            final k = Uri.decodeQueryComponent(f.split('=').first);
            return k != 'index';
          }).join('&')}';

      return TorrentRequest(
        url: filteredMagnet,
        fileIndex: fileIndex,
        isMagnet: true,
      );
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw ArgumentError('Invalid torrent metadata URL');
    }
    return TorrentRequest(url: value, fileIndex: null, isMagnet: false);
  }
}

/// Bounded verified-piece prebuffer and read-ahead, independent of HTTP chunk size.
class TorrentBufferPlan {
  static const int startupBytes = 4 * 1024 * 1024; // 4MB
  static const int readAheadBytes = 16 * 1024 * 1024; // 16MB

  static ({int start, int end}) window({
    required int offset,
    required int size,
    required int pieceLength,
    required int position,
    required int bytes,
  }) {
    if (offset < 0 ||
        size <= 0 ||
        pieceLength <= 0 ||
        position < 0 ||
        bytes <= 0) {
      return (start: 0, end: 0);
    }
    final start = ((offset + position) ~/ pieceLength);
    final endPos = (position + bytes - 1) < (size - 1)
        ? (position + bytes - 1)
        : (size - 1);
    final end = ((offset + endPos) ~/ pieceLength);
    return (start: start, end: end);
  }
}

/// Pure validation shared by the desktop engine and regression tests.
class LeviStreamRules {
  static int? explicitEpisode(String path) {
    final fileName = File(path).uri.pathSegments.lastOrNull ?? path;
    final match = RegExp(
      r'(?:\s-\s*|S\d{1,2}E|\b(?:Episode|Ep?)\s*)(\d{1,4})(?:v\d+)?(?=[ ._(\[]|$)',
      caseSensitive: false,
    ).firstMatch(fileName);
    return match != null ? int.tryParse(match.group(1) ?? '') : null;
  }

  static int selectAudio(List<String?> languages, String language) {
    final codes = language == 'en'
        ? {'en', 'eng', 'english'}
        : {'ja', 'jpn', 'japanese', 'jp'};
    final index = languages.indexWhere(
      (lang) => codes.contains(lang?.toLowerCase().split('-').firstOrNull),
    );
    if (index >= 0) return index;
    if (languages.length == 1 &&
        (languages.first == null ||
            languages.first!.isEmpty ||
            languages.first == 'und')) {
      return 0;
    }
    return -1;
  }

  static int selectVideo({
    required List<({String path, int size})> files,
    int? episodeNumber,
    int? fileIndex,
  }) {
    final videoIndices = <int>[];
    for (int i = 0; i < files.length; i++) {
      final p = files[i].path.toLowerCase();
      final isVideo =
          (p.endsWith('.mkv') || p.endsWith('.mp4') || p.endsWith('.webm'));
      final isSample = RegExp(r'(^|[ /_.-])sample([ /_.-]|$)').hasMatch(p);
      if (files[i].size > 0 && isVideo && !isSample) {
        videoIndices.add(i);
      }
    }

    if (fileIndex != null) {
      if (!videoIndices.contains(fileIndex)) {
        throw ArgumentError('Mapped torrent file is not a playable video');
      }
      return fileIndex;
    }

    if (videoIndices.length > 1 && episodeNumber != null) {
      final matches = videoIndices
          .where((i) => explicitEpisode(files[i].path) == episodeNumber)
          .toList();
      if (matches.length == 1) return matches.first;
    }

    if (videoIndices.isEmpty) {
      throw ArgumentError('No playable video found in torrent');
    }
    return videoIndices.first;
  }

  static ({int start, int end})? parseRange(String? header, int size) {
    if (size <= 0) return null;
    if (header == null) return (start: 0, end: size - 1);
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;
    final first = match.group(1) ?? '';
    final last = match.group(2) ?? '';
    if (first.isEmpty) {
      final suffix = int.tryParse(last);
      if (suffix == null || suffix <= 0) return null;
      final start = (size - suffix) > 0 ? (size - suffix) : 0;
      return (start: start, end: size - 1);
    }
    final start = int.tryParse(first);
    if (start == null || start >= size) return null;
    final end = last.isEmpty ? (size - 1) : (int.tryParse(last) ?? (size - 1));
    if (end < start) return null;
    final clampedEnd = end < (size - 1) ? end : (size - 1);
    return (start: start, end: clampedEnd);
  }
}
