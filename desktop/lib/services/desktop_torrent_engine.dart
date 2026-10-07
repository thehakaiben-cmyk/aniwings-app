import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'torrent_stream_rules.dart';

/// Peer-backed streaming with native piece scheduling and HTTP range support.
class DesktopTorrentEngine {
  DesktopTorrentEngine._();
  static final instance = DesktopTorrentEngine._();
  Future<void>? _initialization;
  final _sessions = <String, ({int torrentId, int streamId})>{};

  Future<void> _initialize() => _initialization ??=
      LibtorrentFlutter.init(
        fetchTrackers: true,
        uploadLimit: 256 * 1024,
      ).catchError((Object error) {
        _initialization = null;
        throw error;
      });

  Future<String?> startStream(
    String torrentUrl, {
    int? episodeNumber,
    Map<String, String> headers = const {},
  }) async {
    if (torrentUrl.trim().isEmpty) return null;
    final request = TorrentRequest.parse(torrentUrl);
    await _initialize();
    final engine = LibtorrentFlutter.instance;
    int? torrentId;
    try {
      if (request.isMagnet) {
        torrentId = engine.addMagnet(request.url, null, true);
      } else {
        final client = http.Client();
        final directory = await Directory.systemTemp.createTemp(
          'aniwings_metadata_',
        );
        try {
          final response = await client
              .get(Uri.parse(torrentUrl), headers: headers)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
            return null;
          }
          final file = File('${directory.path}/source.torrent');
          await file.writeAsBytes(response.bodyBytes);
          torrentId = engine.addTorrentFile(file.path, null, true);
        } finally {
          client.close();
          await directory.delete(recursive: true);
        }
      }
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      var files = engine.getFiles(torrentId);
      while (files.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        files = engine.getFiles(torrentId);
      }
      final index = LeviStreamRules.selectVideo(
        files: files.map((file) => (path: file.path, size: file.size)).toList(),
        episodeNumber: episodeNumber,
        fileIndex: request.fileIndex,
      );
      final stream = engine.startStream(
        torrentId,
        fileIndex: files[index].index,
      );
      _sessions[stream.url] = (torrentId: torrentId, streamId: stream.id);
      return stream.url;
    } catch (_) {
      if (torrentId != null) engine.removeTorrent(torrentId, deleteFiles: true);
      rethrow;
    }
  }

  Future<void> stopStream(String url) async {
    final session = _sessions.remove(url);
    if (session == null || !LibtorrentFlutter.isInitialized) return;
    final engine = LibtorrentFlutter.instance;
    engine.stopStream(session.streamId);
    engine.removeTorrent(session.torrentId, deleteFiles: true);
  }

  // Native stream-only sessions use a bounded RAM cache, not placeholder files.
  void cleanupOrphanedCaches() {}
}
