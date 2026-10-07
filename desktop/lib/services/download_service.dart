import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime.dart';
import '../models/episode.dart';
import '../models/video_provider.dart';
import 'anime_service.dart';
import 'storage_service.dart';
import 'media_download.dart';
import 'levi_native_proxy_io.dart';

enum DownloadStatus {
  queued,
  resolving,
  downloading,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  final String id;
  final Anime anime;
  final Episode episode;
  final String quality;
  final String audio;
  DownloadStatus status;
  double progress = 0;
  String? path;
  String? subtitlePath;
  String? stagingPath;
  String? error;
  bool cancelled = false;
  DownloadTask({
    required this.id,
    required this.anime,
    required this.episode,
    required this.quality,
    required this.audio,
    this.status = DownloadStatus.queued,
    this.path,
    this.subtitlePath,
    this.stagingPath,
    this.error,
  });
  bool get active => {
    DownloadStatus.queued,
    DownloadStatus.resolving,
    DownloadStatus.downloading,
  }.contains(status);
  Map<String, dynamic> toJson() => {
    'id': id,
    'anime': anime.toJson(),
    'episode': episode.toJson(),
    'quality': quality,
    'audio': audio,
    'status': status.name,
    'path': path,
    'subtitlePath': subtitlePath,
    'stagingPath': stagingPath,
    'error': error,
  };
  factory DownloadTask.fromJson(Map<String, dynamic> value) => DownloadTask(
    id: value['id'],
    anime: Anime.fromJson(value['anime']),
    episode: Episode.fromJson(value['episode']),
    quality: value['quality'],
    audio: value['audio'],
    status: DownloadStatus.values.byName(value['status']),
    path: value['path'],
    subtitlePath: value['subtitlePath'],
    stagingPath: value['stagingPath'],
    error: value['error'],
  );
}

final downloadServiceProvider = ChangeNotifierProvider<DownloadService>(
  (ref) => DownloadService(
    ref.read(animeServiceProvider),
    ref.read(storageServiceProvider),
    ref.read(sharedPreferencesProvider),
    catalogResolver: () => ref.read(animeServiceProvider),
  ),
);

/// One persistent queue for all pages. Transfers publish only verified files.
class DownloadService extends ChangeNotifier {
  final AnimeService animeService;
  final StorageService storage;
  final AnimeService Function()? catalogResolver;
  final SharedPreferences preferences;
  final http.Client Function() clientFactory;
  final Future<Directory> Function()? directoryFactory;
  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool _running = false;
  bool _disposed = false;
  DownloadTask? _current;
  Completer<void>? _currentDone;
  http.Client? _client;
  Future<void> _writes = Future.value();
  Future<void> get idle => _processing;
  Future<void> _processing = Future.value();
  DownloadService(
    this.animeService,
    this.storage,
    this.preferences, {
    http.Client Function()? clientFactory,
    this.directoryFactory,
    this.catalogResolver,
  }) : clientFactory = clientFactory ?? http.Client.new {
    for (final raw
        in preferences.getStringList('desktop_download_tasks') ?? <String>[]) {
      try {
        final task = DownloadTask.fromJson(jsonDecode(raw));
        if (task.active) task.status = DownloadStatus.queued;
        _tasks.add(task);
      } catch (_) {
        /* Ignore an individual corrupt record. */
      }
    }
    // Restoration finishes before listeners can enqueue another batch.
    scheduleMicrotask(_start);
  }
  static Future<Directory> defaultDirectory() async {
    final base = Platform.isAndroid
        ? await getApplicationDocumentsDirectory()
        : (await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory());
    return Directory('${base.path}${Platform.pathSeparator}AniWings');
  }

