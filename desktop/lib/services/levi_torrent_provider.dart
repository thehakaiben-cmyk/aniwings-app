import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/video_provider.dart';
import '../models/anime.dart';
import 'levi_torrent_scraper.dart';
import 'eren_torrent_scraper.dart';
import 'mikasa_torrent_scraper.dart';

/// Resolves catalog identity before contacting the torrent index. MAL and
/// AniList IDs occupy separate namespaces, even when their numbers coincide.
class LeviTorrentProvider {
  final http.Client? client;
  final Future<String?> Function(String) prepareStream;
  final Future<void> Function(String) stopStream;
  LeviTorrentProvider({
    this.client,
    required this.prepareStream,
    required this.stopStream,
  });

  Future<VideoProviderSource?> resolve({
    required String idType,
    required String id,
    required int episodeNumber,
    required String language,
    Anime? anime,
    bool isDonghua = false,
    bool Function()? isCancelled,
    String serverName = 'Levi',
    bool deferStreaming = false,
  }) async {
    if (!{'mal', 'ani'}.contains(idType) ||
        (int.tryParse(id) ?? 0) < 1 ||
        episodeNumber < 1 ||
        !{'sub', 'dub', 'any'}.contains(language.toLowerCase())) {
      return null;
    }
    try {
      final media = await _metadata(idType, id, anime);
      if (media == null || isCancelled?.call() == true) return null;
      final count = media['episodes'];
      if (count is int && count > 0 && episodeNumber > count) return null;
      final titleData = media['title'];
      if (titleData is! Map) return null;
      final titles = ['romaji', 'english', 'native']
          .map((key) => titleData[key])
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toSet()
          .toList();
      titles.addAll(
        (media['synonyms'] as List? ?? const []).whereType<String>().where(
          (title) => title.trim().isNotEmpty && !titles.contains(title),
        ),
      );
      final qualifierPattern = RegExp(
        r'\b(?:season \d+|part \d+|cour \d+|(?:19|20)\d{2})\b',
      );
      final yearPattern = RegExp(r'\b(?:19|20)\d{2}\b');
      final canonicalNormalized = ['romaji', 'english']
          .map((key) => titleData[key])
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .map(LeviTorrentScraper.normalizeTitle)
          .toList();
      final baseTitles = <String>[];
      for (final title in titles) {
        final split = title.split(RegExp(r'[:\-]')).first.trim();
        if (split.length >= 3 &&
            !titles.contains(split) &&
            !baseTitles.contains(split)) {
          baseTitles.add(split);
          final normFull = LeviTorrentScraper.normalizeTitle(title);
          final normSplit = LeviTorrentScraper.normalizeTitle(split);
          final missingQuals = qualifierPattern
              .allMatches(normFull)
              .map((m) => m[0]!)
              .where((q) => !normSplit.contains(q))
              .toList();
          if (missingQuals.isNotEmpty) {
            final qualifiedSplit = '$split ${missingQuals.join(' ')}';
            if (!titles.contains(qualifiedSplit) &&
                !baseTitles.contains(qualifiedSplit)) {
              baseTitles.add(qualifiedSplit);
            }
          }
        }
      }
      titles.addAll(baseTitles);
      if (titles.isEmpty) return null;
      // Unqualified translated aliases can refer to a different season/remake.
      // Cached aliases can put English before romaji. Use the most specific
      // alias so an unqualified translation cannot select another season.
      // Normalize all titles *first* so Roman numerals like "III" are already
      // converted to "season 3" before the qualifier check runs.
      final normalizedMap = {
        for (final title in titles)
          title: LeviTorrentScraper.normalizeTitle(title),
      };
      final qualifiers = normalizedMap.values
          .map(
            (normalized) => qualifierPattern
                .allMatches(normalized)
                .map((m) => m[0]!)
                .where((q) {
                  if (yearPattern.hasMatch(q)) {
                    return canonicalNormalized.any((c) => c.contains(q));
                  }
                  return true;
                })
                .toList(),
          )
          .fold<List<String>>([], (a, b) => a.length >= b.length ? a : b);
      if (qualifiers.isNotEmpty) {
        final filtered = titles.where((title) {
          final normalized = normalizedMap[title]!;
          return qualifiers.every(
            (qualifier) => normalized.contains(qualifier),
          );
        }).toList();
        if (filtered.isNotEmpty) {
          titles.removeWhere((title) => !filtered.contains(title));
        }
      }

      final List<TorrentSearchResult> releases;
      final normalizedServer = serverName.toLowerCase().trim();
      if (normalizedServer == 'eren') {
        releases = await ErenTorrentScraper(client: client).searchAnimeTorrents(
          title: titles.first,
          alternativeTitles: titles.skip(1).toList(),
          episodeNumber: episodeNumber,
          language: language,
          isDonghua: isDonghua,
        );
      } else if (normalizedServer == 'mikasa') {
        releases = await MikasaTorrentScraper(client: client)
            .searchAnimeTorrents(
              title: titles.first,
              alternativeTitles: titles.skip(1).toList(),
              episodeNumber: episodeNumber,
              language: language,
              isDonghua: isDonghua,
            );
      } else {
        releases = await LeviTorrentScraper(client: client).searchAnimeTorrents(
          title: titles.first,
          alternativeTitles: titles.skip(1).toList(),
          episodeNumber: episodeNumber,
          language: language,
          isDonghua: isDonghua,
        );
      }
      for (final release in releases.take(3)) {
        if (isCancelled?.call() == true) return null;
        if (deferStreaming) {
          return VideoProviderSource(
            name: serverName,
            description: '$serverName Torrent • ${release.seeders} seeders',
            languageType: language == 'any' ? 'SUB' : language.toUpperCase(),
            videoUrls: const [],
            speedStatus: 'Peer-dependent',
            streamFormat: 'torrent',
            sourcePlayerUrl: release.magnetUrl.isNotEmpty
                ? release.magnetUrl
                : release.torrentUrl,
          );
        }
        String? url;
        try {
          url = await prepareStream(release.torrentUrl);
        } catch (_) {
          // Metadata downloads can fail while the release's magnet still works.
        }
        if (url == null && release.magnetUrl.isNotEmpty) {
          try {
            url = await prepareStream(release.magnetUrl);
          } catch (_) {}
        }
        if (url == null) continue;
        if (isCancelled?.call() == true) {
          await stopStream(url);
          return null;
        }
        // Never return .torrent/magnet URLs as video URLs.
        final local = Uri.tryParse(url);
        if (local?.scheme != 'http' ||
            local?.host != '127.0.0.1' ||
            !local!.hasPort) {
          await stopStream(url);
          continue;
        }
        return VideoProviderSource(
          name: serverName,
          description:
              '$serverName Torrent • ${release.resolution > 0 ? '${release.resolution}p' : 'Original quality'} • ${release.seeders >= 0 ? '${release.seeders} seeders' : 'Peer availability unknown'}',
          languageType: language == 'any' ? 'SUB' : language.toUpperCase(),
          videoUrls: [url],
          speedStatus: 'Peer-dependent',
          streamFormat: 'torrent',
          sourcePlayerUrl: release.magnetUrl.isNotEmpty
              ? release.magnetUrl
              : release.torrentUrl,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<Map?> _metadata(String idType, String id, Anime? known) async {
    // Playback already has catalog metadata in normal navigation. Requiring a
    // second AniList request here made every torrent fail during its outages.
    final matches =
        known != null &&
        (idType == 'mal'
            ? known.malId == id ||
                  (known.malId == null &&
                      known.aniListId == null &&
                      known.id == id)
            : known.aniListId == id ||
                  (known.aniListId == null &&
                      known.malId == null &&
                      known.id == id));
    if (matches &&
        known.title.trim().isNotEmpty &&
        known.title != 'Unknown Title') {
      return {
        'episodes': known.totalEpisodes,
        'title': {
          'romaji': known.alternativeTitles.firstOrNull ?? known.title,
          'english': known.title,
        },
        'synonyms': known.alternativeTitles,
      };
    }
    final field = idType == 'mal' ? 'idMal' : 'id';
    try {
      final uri = Uri.https('graphql.anilist.co');
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final body = jsonEncode({
        'query':
            'query(\$id: Int!) { Media($field: \$id, type: ANIME) { id idMal episodes synonyms title { romaji english native } } }',
        'variables': {'id': int.parse(id)},
      });
      final response =
          await (client?.post(uri, headers: headers, body: body) ??
                  http.post(uri, headers: headers, body: body))
              .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final media = jsonDecode(response.body)['data']?['Media'];
        if (media is Map && media[field]?.toString() == id) return media;
      }
    } catch (_) {}
    // Only a MAL identifier may be sent to Jikan. Never guess an ID conversion.
    if (idType == 'mal') {
      try {
        final uri = Uri.https('api.jikan.moe', '/v4/anime/$id');
        final response = await (client?.get(uri) ?? http.get(uri)).timeout(
          const Duration(seconds: 5),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body)['data'];
          if (data is Map && data['mal_id']?.toString() == id) {
            return {
              'episodes': data['episodes'],
              'title': {
                'romaji': data['title'],
                'english': data['title_english'],
                'native': data['title_japanese'],
              },
              'synonyms': data['title_synonyms'],
            };
          }
        }
      } catch (_) {}
    }
    if (known != null &&
        known.title.trim().isNotEmpty &&
        known.title != 'Unknown Title' &&
        known.title != id) {
      return {
        'episodes': known.totalEpisodes,
        'title': {
          'romaji': known.alternativeTitles.firstOrNull ?? known.title,
          'english': known.title,
        },
        'synonyms': known.alternativeTitles,
      };
    }
    return null;
  }
}
