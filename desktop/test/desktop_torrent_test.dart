import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aniwings/services/torrent_stream_rules.dart';
import 'package:aniwings/services/desktop_torrent_engine.dart';
import 'package:aniwings/services/levi_torrent_scraper.dart';
import 'package:aniwings/services/eren_torrent_scraper.dart';
import 'package:aniwings/services/mikasa_torrent_scraper.dart';
import 'package:aniwings/services/levi_torrent_provider.dart';
import 'package:aniwings/services/levi_native_proxy_stub.dart'
    if (dart.library.io) 'package:aniwings/services/levi_native_proxy_io.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('TorrentStreamRules Tests', () {
    test('TorrentRequest parses valid magnet URLs and extracts index', () {
      const magnet =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Anime+Title&index=3&tr=http%3A%2F%2Ftracker.com';
      final req = TorrentRequest.parse(magnet);
      expect(req.isMagnet, isTrue);
      expect(req.fileIndex, equals(3));
      expect(
        req.url,
        contains('xt=urn:btih:0123456789abcdef0123456789abcdef01234567'),
      );
      expect(req.url, isNot(contains('index=3')));
    });

    test('TorrentRequest parses valid .torrent HTTPS URLs', () {
      const torrentUrl = 'https://nyaa.si/download/1234567.torrent';
      final req = TorrentRequest.parse(torrentUrl);
      expect(req.isMagnet, isFalse);
      expect(req.fileIndex, isNull);
      expect(req.url, equals(torrentUrl));
    });

    test('TorrentRequest rejects invalid URLs and malformed hashes', () {
      expect(
        () => TorrentRequest.parse('ftp://invalid.com'),
        throwsArgumentError,
      );
      expect(
        () => TorrentRequest.parse('magnet:?xt=urn:btih:invalid_hash'),
        throwsArgumentError,
      );
    });

    test('TorrentBufferPlan computes correct piece window', () {
      final window = TorrentBufferPlan.window(
        offset: 0,
        size: 50 * 1024 * 1024,
        pieceLength: 2 * 1024 * 1024,
        position: 0,
        bytes: TorrentBufferPlan.startupBytes,
      );
      expect(window.start, equals(0));
      expect(window.end, equals(1)); // 0..1 covers 4MB with 2MB piece size
    });

    test('LeviStreamRules matches explicit episode titles', () {
      expect(
        LeviStreamRules.explicitEpisode('[Sub] Frieren - 04 [1080p].mkv'),
        equals(4),
      );
      expect(
        LeviStreamRules.explicitEpisode('Attack on Titan S04E12 [1080p].mp4'),
        equals(12),
      );
      expect(
        LeviStreamRules.explicitEpisode('One Piece Episode 1000.mkv'),
        equals(1000),
      );
      expect(
        LeviStreamRules.explicitEpisode('Movie Title Special.mkv'),
        isNull,
      );
    });

    test('LeviStreamRules selects video and filters samples', () {
      final files = [
        (path: 'Anime/Sample.mkv', size: 10 * 1024 * 1024),
        (path: 'Anime/Track.nfo', size: 1024),
        (path: 'Anime/Episode 01.mkv', size: 500 * 1024 * 1024),
        (path: 'Anime/Episode 02.mkv', size: 500 * 1024 * 1024),
      ];

      final ep1 = LeviStreamRules.selectVideo(files: files, episodeNumber: 1);
      expect(ep1, equals(2));

      final ep2 = LeviStreamRules.selectVideo(files: files, episodeNumber: 2);
      expect(ep2, equals(3));
    });

    test('LeviStreamRules parses HTTP byte ranges', () {
      final fullRange = LeviStreamRules.parseRange(null, 1000);
      expect(fullRange, equals((start: 0, end: 999)));

      final partRange = LeviStreamRules.parseRange('bytes=100-499', 1000);
      expect(partRange, equals((start: 100, end: 499)));

      final suffixRange = LeviStreamRules.parseRange('bytes=-200', 1000);
      expect(suffixRange, equals((start: 800, end: 999)));

      final openRange = LeviStreamRules.parseRange('bytes=500-', 1000);
      expect(openRange, equals((start: 500, end: 999)));
    });
  });

  group('DesktopTorrentEngine Lifecycle & HTTP 206 Loopback Tests', () {
    test('supportsLeviNativeStreaming is enabled on Windows and Linux', () {
      expect(
        supportsLeviNativeStreaming,
        equals(Platform.isWindows || Platform.isLinux),
      );
    });

    test('empty and malformed sources never create synthetic media', () async {
      final engine = DesktopTorrentEngine.instance;
      expect(await engine.startStream(''), isNull);
      await expectLater(
        engine.startStream('https://example.com/video.mp4'),
        throwsArgumentError,
      );
      await engine.stopStream('http://127.0.0.1:1/missing');
    });
  });

  group('Torrent Scraper Suite Tests', () {
    test('LeviTorrentScraper parses Nyaa XML feeds', () {
      const xmlFeed = '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Nyaa</title>
    <item>
      <title>[SubsPlease] Frieren - 01 (1080p) [12345678].mkv</title>
      <link>https://nyaa.si/download/1000001.torrent</link>
      <infoHash>0123456789abcdef0123456789abcdef01234567</infoHash>
      <seeders>25</seeders>
      <leechers>2</leechers>
      <size>1.2 GiB</size>
    </item>
  </channel>
</rss>''';

      final results = LeviTorrentScraper.parseFeed(xmlFeed);
      expect(results.length, equals(1));
      expect(results.first.title, contains('Frieren - 01'));
      expect(results.first.seeders, equals(25));
      expect(results.first.resolution, equals(1080));
      expect(
        results.first.torrentUrl,
        equals('https://nyaa.si/download/1000001.torrent'),
      );
    });

    test('ErenTorrentScraper searches and ranks NekoBT results', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '''{
            "data": {
              "results": [
                {
                  "id": "999",
                  "title": "[Erai-raws] Frieren - 01 [1080p][Multiple Subtitle].mkv",
                  "seeders": 15,
                  "leechers": 1,
                  "filesize": 1400000000,
                  "magnet": "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567",
                  "audio_lang": ["jpn"]
                }
              ]
            }
          }''',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final scraper = ErenTorrentScraper(client: mockClient);
      final results = await scraper.searchAnimeTorrents(
        title: 'Sousou no Frieren',
        alternativeTitles: ['Frieren'],
        episodeNumber: 1,
        language: 'sub',
      );

      expect(results.length, equals(1));
      expect(results.first.title, contains('Frieren - 01'));
      expect(results.first.seeders, equals(15));
      expect(results.first.resolution, equals(1080));
    });

    test('MikasaTorrentScraper searches ShanaProject releases', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '''<!DOCTYPE html>
<html>
  <body>
    <div class="release_block">
      <div class="release_title"><a href="/series/frieren">Sousou no Frieren</a></div>
      <div class="release_episode">01</div>
      <div class="release_profile">1080p</div>
      <div class="release_size">1.3 GB</div>
      <a href="/download/12345.torrent">Download</a>
    </div>
  </body>
</html>''',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final scraper = MikasaTorrentScraper(client: mockClient);
      final results = await scraper.searchAnimeTorrents(
        title: 'Sousou no Frieren',
        episodeNumber: 1,
        language: 'sub',
      );

      expect(results.length, equals(1));
      expect(results.first.title, contains('Sousou no Frieren - 01'));
      expect(results.first.resolution, equals(1080));
    });

    test(
      'LeviTorrentProvider resolves and mounts local stream URL for Levi',
      () async {
        final mockClient = MockClient((request) async {
          if (request.url.host == 'graphql.anilist.co') {
            return http.Response(
              '''{
              "data": {
                "Media": {
                  "id": 154587,
                  "idMal": 52991,
                  "episodes": 28,
                  "synonyms": ["Frieren"],
                  "title": {
                    "romaji": "Sousou no Frieren",
                    "english": "Frieren: Beyond Journey's End",
                    "native": "葬送のフリーレン"
                  }
                }
              }
            }''',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.host == 'nyaa.si') {
            return http.Response(
              '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Nyaa</title>
    <item>
      <title>[SubsPlease] Sousou no Frieren - 01 (1080p) [12345678].mkv</title>
      <link>https://nyaa.si/download/1000001.torrent</link>
      <infoHash>0123456789abcdef0123456789abcdef01234567</infoHash>
      <seeders>30</seeders>
      <leechers>3</leechers>
      <size>1.2 GiB</size>
    </item>
  </channel>
</rss>''',
              200,
              headers: {'content-type': 'application/xml'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final provider = LeviTorrentProvider(
          client: mockClient,
          prepareStream: (torrentUrl) async =>
              'http://127.0.0.1:45678/levi/test_session/stream.mkv',
          stopStream: (url) async {},
        );

        final result = await provider.resolve(
          idType: 'ani',
          id: '154587',
          episodeNumber: 1,
          language: 'sub',
          serverName: 'Levi',
        );

        expect(result, isNotNull);
        expect(result!.name, equals('Levi'));
        expect(
          result.videoUrls,
          equals(['http://127.0.0.1:45678/levi/test_session/stream.mkv']),
        );
        expect(result.speedStatus, equals('Peer-dependent'));
        expect(result.usesTorrentPlayer, isTrue);
        expect(result.hasEmbeddedAudioControls, isTrue);
      },
    );
  });
}
