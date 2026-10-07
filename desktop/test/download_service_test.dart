import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aniwings/models/anime.dart';
import 'package:aniwings/models/episode.dart';
import 'package:aniwings/models/video_provider.dart';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/download_service.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Catalog extends AnimeService {
  List<VideoProviderSource> sources = [];
  Completer<List<VideoProviderSource>>? pending;
  @override
  Future<List<VideoProviderSource>> getVideoProvidersForEpisode(
    String id,
    int episode,
  ) async => pending == null ? sources : await pending!.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SharedPreferences prefs;
  late _Catalog catalog;
  late DownloadService service;
  final anime = Anime(
    id: 'test',
    title: 'Anime: A / B',
    description: '',
    posterUrl: '',
    backdropUrl: '',
    rating: 8,
    status: 'Completed',
    genres: const ['Action'],
    totalEpisodes: 2,
    year: '2026',
  );
  Episode episode(int number) => Episode(
    id: 'test_ep_$number',
    animeId: 'test',
    episodeNumber: number,
    title: 'Episode $number',
    airDate: DateTime(2026),
    duration: const Duration(minutes: 24),
    videoUrls: const [],
  );
  VideoProviderSource source(String url, {String audio = 'SUB'}) =>
      VideoProviderSource(
        name: 'Gojo',
        description: '',
        languageType: audio,
        videoUrls: [url],
        speedStatus: 'Fast',
        headers: const {'Referer': 'https://source.test'},
      );
  final mp4 = [0, 0, 0, 24, ...'ftypisom'.codeUnits, ...List.filled(32, 0)];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'aniwings-download-test-',
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    catalog = _Catalog();
  });
  tearDown(() async {
    service.dispose();
    catalog.dispose();
    await directory.delete(recursive: true);
  });
  void create(http.Client Function() client) {
    service = DownloadService(
      catalog,
      StorageService(prefs),
      prefs,
      directoryFactory: () async => directory,
      clientFactory: client,
    );
  }

  Future<void> enqueue(List<Episode> episodes) => service.enqueue(
    anime: anime,
    episodes: episodes,
    quality: '720P',
    audio: 'SUB',
  );

  test(
    'failover verifies files, deduplicates queue and restores completed history',
    () async {
      catalog.sources = [
        source('https://media.test/error'),
        source('https://media.test/video.mp4'),
      ];
      create(
        () => MockClient((request) async {
          expect(request.headers['Referer'], 'https://source.test');
          return request.url.path == '/error'
              ? http.Response(
                  '<html>error</html>',
                  200,
                  headers: {'content-type': 'text/html'},
                )
              : http.Response.bytes(mp4, 200);
        }),
      );
      await enqueue([episode(1), episode(1), episode(2)]);
      await service.idle;
      expect(service.tasks.length, 2);
      expect(
        service.tasks.every((task) => task.status == DownloadStatus.completed),
        isTrue,
      );
      for (final task in service.tasks) {
        expect(await File(task.path!).readAsBytes(), mp4);
        expect(task.path!.endsWith('.mp4'), isTrue);
      }
      expect(await service.completedBytes(), mp4.length * 2);
      expect(
        directory.listSync().whereType<File>().any(
          (file) => file.path.endsWith('.part'),
        ),
        isFalse,
      );
      service.dispose();
      create(
        () => MockClient(
          (_) async =>
              throw StateError('Completed history must not download again'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.tasks.length, 2);
      await service.remove(service.tasks.first);
      expect(service.tasks.length, 1);
      expect(directory.listSync().whereType<File>().length, 1);
    },
  );
  test('failed media leaves no video and retry succeeds', () async {
    catalog.sources = [source('https://media.test/video')];
    var fail = true;
    create(
      () => MockClient(
        (_) async => fail
            ? http.Response('<html>no video</html>', 200)
            : http.Response.bytes(mp4, 200),
      ),
    );
    await enqueue([episode(1)]);
    await service.idle;
    final task = service.tasks.single;
    expect(task.status, DownloadStatus.failed);
    expect(directory.listSync(), isEmpty);
    fail = false;
    await service.retry(task);
    await service.idle;
    expect(service.tasks.single.status, DownloadStatus.completed);
  });
  test(
    'cancel resolving task and queued task without publishing files',
    () async {
      catalog.pending = Completer<List<VideoProviderSource>>();
      create(
        () => MockClient(
          (_) async => throw StateError('Cancelled queue must not transfer'),
        ),
      );
      await enqueue([episode(1), episode(2)]);
      await service.cancel(service.tasks[0]);
      await service.cancel(service.tasks[1]);
      catalog.pending!.complete([source('https://media.test/video')]);
      await service.idle;
      expect(
        service.tasks.every((task) => task.status == DownloadStatus.cancelled),
        isTrue,
      );
      expect(directory.listSync(), isEmpty);
    },
  );
  test('interrupted queue restores and completed video is persisted', () async {
    final pending = DownloadTask(
      id: 'pending',
      anime: anime,
      episode: episode(1),
      quality: '720P',
      audio: 'SUB',
      status: DownloadStatus.downloading,
    );
    await prefs.setStringList('desktop_download_tasks', [
      jsonEncode(pending.toJson()),
    ]);
    catalog.sources = [source('https://media.test/video')];
    create(() => MockClient((_) async => http.Response.bytes(mp4, 200)));
    await Future<void>.delayed(Duration.zero);
    await service.idle;
    expect(service.tasks.single.status, DownloadStatus.completed);
    expect(await File(service.tasks.single.path!).exists(), isTrue);
  });
  test(
    'download audio preference never silently switches SUB to DUB',
    () async {
      catalog.sources = [source('https://media.test/dub.mp4', audio: 'DUB')];
      create(
        () => MockClient(
          (_) async => throw StateError('Wrong audio must not transfer'),
        ),
      );
      await enqueue([episode(1)]);
      await service.idle;
      expect(service.tasks.single.status, DownloadStatus.failed);
      expect(directory.listSync(), isEmpty);
    },
  );
}
