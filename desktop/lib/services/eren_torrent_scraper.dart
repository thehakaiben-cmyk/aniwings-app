import 'dart:convert';
import 'package:http/http.dart' as http;
import 'levi_torrent_scraper.dart';

class ErenTorrentScraper {
  final http.Client? client;
  ErenTorrentScraper({this.client});

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

    final pad2 = episodeNumber.toString().padLeft(2, '0');
    final pad3 = episodeNumber.toString().padLeft(3, '0');
    final pad4 = episodeNumber.toString().padLeft(4, '0');
    final epStr = episodeNumber.toString();

    final queries = <String>[];
    for (final alias in titles.take(3)) {
      final sanitized = LeviTorrentScraper.sanitizeQueryTitle(alias);
      if (sanitized.isEmpty) continue;
      for (final ep in [pad3, pad2, epStr, 'EP$pad4', 'E$pad3', 'E$pad2']) {
        final q = '$sanitized $ep';
        if (!queries.contains(q)) queries.add(q);
      }
      final noSub = LeviTorrentScraper.sanitizeQueryTitle(
        alias.split(RegExp(r'[:\-]')).first,
      );
      if (noSub.isNotEmpty && noSub != sanitized) {
        for (final ep in [pad3, pad2, epStr]) {
          final q = '$noSub $ep';
          if (!queries.contains(q)) queries.add(q);
        }
      }
    }

    Future<void> fetchQuery(String query) async {
      try {
        final uri = Uri.parse(
          'https://nekobt.to/api/v1/torrents/search?query=${Uri.encodeQueryComponent(query)}',
        );
        const headers = {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        };
        final response =
            await (client?.get(uri, headers: headers) ??
                    http.get(uri, headers: headers))
                .timeout(const Duration(seconds: 7));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final results = data['data']?['results'] as List? ?? const [];
          for (final item in results) {
            if (item is! Map) continue;
            if (item['deleted'] == true ||
                item['hidden'] == true ||
                item['waiting_approve'] == true) {
              continue;
            }
            final audio =
                (item['audio_lang'] is List
                        ? (item['audio_lang'] as List).whereType<String>()
                        : (item['audio_lang'] is String
                              ? (item['audio_lang'] as String).split(
                                  RegExp(r'[,;+\s]+'),
                                )
                              : <String>[]))
                    .map(
                      (value) => switch (value.toLowerCase().trim()) {
                        'eng' => 'en',
                        'jpn' => 'ja',
                        'zho' || 'chi' => 'zh',
                        final language => language.split('-').first,
                      },
                    )
                    .toSet();
            final rawTitle = (item['title'] as String? ?? '').trim();
            final tTitle = audio.length > 1
                ? '$rawTitle [Multi Audio]'
                : rawTitle;
            final id = item['id']?.toString() ?? '';
            final magnet = (item['magnet'] as String? ?? '').trim();
            final seeders = int.tryParse('${item['seeders']}') ?? 0;
            final leechers = int.tryParse('${item['leechers']}') ?? 0;
            final fileSize = int.tryParse('${item['filesize']}') ?? 0;
            final downloadUrl = id.isNotEmpty
                ? 'https://nekobt.to/api/v1/torrents/$id/download?public=true'
                : magnet;

            if (tTitle.isEmpty || (magnet.isEmpty && downloadUrl.isEmpty)) {
              continue;
            }

            final qualityMatch = RegExp(
              r'\b(2160|1080|720|480)p\b',
              caseSensitive: false,
            ).firstMatch(tTitle);
            final resolution = int.tryParse(qualityMatch?[1] ?? '') ?? 0;

            final sizeStr = fileSize > 0
                ? (fileSize > 1024 * 1024 * 1024
                      ? '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
                      : '${(fileSize / (1024 * 1024)).toStringAsFixed(0)} MB')
                : '';

            final searchResult = TorrentSearchResult(
              title: tTitle,
              magnetUrl: magnet,
              torrentUrl: downloadUrl,
              seeders: seeders,
              leechers: leechers,
              size: sizeStr,
              resolution: resolution,
            );

            if (LeviTorrentScraper.matchesEpisode(
                  tTitle,
                  titles,
                  episodeNumber,
                ) &&
                (language == 'any' ||
                    (audio.isNotEmpty
                        ? audio.contains(
                            language == 'dub'
                                ? 'en'
                                : isDonghua
                                ? 'zh'
                                : 'ja',
                          )
                        : LeviTorrentScraper.matchesLanguage(
                            tTitle,
                            language,
                          )))) {
              found[searchResult.torrentUrl] = searchResult;
            }
          }
        }
      } catch (_) {}
    }

    await Future.wait(queries.take(2).map(fetchQuery));
    if (found.isEmpty && queries.length > 2) {
      await Future.wait(queries.skip(2).take(4).map(fetchQuery));
    }

    final results = found.values.toList();
    results.sort((a, b) {
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
}
