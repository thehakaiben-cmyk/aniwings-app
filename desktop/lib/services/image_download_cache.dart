import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'artwork_download_worker.dart';
import 'package:http/http.dart' as http;

/// Shares encoded artwork across resize variants without decoding during intro.
class ImageDownloadCache {
  static final shared = ImageDownloadCache();
  final http.Client _client;
  final bool _backgroundDownloads;
  final int maximumBytes;
  final int concurrentDownloads;
  final _bytes = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List>>{};
  final _waiters = Queue<_DownloadSlot>();
  final _foregroundWaiters = Queue<_DownloadSlot>();
  final _queued = <String, _DownloadSlot>{};
  int _usedBytes = 0;
  int _active = 0;

  ImageDownloadCache({
    http.Client? client,
    this.maximumBytes = 24 * 1024 * 1024,
    this.concurrentDownloads = 3,
  }) : assert(concurrentDownloads > 0),
       assert(maximumBytes >= 0),
       _backgroundDownloads =
           client == null &&
           !kIsWeb &&
           !Platform.environment.containsKey('FLUTTER_TEST'),
       _client = client ?? http.Client();

  Future<Uint8List> load(String url, {bool prioritize = false}) {
    final cached = _bytes.remove(url);
    if (cached != null) {
      _bytes[url] = cached;
      return Future.value(cached);
    }
    final existing = _pending[url];
    if (existing != null) {
      final slot = _queued[url];
      if (prioritize && slot != null && _waiters.remove(slot)) {
        _foregroundWaiters.add(slot);
      }
      return existing;
    }
    final request = _download(url, prioritize);
    _pending[url] = request;
    return request;
  }

  Future<void> prefetch(Iterable<String> urls) async {
    await Future.wait(
      urls.where((url) => url.trim().isNotEmpty).toSet().map((url) async {
        try {
          await load(url);
        } catch (_) {
          /* Visible images can retry later. */
        }
      }),
    );
  }

  Future<void> _acquire(String url, bool prioritize) async {
    if (_active < concurrentDownloads) {
      _active++;
      return;
    }
    final slot = _DownloadSlot(url);
    _queued[url] = slot;
    (prioritize ? _foregroundWaiters : _waiters).add(slot);
    await slot.ready.future;
  }

  void _release() {
    final queue = _foregroundWaiters.isNotEmpty ? _foregroundWaiters : _waiters;
    if (queue.isNotEmpty) {
      final slot = queue.removeFirst();
      _queued.remove(slot.url);
      slot.ready.complete();
    } else {
      _active--;
    }
  }

  Future<Uint8List> _download(String url, bool prioritize) async {
    await _acquire(url, prioritize);
    try {
      final data = _backgroundDownloads
          ? await ArtworkDownloadWorker.shared
                .load(url)
                .timeout(const Duration(seconds: 12))
          : await _fetchBytes(url);
      if (data.length <= maximumBytes) {
        while (_usedBytes + data.length > maximumBytes && _bytes.isNotEmpty) {
          final oldest = _bytes.keys.first;
          _usedBytes -= _bytes.remove(oldest)!.length;
        }
        _bytes[url] = data;
        _usedBytes += data.length;
      }
      return data;
    } finally {
      _pending.remove(url);
      _release();
    }
  }

  Future<Uint8List> _fetchBytes(String url) async {
    final response = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw StateError('Artwork request failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  void evict(String url) {
    final previous = _bytes.remove(url);
    if (previous != null) _usedBytes -= previous.length;
  }

  void dispose() {
    _client.close();
  }
}

class _DownloadSlot {
  final String url;
  final ready = Completer<void>();
  _DownloadSlot(this.url);
}
