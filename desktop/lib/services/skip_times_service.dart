import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/episode_skip_times.dart';

final skipTimesServiceProvider = Provider<SkipTimesService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return SkipTimesService(client);
});

class SkipTimesService {
  final http.Client _client;
  final Map<String, EpisodeSkipTimes> _cache = {};
  final Map<String, Future<EpisodeSkipTimes>> _pending = {};

  SkipTimesService(this._client);

  Future<EpisodeSkipTimes> getSkipTimes(
    String malId,
    int episodeNumber,
    Duration duration,
  ) async {
    if ((int.tryParse(malId) ?? 0) <= 0 ||
        episodeNumber <= 0 ||
        duration <= Duration.zero) {
      return const EpisodeSkipTimes();
    }
    final key = '$malId|$episodeNumber|${duration.inMilliseconds}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = _fetch(malId, episodeNumber, duration, key);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  Future<EpisodeSkipTimes> _fetch(
    String malId,
    int episodeNumber,
    Duration duration,
    String key,
  ) async {
    try {
      final uri = Uri.https(
        'api.aniskip.com',
        '/v2/skip-times/$malId/$episodeNumber',
        {
          'types': ['op', 'ed'],
          'episodeLength': (duration.inMilliseconds / 1000).toStringAsFixed(3),
        },
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return const EpisodeSkipTimes();
      final result = EpisodeSkipTimes.fromAniSkip(
        jsonDecode(response.body),
        duration,
      );
      if (_cache.length >= 80) _cache.remove(_cache.keys.first);
      _cache[key] = result;
      return result;
    } catch (_) {
      return const EpisodeSkipTimes();
    }
  }
}
