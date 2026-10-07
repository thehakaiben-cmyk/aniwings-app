import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class TorrentSearchResult {
  final String title;
  final String magnetUrl;
  final String torrentUrl;
  final int seeders;
  final int leechers;
  final String size;
  final int resolution;

  const TorrentSearchResult({
    required this.title,
    required this.magnetUrl,
    required this.torrentUrl,
    required this.seeders,
    required this.leechers,
    required this.size,
    this.resolution = 0,
  });
}

/// Only unambiguous single-episode releases are eligible. Catalog episode
/// numbers are never treated as absolute offsets or torrent IDs.
class LeviTorrentScraper {
  final http.Client? client;
  LeviTorrentScraper({this.client});

  Future<List<TorrentSearchResult>> searchAnimeTorrents({
    required String title,
    required int episodeNumber,
    required String language,
    List<String> alternativeTitles = const [],
    bool isDonghua = false,
  }) async {
    if (episodeNumber < 1 ||
        !{'sub', 'dub', 'any'}.contains(language.toLowerCase())) {
      return const [];
    }
    final titles = {title.trim(), ...alternativeTitles.map((s) => s.trim())}
      ..removeWhere((s) => s.isEmpty);
    final found = <String, TorrentSearchResult>{};
    // Scope the feed to this episode, then validate its complete title below.
    final padEp = episodeNumber.toString().padLeft(2, '0');
    final pad3 = episodeNumber.toString().padLeft(3, '0');
    final pad4 = episodeNumber.toString().padLeft(4, '0');
    final epStr = episodeNumber.toString();
    final queries = <String>[];
    // First pass: standard 2-digit queries for all aliases
    for (final alias in titles.take(3)) {
      final sanitized = sanitizeQueryTitle(alias);
      if (sanitized.isNotEmpty && !queries.contains('$sanitized $padEp')) {
        queries.add('$sanitized $padEp');
      }
      final noSub = sanitizeQueryTitle(alias.split(RegExp(r'[:\-]')).first);
      if (noSub.isNotEmpty &&
          noSub != sanitized &&
          !queries.contains('$noSub $padEp')) {
        queries.add('$noSub $padEp');
      }
    }

    // Second pass: 3-digit and alternate format queries for older and long-running series
    for (final alias in titles.take(3)) {
      final sanitized = sanitizeQueryTitle(alias);
      if (sanitized.isEmpty) continue;
      if (pad3 != padEp && !queries.contains('$sanitized $pad3')) {
        queries.add('$sanitized $pad3');
      }
      if (!queries.contains('$sanitized $epStr')) {
        queries.add('$sanitized $epStr');
      }
      if (!queries.contains('$sanitized EP$pad4')) {
        queries.add('$sanitized EP$pad4');
      }
      final noSub = sanitizeQueryTitle(alias.split(RegExp(r'[:\-]')).first);
      if (noSub.isNotEmpty && noSub != sanitized) {
        if (pad3 != padEp && !queries.contains('$noSub $pad3')) {
          queries.add('$noSub $pad3');
        }
      }
    }

    if (client == null) {
      final seasonRegex = RegExp(
        r'\b(?:season\s*(\d+)|(\d+)(?:st|nd|rd|th)\s+season)\b',
        caseSensitive: false,
      );
      for (final alias in titles.take(4)) {
        final sanitized = sanitizeQueryTitle(alias);
        final match = seasonRegex.firstMatch(sanitized);
        if (match != null) {
          final seasonNum = match.group(1) ?? match.group(2)!;
          final padSeason = seasonNum.padLeft(2, '0');
          final sShort = sanitized
              .replaceFirst(seasonRegex, 'S$seasonNum')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (sShort.isNotEmpty && !queries.contains('$sShort $padEp')) {
            queries.add('$sShort $padEp');
          }
          final sEpTag = sanitized
              .replaceFirst(seasonRegex, 'S${padSeason}E$padEp')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (sEpTag.isNotEmpty && !queries.contains(sEpTag)) {
            queries.add(sEpTag);
          }
          final stripped = sanitized
              .replaceFirst(seasonRegex, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (stripped.length >= 3 && !queries.contains('$stripped $padEp')) {
            queries.add('$stripped $padEp');
          }
        }
      }
    }

    Future<void> fetchQuery(String query) async {
      final hosts = client == null
          ? const ['nyaa.si', 'nyaa.land']
          : const ['nyaa.si'];
      for (final host in hosts) {
        final uri = Uri.https(host, '/', {
          'page': 'rss',
          'q': query,
          // Donghua fansubs are rarely tagged as English-translated (1_2).
          // Use the broader all-anime category (1_0) for Donghua titles.
          'c': isDonghua ? '1_0' : '1_2',
          'f': '0',
        });
        try {
          const headers = {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          };
          final response =
              await (client?.get(uri, headers: headers) ??
                      http.get(uri, headers: headers))
                  .timeout(const Duration(seconds: 6));
          if (response.statusCode == 200) {
            final normalizedBody = host == 'nyaa.si'
                ? response.body
                : response.body.replaceAll(
                    'https://$host/download/',
                    'https://nyaa.si/download/',
                  );
            for (final result in parseFeed(normalizedBody)) {
              if (result.seeders > 0 &&
                  matchesEpisode(result.title, titles, episodeNumber) &&
                  matchesLanguage(result.title, language)) {
                found[result.torrentUrl] = result;
              }
            }
            break;
          }
        } catch (_) {}
      }
    }

    await Future.wait(queries.take(2).map(fetchQuery));
    if (found.isEmpty && queries.length > 2) {
      await Future.wait(queries.skip(2).take(4).map(fetchQuery));
    }
    if (found.isEmpty && queries.length > 6) {
      await Future.wait(queries.skip(6).take(4).map(fetchQuery));
    }
    final results = found.values.toList();
    results.sort((a, b) {
      // A lone peer on a large release is a poor default for immediate playback.
      final availability = (b.seeders >= 5 ? 1 : 0).compareTo(
        a.seeders >= 5 ? 1 : 0,
      );
      if (availability != 0) return availability;
      if (a.seeders < 5 && b.seeders < 5) {
        final peers = b.seeders.compareTo(a.seeders);
        if (peers != 0) return peers;
      }
      final aQuality = a.resolution > 1080 ? 0 : a.resolution;
      final bQuality = b.resolution > 1080 ? 0 : b.resolution;
      final quality = bQuality.compareTo(aQuality);
      return quality != 0 ? quality : b.seeders.compareTo(a.seeders);
    });
    return results;
  }

  static String sanitizeQueryTitle(String value) {
    return value
        .replaceAll(RegExp(r'''[()[\]{}:;!?"'`~^]'''), ' ')
        .replaceAll(RegExp(r'\s+-\s+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Maps standalone Roman numerals (II–X) to 'season N' sequel indicators.
  /// Only matches word-boundary Roman numerals that are preceded by a space or
  /// start of string, and followed by a space, colon, dash, or end of string.
  static String _romanToSeason(String value) {
    const mapping = <String, String>{
      'X': '10',
      'IX': '9',
      'VIII': '8',
      'VII': '7',
      'VI': '6',
      'V': '5',
      'IV': '4',
      'III': '3',
      'II': '2',
    };
    return value.replaceAllMapped(
      RegExp(
        r'(?<=\s|^)(X|IX|VIII|VII|VI|V|IV|III|II)(?=\s|:|$|-)',
        caseSensitive: false,
      ),
      (m) => 'season ${mapping[m[1]!.toUpperCase()]}',
    );
  }

  static String normalizeTitle(String value) {
    return _romanToSeason(value)
        .toLowerCase()
        .replaceAllMapped(
          RegExp(
            r'\b(?:season\s*(\d+)|(\d+)(?:st|nd|rd|th)\s+season|s(\d+))\b',
          ),
          (m) => ' season ${int.parse(m[1] ?? m[2] ?? m[3]!)} ',
        )
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool matchesEpisode(
    String release,
    Iterable<String> titles,
    int episode,
  ) {
    if (RegExp(
      r'\b(batch|complete|ova|oad|special|movie|pv|trailer|soundtrack|ost)\b',
      caseSensitive: false,
    ).hasMatch(release)) {
      return false;
    }
    if (RegExp(
      r'\[[^\]]*\b(?:season\s*\d+|s\d{1,2}|part\s*\d+|cour\s*\d+)[^\]]*\]',
      caseSensitive: false,
    ).hasMatch(release)) {
      return false;
    }
    final name = release
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[_.]+'), ' ')
        .trim();
    // Prefer explicit episode markers so numbers in titles/seasons do not
    // become the episode number (e.g. "86" or "Season 2 - 01").
    RegExpMatch? match;
    for (final separator in [
      r'\s-\s*|\s+S(\d{1,2})E|\s+(?:EP?|Episode)\s*',
      r'\s+()',
    ]) {
      match = RegExp(
        r'^(.*?)'
        '(?:$separator)'
        r'(\d{1,4})(?:v\d+)?(?=\s|\(|\[|\.(?:mkv|mp4)$|$)',
        caseSensitive: false,
      ).firstMatch(name);
      if (match != null) break;
    }
    if (match == null || int.tryParse(match[3]!) != episode) return false;
    final remainder = name.substring(match.end).trim();
    if (RegExp(r'^[-~–&+]|^\d').hasMatch(remainder)) return false;
    var series = normalizeTitle(match[1]!);
    final season = int.tryParse(match[2] ?? '');
    if (season != null) series = '$series season $season';
    String firstSeason(String s) => s.replaceFirst(RegExp(r' season 1$'), '');
    return titles.any(
      (title) => firstSeason(normalizeTitle(title)) == firstSeason(series),
    );
  }

  static bool matchesLanguage(String title, String language) {
    if (language.toLowerCase() == 'any') return true;
    final dub = RegExp(
      r'\b(?:english[ ._-]*dub(?:bed)?|dub(?:bed)?)\b',
      caseSensitive: false,
    ).hasMatch(title);
    final multi = RegExp(
      r'\b(?:dual|multi)[ ._-]*audio\b',
      caseSensitive: false,
    ).hasMatch(title);
    if (language.toLowerCase() == 'dub') return dub || multi;
    return !dub || multi;
  }

  static List<TorrentSearchResult> parseFeed(String source) {
    try {
      final doc = XmlDocument.parse(source);
      final results = <TorrentSearchResult>[];
      for (final item in doc.findAllElements('item')) {
        String field(String name) =>
            item.childElements
                .where((e) => e.name.local == name)
                .map((e) => e.innerText.trim())
                .firstOrNull ??
            '';
        final title = field('title');
        final link = Uri.tryParse(field('link'));
        if (title.isEmpty ||
            link == null ||
            link.scheme != 'https' ||
            link.host != 'nyaa.si' ||
            !RegExp(r'^/download/\d+\.torrent$').hasMatch(link.path)) {
          continue;
        }
        final hash = field('infoHash');
        final magnet = RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(hash)
            ? 'magnet:?xt=urn:btih:${hash.toLowerCase()}'
            : '';
        final quality = RegExp(
          r'\b(2160|1080|720|480)p\b',
          caseSensitive: false,
        ).firstMatch(title);
        results.add(
          TorrentSearchResult(
            title: title,
            magnetUrl: magnet,
            torrentUrl: link.toString(),
            seeders: int.tryParse(field('seeders')) ?? 0,
            leechers: int.tryParse(field('leechers')) ?? 0,
            size: field('size'),
            resolution: int.tryParse(quality?[1] ?? '') ?? 0,
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }
}
