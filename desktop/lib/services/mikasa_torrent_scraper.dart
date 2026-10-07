import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'levi_torrent_scraper.dart';

class MikasaTorrentScraper {
  final http.Client? client;
  MikasaTorrentScraper({this.client});

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

    // Shana searches series titles; episode numbers are a separate column.
    final queries = titles
        .take(3)
        .map(LeviTorrentScraper.sanitizeQueryTitle)
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList();

    Future<void> fetchQuery(String query) async {
      try {
        final uri = Uri.parse(
          'https://www.shanaproject.com/search/?title=${Uri.encodeQueryComponent(query)}',
        );
        const headers = {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml',
        };
        final response =
            await (client?.get(uri, headers: headers) ??
                    http.get(uri, headers: headers))
                .timeout(const Duration(seconds: 7));
        if (response.statusCode == 200) {
          final document = html_parser.parse(response.body);
          final blocks = document.querySelectorAll('.release_block');
          // Older fixtures/site layouts do not have the outer release block.
          final rows = blocks.isNotEmpty
              ? blocks
              : document.querySelectorAll('.release_title');
          for (final row in rows) {
            final titleNode =
                row.querySelector('.release_title a[href*="/series/"]') ??
                row.querySelector('a[href*="/series/"]');
            final seriesTitle = titleNode?.text.trim() ?? '';
            final episodeText = row
                .querySelector('.release_episode')
                ?.text
                .trim();
            final profile =
                row.querySelector('.release_profile')?.text.trim() ?? '';
            final sizeStr =
                row.querySelector('.release_size')?.text.trim() ?? '';
            final downloadPath =
                row
                    .querySelector('a[href^="/download/"]')
                    ?.attributes['href'] ??
                '';
            if (seriesTitle.isEmpty || downloadPath.isEmpty) continue;
            final rawTitle =
                episodeText != null && int.tryParse(episodeText) != null
                ? '$seriesTitle - ${episodeText.padLeft(2, '0')}'
                : seriesTitle;
            final fullTitle = profile.isNotEmpty
                ? '$rawTitle [$profile]'
                : rawTitle;
            final downloadUrl = Uri.https(
              'www.shanaproject.com',
            ).resolve(downloadPath).toString();
            if (Uri.parse(downloadUrl).host != 'www.shanaproject.com') continue;

            final qualityMatch = RegExp(
              r'\b(2160|1080|720|480)p\b',
              caseSensitive: false,
            ).firstMatch(fullTitle);
            final resolution = int.tryParse(qualityMatch?[1] ?? '') ?? 0;

            final searchResult = TorrentSearchResult(
              title: fullTitle,
              magnetUrl: '',
              torrentUrl: downloadUrl,
              seeders:
                  -1, // Shana does not report a seeder count; do not fabricate one.
              leechers: 0,
              size: sizeStr,
              resolution: resolution,
            );

            if (LeviTorrentScraper.matchesEpisode(
                  fullTitle,
                  titles,
                  episodeNumber,
                ) &&
                LeviTorrentScraper.matchesLanguage(fullTitle, language)) {
              found[searchResult.torrentUrl] = searchResult;
            }
          }
        }
      } catch (_) {}
    }

    await Future.wait(queries.take(2).map(fetchQuery));
    if (found.isEmpty && queries.length > 2) {
      await fetchQuery(queries[2]);
    }

    final results = found.values.toList();
    results.sort((a, b) {
      final aQuality = a.resolution > 1080 ? 0 : a.resolution;
      final bQuality = b.resolution > 1080 ? 0 : b.resolution;
      return bQuality.compareTo(aQuality);
    });
    return results;
  }
}