  Future<void> _save() {
    final snapshot = _tasks.map((task) => jsonEncode(task.toJson())).toList();
    _writes = _writes.catchError((_) {}).then((_) async {
      await preferences.setStringList('desktop_download_tasks', snapshot);
    });
    return _writes;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> enqueue({
    required Anime anime,
    required List<Episode> episodes,
    required String quality,
    required String audio,
  }) async {
    if (_disposed) return;
    for (final episode in episodes) {
      final id = '${anime.id}_${episode.id}_${quality}_$audio';
      if (_tasks.any(
        (task) =>
            task.id == id &&
            (task.active ||
                (task.status == DownloadStatus.completed &&
                    task.path != null &&
                    File(task.path!).existsSync())),
      )) {
        continue;
      }
      _tasks.removeWhere((task) => task.id == id);
      _tasks.add(
        DownloadTask(
          id: id,
          anime: anime,
          episode: episode,
          quality: quality,
          audio: audio,
        ),
      );
    }
    await _save();
    _changed();
    _start();
  }

  void _start() {
    if (_running ||
        _disposed ||
        !_tasks.any((task) => task.status == DownloadStatus.queued)) {
      return;
    }
    _running = true;
    _processing = _process();
  }

  Future<void> _process() async {
    try {
      while (!_disposed) {
        final task = _tasks
            .where((task) => task.status == DownloadStatus.queued)
            .firstOrNull;
        if (task == null) break;
        _current = task;
        final done = Completer<void>();
        _currentDone = done;
        try {
          await _download(task);
          await _save();
          _changed();
        } finally {
          _current = null;
          _currentDone = null;
          done.complete();
        }
      }
    } finally {
      _current = null;
      _running = false;
    }
  }

  Future<void> cancel(DownloadTask task) async {
    if (!task.active) return;
    task.cancelled = true;
    task.status = DownloadStatus.cancelled;
    if (identical(_current, task)) _client?.close();
    await _save();
    _changed();
  }

  Future<void> retry(DownloadTask task) async {
    if (identical(_current, task)) await _currentDone?.future;
    await enqueue(
      anime: task.anime,
      episodes: [task.episode],
      quality: task.quality,
      audio: task.audio,
    );
  }

  Future<int> completedBytes() async {
    var bytes = 0;
    for (final task in _tasks.where(
      (task) => task.status == DownloadStatus.completed,
    )) {
      for (final path in [task.path, task.subtitlePath]) {
        if (path != null) {
          try {
            bytes += await File(path).length();
          } on FileSystemException {
            /* Missing files do not occupy space. */
          }
        }
      }
    }
    return bytes;
  }

  Future<void> remove(DownloadTask task) async {
    if (task.active) await cancel(task);
    if (identical(_current, task)) await _currentDone?.future;
    // Only files recorded as belonging to this download are removed.
    for (final path in [task.path, task.subtitlePath]) {
      if (path != null && await File(path).exists()) await File(path).delete();
    }
    _tasks.remove(task);
    await _save();
    _changed();
  }

  Future<void> _download(DownloadTask task) async {
    task.status = DownloadStatus.resolving;
    task.error = null;
    _changed();
    try {
      final interrupted = task.stagingPath;
      if (interrupted != null) {
        final file = File(interrupted);
        final basename = file.uri.pathSegments.last;
        if (basename.startsWith('AniWings_') &&
            basename.endsWith('.part') &&
            await file.exists()) {
          await file.delete();
        }
        task.stagingPath = null;
      }
      final catalog = catalogResolver?.call() ?? animeService;
      catalog.seedMemoryCache(task.anime);
      final providers = await catalog
          .getVideoProvidersForEpisode(
            task.anime.id,
            task.episode.episodeNumber,
          )
          .timeout(const Duration(seconds: 60));
      final candidates = providers
          .where(
            (source) =>
                !source.isEmbed &&
                source.languageType.toUpperCase() == task.audio.toUpperCase(),
          )
          .toList();
      final errors = <String>[];
      for (final source in candidates) {
        if (task.cancelled || _disposed) break;
        String? torrentUrl;
        try {
          var urls = source.videoUrls;
          if (source.usesTorrentPlayer && source.sourcePlayerUrl != null) {
            torrentUrl = await prepareLeviNativeStream(
              source.sourcePlayerUrl!,
              episodeNumber: task.episode.episodeNumber,
            );
            urls = torrentUrl == null ? [] : [torrentUrl];
          }
          for (final url in urls) {
            if (task.cancelled || _disposed) break;
            try {
              await _transfer(task, source, url);
              task.status = DownloadStatus.completed;
              task.progress = 1;
              return;
            } catch (error) {
              errors.add('${source.name}: $error');
            }
          }
        } catch (error) {
          errors.add('${source.name}: $error');
        } finally {
          if (torrentUrl != null) await stopLeviNativeStream(torrentUrl);
        }
      }
      if (!task.cancelled && !_disposed) {
        throw StateError(
          errors.isEmpty
              ? 'No downloadable stream for this episode and audio.'
              : errors.join('\n'),
        );
      }
    } catch (error) {
      if (!task.cancelled && !_disposed) {
        task.status = DownloadStatus.failed;
        task.error = error.toString();
      }
    }
    if (task.cancelled) task.status = DownloadStatus.cancelled;
  }

  Future<void> _transfer(
    DownloadTask task,
    VideoProviderSource source,
    String url,
  ) async {
    final custom = storage.getCustomDownloadDirectory();
    final directory = directoryFactory != null
        ? await directoryFactory!()
        : custom == null
        ? await defaultDirectory()
        : Directory(custom);
    await directory.create(recursive: true);
    final name = task.anime.title.replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
      '_',
    );
    final stem =
        'AniWings_${name.substring(0, name.length.clamp(0, 90))}_EP${task.episode.episodeNumber}_${task.audio}_${DateTime.now().microsecondsSinceEpoch}';
    final staging = File(
      '${directory.path}${Platform.pathSeparator}$stem.part',
    );
    task.stagingPath = staging.path;
    final client = clientFactory();
    _client = client;
    final headers = {'User-Agent': 'Mozilla/5.0', ...?source.headers};
    task.status = DownloadStatus.downloading;
    task.progress = 0;
    _changed();
    var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await _save();
      final extension = await MediaDownload(client).save(
        url: url,
        file: staging,
        headers: headers,
        maxHeight:
            int.tryParse(task.quality.replaceAll(RegExp('[^0-9]'), '')) ?? 0,
        onProgress: (value) {
          if (task.cancelled || _disposed) {
            throw StateError('Download cancelled');
          }
          task.progress = value.clamp(0, 0.99);
          if (DateTime.now().difference(lastUpdate).inMilliseconds >= 250) {
            lastUpdate = DateTime.now();
            _changed();
          }
        },
      );
      if (task.cancelled || _disposed) throw StateError('Download cancelled');
      final result = await staging.rename(
        '${directory.path}${Platform.pathSeparator}$stem.$extension',
      );
      task.path = result.path;
      task.status = DownloadStatus.completed;
      task.progress = 1;
      await _save();
      _changed();
      // Save text subtitle tracks when the provider supplies them.
      final subtitle =
          source.subtitleTracks
              ?.where((track) => track.label.toLowerCase().contains('english'))
              .firstOrNull
              ?.url ??
          source.subtitleUrl;
      if (subtitle != null) {
        try {
          final response = await client
              .get(Uri.parse(subtitle), headers: headers)
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200 &&
              response.bodyBytes.length < 5 * 1024 * 1024 &&
              response.body.contains('-->')) {
            final file = File('${result.path}.vtt');
            await file.writeAsBytes(response.bodyBytes, flush: true);
            task.subtitlePath = file.path;
          }
        } catch (_) {
          /* Video remains usable without optional subtitles. */
        }
      }
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
      if (await staging.exists()) await staging.delete();
      task.stagingPath = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client?.close();
    super.dispose();
  }
}
