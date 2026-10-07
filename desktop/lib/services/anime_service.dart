import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/anime.dart';
import '../models/episode.dart';
import '../models/episode_skip_times.dart';
import '../models/video_provider.dart';
import '../models/character.dart';
import 'storage_service.dart';
import 'metadata_provider_service.dart';
import 'levi_native_proxy_stub.dart'
    if (dart.library.io) 'levi_native_proxy_io.dart';
import 'levi_torrent_provider.dart';

final animeServiceProvider = Provider<AnimeService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final provider = ref.watch(metadataProviderPreference);
  final service = AnimeService(storage: storage, metadataProvider: provider);
  ref.onDispose(service.dispose);
  return service;
});

class _AnimeLookupTarget {
  final String requestId;
  final String? malId;
  final String? aniListId;
  final String title;
  final List<String> aliases;
  final String? year;
  final int totalEpisodes;

  _AnimeLookupTarget({
    required this.requestId,
    required this.malId,
    required this.aniListId,
    required this.title,
    required this.aliases,
    required this.year,
    required this.totalEpisodes,
  });

  String get cacheKey => '${malId ?? requestId}|${title.toLowerCase()}';
}

class _ProviderSearchCandidate {
  final String watchUrl;
  final String title;
  final double score;
  final String? siteAnimeId;

  _ProviderSearchCandidate({
    required this.watchUrl,
    required this.title,
    required this.score,
    this.siteAnimeId,
  });
}

class _AniWatchEpisodeMatch {
  final String siteAnimeId;
  final String serverIds;
  final String? malId;
  final String pageTitle;

  _AniWatchEpisodeMatch({
    required this.siteAnimeId,
    required this.serverIds,
    required this.malId,
    required this.pageTitle,
  });
}

class _ProviderServerEntry {
  final String type;
  final String linkId;
  final String name;

  _ProviderServerEntry({
    required this.type,
    required this.linkId,
    required this.name,
  });
}

class _ResolvedProviderStream {
  final List<String> videoUrls;
  final Map<String, String> headers;
  final String? subtitleUrl;
  final List<SubtitleTrack>? subtitleTracks;
  final EpisodeSkipTimes skipTimes;

  const _ResolvedProviderStream({
    required this.videoUrls,
    required this.headers,
    this.subtitleUrl,
    this.subtitleTracks,
    this.skipTimes = const EpisodeSkipTimes(),
  });
}

class AnimeService {
  static const String _aniwingsApiHost = 'aniwings-app-api.onrender.com';

  final StorageService? storage;
  final http.Client _client;
  final MetadataProvider? metadataProvider;
  String _cacheKey(String key) => metadataProvider == null
      ? key
      : 'metadata_${metadataProvider!.name}_$key';
  void dispose() => _client.close();
  final Map<String, Anime> _memoryCache = {};
  final Map<String, List<Episode>> _episodesCache = {};
  final Map<String, DateTime> _episodesCacheTime = {};
  final Map<String, Map<String, dynamic>> _anilistCache = {};
  final Map<String, Map<String, dynamic>> _aniwingsInfoCache = {};
  final Map<String, Map<String, dynamic>> _jikanFullCache = {};
  final Map<String, Future<Anime?>> _animeDetailsInFlight = {};
  final Map<String, Future<Map<String, dynamic>?>> _anilistInFlight = {};
  final Map<String, Future<List<Episode>>> _episodesInFlight = {};
  Future<void> _jikanQueue = Future.value();
  DateTime _lastJikanRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const int _maxCacheSize = 80;

  void _trimMapCache<K, V>(Map<K, V> map, [int maxEntries = _maxCacheSize]) {
    if (map.length <= maxEntries) return;
    final keysToRemove = map.keys.take(map.length - maxEntries).toList();
    for (final key in keysToRemove) {
      map.remove(key);
    }
  }

  void clearMemoryCache() {
    _memoryCache.clear();
    _episodesCache.clear();
    _episodesCacheTime.clear();
    _anilistCache.clear();
    _aniwingsInfoCache.clear();
    _jikanFullCache.clear();
    _animeDetailsInFlight.clear();
    _anilistInFlight.clear();
    _episodesInFlight.clear();
  }

  // Legacy direct scrapers are disabled until their source-specific resolvers
  // return verified native streams again.
  bool get _enableScraperProviders => false;

  AnimeService({this.storage, this.metadataProvider, http.Client? client})
    : _client = client ?? http.Client();

  // Static fallback mock anime list
  final List<Anime> _fallbackAnimeList = [
    Anime(
      id: '52991',
      title: 'Frieren: Beyond Journey\'s End',
      description:
          'Elf mage Frieren and her courageous fellow adventurers have defeated the Demon King and brought peace to the land. But Frieren will long outlive the rest of her former party. How will she come to understand what life means to the humans around her?',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx154587-qQTzQnEJJ3oB.jpg',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/154587-ivXNJ23SM1xB.jpg',
      rating: 4.9,
      status: 'Completed',
      genres: ['Fantasy', 'Adventure', 'Drama'],
      totalEpisodes: 28,
      year: '2023',
    ),
    Anime(
      id: '38000',
      title: 'Demon Slayer: Kimetsu no Yaiba',
      description:
          'It is the Taisho Period in Japan. Tanjiro, a kindhearted boy who sells charcoal for a living, finds his family slaughtered by a demon. To make matters worse, his younger sister Nezuko, the sole survivor, has been transformed into a demon herself. Greatly devastated, Tanjiro resolves to become a demon slayer.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx101922-WBsBl0ClmgYL.jpg',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/101922-33MtJGsUSxga.jpg',
      rating: 4.8,
      status: 'Completed',
      genres: ['Action', 'Fantasy', 'Adventure'],
      totalEpisodes: 26,
      year: '2019',
    ),
    Anime(
      id: '16498',
      title: 'Attack on Titan',
      description:
          'Centuries ago, mankind was slaughtered to near extinction by monstrous humanoid creatures called Titans, forcing humans to hide in fear behind enormous concentric walls. What makes these giants truly terrifying is that their taste for human flesh is not born of hunger but what seems to be out of pleasure.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx16498-buvcRTBx4NSm.jpg',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/16498-8jpFCOcDmneX.jpg',
      rating: 4.9,
      status: 'Completed',
      genres: ['Action', 'Drama', 'Thriller'],
      totalEpisodes: 25,
      year: '2013',
    ),
    Anime(
      id: '40748',
      title: 'Jujutsu Kaisen',
      description:
          'A boy swallows a cursed talisman - the finger of a demon - and becomes cursed himself. He enters a shaman\'s school to be able to locate the demon\'s other body parts and thus exorcise himself.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx113415-LHBAeoZDIsnF.jpg',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/113415-jQBSkxWAAk83.jpg',
      rating: 4.7,
      status: 'Completed',
      genres: ['Action', 'Supernatural', 'Fantasy'],
      totalEpisodes: 24,
      year: '2020',
    ),
    Anime(
      id: '21',
      title: 'One Piece',
      description:
          'Gol D. Roger was known as the "Pirate King," the strongest and most infamous being to have sailed the Grand Line. The capture and execution of Roger by the World Government brought a change throughout the world. His last words before his death revealed the existence of the greatest treasure in the world, One Piece.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21-ELSYx3yMPcKM.jpg',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/21-wf37VakJmZqs.jpg',
      rating: 4.8,
      status: 'Releasing',
      genres: ['Action', 'Adventure', 'Comedy'],
      totalEpisodes: 1100,
      year: '1999',
    ),
    Anime(
      id: '1535',
      title: 'Death Note',
      description:
          'A shinigami, as a god of death, can kill any person—provided they see their victim\'s face and write their victim\'s name in a notebook called a Death Note. One day, Ryuk, bored by the shinigami lifestyle and interested in seeing how a human would use a Death Note, drops one into the human realm.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx1535-kUgkcrfOrkUM.jpg',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/1535.jpg',
      rating: 4.7,
      status: 'Completed',
      genres: ['Mystery', 'Psychological', 'Supernatural', 'Thriller'],
      totalEpisodes: 37,
      year: '2006',
    ),
    Anime(
      id: '21085',
      title: 'My Hero Academia',
      description:
          'The appearance of "quirks," newly discovered super powers, has been steadily increasing over the years, with 80 percent of humanity possessing various abilities. Izuku Midoriya is quirkless, but he still dreams of becoming a hero.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21459-nYh85uj2Fuwr.jpg',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/21459-yeVkolGKdGUV.jpg',
      rating: 4.5,
      status: 'Releasing',
      genres: ['Action', 'Comedy', 'Supernatural'],
      totalEpisodes: 138,
      year: '2016',
    ),
    Anime(
      id: '5114',
      title: 'Fullmetal Alchemist: Brotherhood',
      description:
          'Two brothers lose their mother to an incurable disease. With the power of alchemy, they use taboo knowledge to resurrect her. The process fails, and as a toll, the elder brother loses his left leg, and the younger brother loses his entire body.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx5114-nSWCgQlmOMtj.jpg',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/5114-q0V5URebphSG.jpg',
      rating: 4.9,
      status: 'Completed',
      genres: ['Action', 'Adventure', 'Drama', 'Fantasy'],
      totalEpisodes: 64,
      year: '2009',
    ),
    Anime(
      id: '150672',
      title: 'Oshi no Ko',
      description:
          'Dr. Goro is reborn as the son of the young starlet Ai Hoshino after her delusional stalker murders him. Now, Goro wants to help his new mother rise to the top of the entertainment industry, but what will he do when disaster strikes?',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx150672-WqmmwZ4nMzAy.png',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/150672-ISwoA0eS722H.jpg',
      rating: 4.6,
      status: 'Releasing',
      genres: ['Drama', 'Supernatural'],
      totalEpisodes: 11,
      year: '2023',
    ),
    Anime(
      id: '151807',
      title: 'Solo Leveling',
      description:
          'In a world where hunters must battle deadly monsters to protect mankind, Sung Jinwoo, the weakest hunter of all mankind, finds himself in a struggle for survival in a double dungeon.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx151807-it355ZgzquUd.png',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/151807-37yfQA3ym8PA.jpg',
      rating: 4.7,
      status: 'Releasing',
      genres: ['Action', 'Adventure', 'Fantasy'],
      totalEpisodes: 12,
      year: '2024',
    ),
    Anime(
      id: '127720',
      title: 'Chainsaw Man',
      description:
          'Denji has a simple dream—to live a happy and peaceful life, spending time with a girl he likes. However, this is a far cry from reality, as Denji is forced by the yakuza into killing devils in order to pay off his crushing debts.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx127230-DdP4vAdssLoz.png',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/127230-o8IRwCGVr9KW.jpg',
      rating: 4.6,
      status: 'Completed',
      genres: ['Action', 'Comedy', 'Supernatural'],
      totalEpisodes: 12,
      year: '2022',
    ),
    Anime(
      id: '21511',
      title: 'Your Name.',
      description:
          'Mitsuha Miyamizu, a high school girl, yearns to live the life of a boy in the bustling city of Tokyo—a dream that stands in contrast to her present life in the countryside. Meanwhile in the city, Taki Tachibana lives a busy life as a high school student.',
      posterUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx21519-SUo3ZQuCbYhJ.png',
      backdropUrl:
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/21519-1ayMXgNlmByb.jpg',
      rating: 4.9,
      status: 'Completed',
      genres: ['Romance', 'Drama', 'Supernatural'],
      totalEpisodes: 1,
      year: '2016',
    ),
  ];

  // Video links: serve as mock streams from our custom backend
  final List<String> _mockVideoUrls = [
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4', // 1080p
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4', // 720p
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4', // 480p
  ];

  // List of all genres
  final List<String> genres = [
    'All',
    'Action',
    'Adventure',
    'Fantasy',
    'Drama',
    'Thriller',
    'Supernatural',
    'Comedy',
    'Sci-Fi',
    'Slice of Life',
    'Romance',
    'Mystery',
    'Horror',
    'Sports',
    'Mecha',
    'Isekai',
    'Historical',
  ];

  Uri _jikanUri(String path, [Map<String, String>? queryParameters]) {
    return Uri.https('api.jikan.moe', '/v4/$path', queryParameters);
  }

  Uri _aniwingsApiUri(String path, [Map<String, String>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.https(_aniwingsApiHost, normalizedPath, queryParameters);
  }

  Future<T> _withJikanRateLimit<T>(Future<T> Function() request) async {
    final previous = _jikanQueue;
    final completer = Completer<void>();
    _jikanQueue = completer.future;

    await previous.catchError((_) {});
    try {
      final elapsed = DateTime.now().difference(_lastJikanRequestAt);
      const minimumGap = Duration(milliseconds: 700);
      if (elapsed < minimumGap) {
        await Future.delayed(minimumGap - elapsed);
      }
      _lastJikanRequestAt = DateTime.now();
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    // Serialize request starts, not entire responses/retries. A slow request
    // must not block every other catalog row behind it.
    return request();
  }

  Duration _retryDelay(http.Response response, int attempt) {
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter.clamp(1, 5));
    }
    return Duration(milliseconds: 900 * (attempt + 1));
  }

  bool _shouldUseCorsProxy(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'graphql.anilist.co' ||
        host == 'api.jikan.moe' ||
        host == _aniwingsApiHost ||
        host == 'localhost' ||
        host == '127.0.0.1') {
      return false;
    }
    return true;
  }

  Map<String, String>? _sanitizeWebHeaders(Map<String, String>? headers) {
    if (headers == null) return null;
    final sanitized = Map<String, String>.from(headers);
    sanitized.removeWhere((key, _) {
      final lower = key.toLowerCase();
      return lower == 'user-agent' ||
          lower == 'referer' ||
          lower == 'origin' ||
          lower == 'host' ||
          lower == 'cookie' ||
          lower == 'x-requested-with';
    });
    return sanitized.isEmpty ? null : sanitized;
  }

  Future<http.Response?> _getResponse(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    Future<http.Response?> perform() async {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final requestUri = (kIsWeb && _shouldUseCorsProxy(uri))
              ? Uri.parse(
                  'https://api.allorigins.win/raw?url=${Uri.encodeComponent(uri.toString())}',
                )
              : uri;
          final requestHeaders = kIsWeb
              ? _sanitizeWebHeaders(headers)
              : headers;
          final response = await _client
              .get(requestUri, headers: requestHeaders)
              .timeout(timeout);
          if (response.statusCode == 429 && attempt < 2) {
            await Future.delayed(_retryDelay(response, attempt));
            continue;
          }
          return response;
        } catch (_) {
          if (attempt == 2) return null;
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
      return null;
    }

    if (uri.host == 'api.jikan.moe') {
      return _withJikanRateLimit(perform);
    }
    return perform();
  }

  Future<Map<String, dynamic>?> _getJsonObject(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (metadataProvider == MetadataProvider.aniList &&
        uri.host == 'api.jikan.moe') {
      return null;
    }
    final response = await _getResponse(
      uri,
      headers: headers,
      timeout: timeout,
    );
    if (response?.statusCode != 200 || response?.body == null) {
      return null;
    }
    try {
      return jsonDecode(response!.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _rawAnimeId(String rawId) {
    var id = rawId.trim();
    if (id.contains('_')) {
      id = id.split('_').first.trim();
    }
    return id;
  }

  void seedMemoryCache(Anime anime) => _cacheAnime(anime);

  void _cacheAnime(Anime anime) {
    _memoryCache[anime.id] = anime;
    if (anime.malId != null && anime.malId!.trim().isNotEmpty) {
      _memoryCache[anime.malId!.trim()] = anime;
    }
    if (anime.aniListId != null && anime.aniListId!.trim().isNotEmpty) {
      _memoryCache['ani:${anime.aniListId!.trim()}'] = anime;
    }
    _trimMapCache(_memoryCache);
  }

  void _cacheAnimeList(List<Anime> animeList) {
    for (final anime in animeList) {
      _cacheAnime(anime);
    }
  }

  List<String> _titleAliases(Iterable<dynamic> values) {
    final aliases = <String>[];
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty || text == 'null') continue;
      if (!aliases.any((alias) => alias.toLowerCase() == text.toLowerCase())) {
        aliases.add(text);
      }
    }
    return aliases;
  }

  Future<Map<String, dynamic>?> _getJikanFullData(String animeId) async {
    final cleanId = _rawAnimeId(animeId);
    if (_jikanFullCache.containsKey(cleanId)) {
      return _jikanFullCache[cleanId];
    }
    final decoded = await _getJsonObject(_jikanUri('anime/$cleanId/full'));
    final data = decoded?['data'];
    if (data is Map<String, dynamic>) {
      _jikanFullCache[cleanId] = data;
      _jikanFullCache[animeId] = data;
      return data;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getAniwingsApiInfoData(String animeId) async {
    final cleanId = _rawAnimeId(animeId);
    if (_aniwingsInfoCache.containsKey(cleanId)) {
      return _aniwingsInfoCache[cleanId];
    }

    final decoded = await _getJsonObject(
      _aniwingsApiUri('/api/info/$cleanId', {
        'source': 'mal',
        'idSource': 'mal',
      }),
      timeout: const Duration(seconds: 3),
    );
    final data = decoded?['data'];
    if (data is Map<String, dynamic>) {
      _aniwingsInfoCache[cleanId] = data;
      _aniwingsInfoCache[animeId] = data;
      return data;
    }
    return null;
  }

  // Parse Jikan API JSON object to Anime Model
  Anime _parseJikanAnime(Map<String, dynamic> item) {
    final id = item['mal_id'].toString();
    final title =
        item['title_english'] as String? ??
        item['title'] as String? ??
        'Unknown Title';
    final description =
        item['synopsis'] as String? ?? 'No description available.';
    final posterUrl =
        item['images']?['jpg']?['large_image_url'] as String? ?? '';
    final backdropUrl =
        item['images']?['jpg']?['large_image_url'] as String? ?? '';

    final score = (item['score'] as num?)?.toDouble() ?? 8.0;
    final rating = (score / 2.0).clamp(1.0, 5.0); // Scale 10-star to 5-star

    final jikanStatus = item['status'] as String? ?? '';
    final status = _mapStatus(jikanStatus);

    final genresList = <String>{
      for (final field in ['genres', 'themes', 'demographics'])
        for (final entry in (item[field] as List? ?? const []))
          if (entry is Map && entry['name'] is String) entry['name'] as String,
    }.toList();

    final totalEpisodes = item['episodes'] as int? ?? 12;
    final year =
        item['year']?.toString() ??
        item['aired']?['prop']?['from']?['year']?.toString() ??
        '2023';

    final broadcastDay = item['broadcast']?['day'] as String?;
    final broadcastTime = item['broadcast']?['time'] as String?;
    final type = item['type'] as String? ?? 'TV';
    final episodeDurationMinutes = _parseDurationMinutes(item['duration']);
    final titleVariants = <dynamic>[
      item['title_english'],
      item['title'],
      item['title_japanese'],
      ...(item['titles'] as List? ?? const []).expand(
        (entry) => entry is Map ? [entry['title']] : const <dynamic>[],
      ),
    ];

    return Anime(
      id: id,
      title: title,
      description: description,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      rating: rating,
      status: status,
      genres: genresList,
      totalEpisodes: totalEpisodes,
      year: year,
      episodeDurationMinutes: episodeDurationMinutes,
      broadcastDay: broadcastDay,
      type: type,
      broadcastTime: broadcastTime,
      malId: id,
      alternativeTitles: _titleAliases(titleVariants),
    );
  }

  String _firstNonEmptyString(List<dynamic> values, String fallback) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value != null) {
        final text = value.toString().trim();
        if (text.isNotEmpty && text != 'null') {
          return text;
        }
      }
    }
    return fallback;
  }

  List<String> _parseStringList(
    dynamic value, {
    List<String> fallback = const ['Action'],
  }) {
    if (value is List) {
      final items = value
          .map((item) {
            if (item is String) return item;
            if (item is Map<String, dynamic>) return item['name']?.toString();
            return item?.toString();
          })
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      return items.isEmpty ? fallback : items;
    }
    // Handle space-delimited string (e.g. "Action Adventure Comedy" from AniWings API)
    if (value is String && value.trim().isNotEmpty) {
      final items = value
          .split(RegExp(r'\s+'))
          .where((item) => item.trim().isNotEmpty)
          .toList();
      return items.isEmpty ? fallback : items;
    }
    return fallback;
  }

  double _scoreToFiveStars(dynamic value) {
    final score = (value as num?)?.toDouble();
    if (score == null || score <= 0) return 4.0;
    return (score > 10 ? score / 20.0 : score / 2.0).clamp(1.0, 5.0);
  }

  String _mapStatus(String rawStatus) {
    final status = rawStatus.toLowerCase();
    if (status.contains('releasing') ||
        status.contains('currently') ||
        status.contains('airing')) {
      return 'Releasing';
    }
    if (status.contains('not_yet') ||
        status.contains('not yet') ||
        status.contains('upcoming')) {
      return 'Upcoming';
    }
    return 'Completed';
  }

  bool _isNotYetReleased(Anime anime) {
    final status = anime.status.toLowerCase();
    return status.contains('upcoming') ||
        status.contains('not_yet') ||
        status.contains('not yet') ||
        status.contains('not released');
  }

  List<Anime> _filterByReleaseState(
    List<Anime> list, {
    required bool upcomingOnly,
  }) {
    return list
        .where(
          (anime) => upcomingOnly
              ? _isNotYetReleased(anime)
              : !_isNotYetReleased(anime),
        )
        .toList();
  }

  String _animeIdentityKey(Anime anime) {
    return anime.malId?.trim().isNotEmpty == true
        ? 'mal:${anime.malId!.trim()}'
        : anime.aniListId?.trim().isNotEmpty == true
        ? 'ani:${anime.aniListId!.trim()}'
        : anime.id;
  }

  Future<List<({String idType, String id})>> _resolveMegaPlayCatalogCandidates(
    Anime anime,
  ) async {
    final candidates = <({String idType, String id})>[];

    void addCandidate(String idType, String? value) {
      final id = value?.trim() ?? '';
      if (id.isEmpty || id == 'null') return;
      if (!candidates.any(
        (candidate) => candidate.idType == idType && candidate.id == id,
      )) {
        candidates.add((idType: idType, id: id));
      }
    }

    // IDs supplied by MAL/AniList are the most reliable MegaPlay lookup.
    addCandidate('mal', anime.malId);
    addCandidate('ani', anime.aniListId);
    if (candidates.isNotEmpty) return candidates;

    // Older category/watch-history cache records often contain only a numeric
    // MAL ID. It is already our documented last-resort interpretation, so use
    // it before a sequence of remote title lookups instead of making playback
    // wait several seconds for the same answer.
    final fallbackId = anime.id.split('_').first.trim();
    if (int.tryParse(fallbackId) != null) {
      addCandidate('mal', fallbackId);
      return candidates;
    }

    // Older cached entries can lack source IDs. Resolve their English,
    // Romaji, native, and alternate titles back through AniList first.
    final aliases = _titleAliases([anime.title, ...anime.alternativeTitles]);
    for (final alias in aliases.take(4)) {
      try {
        const query = r'''
          query ($search: String) {
            Page (page: 1, perPage: 5) {
              media (search: $search, type: ANIME, isAdult: false) {
                id
                idMal
                title { english romaji native userPreferred }
              }
            }
          }
        ''';
        final response = await _client
            .post(
              Uri.parse('https://graphql.anilist.co'),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'query': query,
                'variables': {'search': alias},
              }),
            )
            .timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) continue;

        final media = jsonDecode(response.body)['data']?['Page']?['media'];
        if (media is! List) continue;
        for (final item in media.whereType<Map<String, dynamic>>()) {
          final titles = item['title'] as Map<String, dynamic>?;
          final matchingTitle =
              _titleAliases([
                titles?['english'],
                titles?['romaji'],
                titles?['native'],
                titles?['userPreferred'],
              ]).any(
                (title) =>
                    _normalizeTitleForMatch(title) ==
                    _normalizeTitleForMatch(alias),
              );
          if (!matchingTitle) continue;
          addCandidate('mal', item['idMal']?.toString());
          addCandidate('ani', item['id']?.toString());
          if (candidates.isNotEmpty) return candidates;
        }
      } catch (_) {}
    }

    return candidates;
  }

  Future<Set<String>> _playableMegaPlayEmbedLanguages({
    required String idType,
    required String id,
    required int episodeNumber,
  }) async {
    final checks = ['sub', 'dub'].map((language) async {
      try {
        final url = Uri.parse(
          'https://megaplay.buzz/stream/$idType/$id/$episodeNumber/$language?server=gojo',
        );
        final response = await _getResponse(
          url,
          headers: _embedHeadersForOrigin('https://megaplay.buzz'),
          timeout: const Duration(seconds: 5),
        );
        if (response == null || response.statusCode != 200) return null;
        final body = response.body.toLowerCase();
        final isNotFound =
            body.contains('404 not found') ||
            body.contains('episode not found');
        if (isNotFound) return null;
        return language.toUpperCase();
      } catch (_) {
        return language.toUpperCase();
      }
    });
    final results = (await Future.wait(checks)).whereType<String>().toSet();
    return results.isEmpty ? {'SUB', 'DUB'} : results;
  }

  /// Keeps metadata results intact. Video availability is resolved only when
  /// an episode is opened in the player, never while loading app content.
  Future<List<Anime>> _preserveMetadataResults(List<Anime> list) async {
    return List<Anime>.from(list);
  }

  Future<List<Anime>?> _readFilteredCategoryCache(
    String categoryKey, {
    required bool upcomingOnly,
  }) async {
    if (storage == null) return null;
    final cached = storage!.getCachedCategoryList(_cacheKey(categoryKey));
    if (cached == null || cached.isEmpty) return null;

    final filtered = _filterByReleaseState(cached, upcomingOnly: upcomingOnly);
    if (filtered.isEmpty) return null;

    _cacheAnimeList(filtered);
    return filtered;
  }

  Future<List<Anime>> _saveFilteredCategoryList(
    String categoryKey,
    List<Anime> list, {
    required bool upcomingOnly,
  }) async {
    final filtered = _filterByReleaseState(list, upcomingOnly: upcomingOnly);
    if (filtered.isNotEmpty) _cacheAnimeList(filtered);
    if (storage != null) {
      unawaited(
        storage!.saveCategoryListToCache(_cacheKey(categoryKey), filtered),
      );
    }
    return filtered;
  }

  int _parseDurationMinutes(dynamic value, {int fallback = 24}) {
    if (value is num && value > 0) {
      return value.round();
    }
    if (value is! String || value.trim().isEmpty) {
      return fallback;
    }

    final text = value.toLowerCase();
    var total = 0;
    final unitPattern = RegExp(
      r'(\d+)\s*(hr|hrs|hour|hours|h|min|mins|minute|minutes|m)',
    );

    for (final match in unitPattern.allMatches(text)) {
      final amount = int.tryParse(match.group(1) ?? '') ?? 0;
      final unit = match.group(2) ?? '';
      if (unit.startsWith('h')) {
        total += amount * 60;
      } else {
        total += amount;
      }
    }

    if (total > 0) return total;

    final firstNumber = RegExp(r'\d+').firstMatch(text)?.group(0);
    final parsed = int.tryParse(firstNumber ?? '');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }

  Anime _parseAniwingsApiAnime(Map<String, dynamic> item) {
    final titleObj = item['title'] as Map<String, dynamic>?;
    final coverObj = item['coverImage'] as Map<String, dynamic>?;
    final startDate = item['startDate'] as Map<String, dynamic>?;
    final nextAiringEpisode =
        item['nextAiringEpisode'] as Map<String, dynamic>?;

    final id = _firstNonEmptyString([
      item['idMal'],
      item['malId'],
      item['id'],
    ], 'unknown');
    final title = _firstNonEmptyString([
      titleObj?['english'],
      titleObj?['userPreferred'],
      titleObj?['romaji'],
      item['title'],
      item['name'],
    ], 'Unknown Title');
    final posterUrl = _firstNonEmptyString([
      coverObj?['extraLarge'],
      coverObj?['large'],
      coverObj?['medium'],
      item['posterUrl'],
      item['image'],
    ], '');
    final backdropUrl = _firstNonEmptyString([
      item['bannerImage'],
      item['backdropUrl'],
      posterUrl,
    ], posterUrl);
    final explicitEpisodes = (item['episodes'] as num?)?.toInt() ?? 0;
    final nextEpisode = (nextAiringEpisode?['episode'] as num?)?.toInt();
    final totalEpisodes = explicitEpisodes > 0
        ? explicitEpisodes
        : nextEpisode != null && nextEpisode > 1
        ? nextEpisode - 1
        : 0;
    final year = _firstNonEmptyString([
      item['seasonYear'],
      startDate?['year'],
      item['year'],
    ], '2023');
    final malId = _firstNonEmptyString([item['idMal'], item['malId']], '');
    final aniListId = _firstNonEmptyString([item['id']], '');

    return Anime(
      id: id,
      title: title,
      description:
          item['description'] as String? ?? 'No description available.',
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      rating: _scoreToFiveStars(
        item['averageScore'] ?? item['mean'] ?? item['score'],
      ),
      status: _mapStatus(item['status'] as String? ?? ''),
      genres: _parseStringList(item['genres']),
      totalEpisodes: totalEpisodes,
      year: year,
      episodeDurationMinutes: _parseDurationMinutes(item['duration']),
      malId: malId.isEmpty ? null : malId,
      aniListId: aniListId.isEmpty ? null : aniListId,
      alternativeTitles: _titleAliases([
        titleObj?['english'],
        titleObj?['romaji'],
        titleObj?['native'],
        titleObj?['userPreferred'],
        item['title'],
        item['name'],
      ]),
    );
  }

  // Get anime catalog (fallback list)
  Future<List<Anime>> getAnimeList() async {
    return [];
  }

  Anime? _fallbackAnimeById(String id) {
    for (final anime in _fallbackAnimeList) {
      if (anime.id == id) return anime;
    }
    return null;
  }

  List<Anime> _fallbackTrendingAnimeList() {
    final list = List<Anime>.from(_fallbackAnimeList)
      ..sort((a, b) {
        final byRating = b.rating.compareTo(a.rating);
        if (byRating != 0) return byRating;
        return a.title.compareTo(b.title);
      });
    _cacheAnimeList(list);
    return list;
  }

  // Get trending anime from AniList (primary) or Jikan (fallback)
  Future<List<Anime>> getTrendingAnime() async {
    final cached = await _readFilteredCategoryCache(
      'trending',
      upcomingOnly: false,
    );
    if (cached != null) {
      return cached;
    }

    const query = r'''
      query ($page: Int, $perPage: Int) {
        Page (page: $page, perPage: $perPage) {
          media (type: ANIME, sort: TRENDING_DESC, isAdult: false, format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
            description
          }
        }
      }
    ''';
    final list = await _fetchAniListCategory(query, {'page': 1, 'perPage': 15});
    if (list.isNotEmpty) {
      return _saveFilteredCategoryList('trending', list, upcomingOnly: false);
    }

    // Fallback to Jikan top anime by popularity
    try {
      final decoded = await _getJsonObject(
        _jikanUri('top/anime', {'filter': 'bypopularity', 'limit': '15'}),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final jikanList = data.map((item) => _parseJikanAnime(item)).toList();
        final filtered = await _saveFilteredCategoryList(
          'trending',
          jikanList,
          upcomingOnly: false,
        );
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return List<Anime>.from(_fallbackTrendingAnimeList());
  }

  // Get recommended anime based on user preferred genres
  Future<List<Anime>> getRecommendedAnime(List<String> userGenres) async {
    final list = await getTrendingAnime();
    if (userGenres.isEmpty) {
      return list.take(4).toList();
    }
    return list
        .where((anime) => anime.genres.any((g) => userGenres.contains(g)))
        .toList();
  }

  Future<List<Anime>> getRecommendationsForAnime(String animeId) async {
    if (metadataProvider != null) {
      final target = await getAnimeById(animeId);
      // Recommendations use the chosen catalog rather than blending fields
      // from a second provider into details.
      final list = await queryAnime(
        query: '',
        genre: target?.genres.firstOrNull ?? 'All',
        sortBy: 'Rating',
      );
      return list
          .where((anime) => anime.id != _rawAnimeId(animeId))
          .take(12)
          .toList();
    }
    final cleanId = _rawAnimeId(animeId);
    Anime? targetAnime = _memoryCache[cleanId] ?? _memoryCache[animeId];
    targetAnime ??= await getAnimeById(cleanId);

    final malId =
        targetAnime?.malId ?? (int.tryParse(cleanId) != null ? cleanId : null);
    final aniListId =
        targetAnime?.aniListId ??
        (int.tryParse(cleanId) != null ? cleanId : null);
    final genres = targetAnime?.genres ?? <String>[];

    final recommendations = <Anime>[];
    final seen = <String>{cleanId, animeId};
    if (aniListId != null) seen.add(aniListId);
    if (targetAnime != null) {
      seen.add(targetAnime.id);
      if (targetAnime.malId != null) seen.add(targetAnime.malId!);
      if (targetAnime.aniListId != null) seen.add(targetAnime.aniListId!);
    }

    // 1. Query AniList for relations & genre recommendations
    try {
      final aniData = await getAniListData(cleanId);
      if (aniData != null) {
        final edges = aniData['relations']?['edges'] as List<dynamic>? ?? [];
        for (final edge in edges) {
          final relType = edge['relationType'] as String? ?? '';
          if (![
            'PREQUEL',
            'SEQUEL',
            'PARENT',
            'SPIN_OFF',
            'SIDE_STORY',
            'ALTERNATIVE',
          ].contains(relType)) {
            continue;
          }
          final node = edge['node'] as Map<String, dynamic>? ?? {};
          final nodeMalId = node['idMal']?.toString();
          final nodeAniListId = node['id']?.toString();
          final nodeId = nodeMalId ?? nodeAniListId ?? '';
          if (nodeId.isEmpty || seen.contains(nodeId)) continue;
          if (nodeMalId != null && seen.contains(nodeMalId)) continue;
          if (nodeAniListId != null && seen.contains(nodeAniListId)) continue;

          seen.add(nodeId);
          if (nodeMalId != null) seen.add(nodeMalId);
          if (nodeAniListId != null) seen.add(nodeAniListId);

          final cover =
              node['coverImage']?['large'] as String? ??
              node['coverImage']?['medium'] as String? ??
              '';
          final title =
              node['title']?['userPreferred'] as String? ??
              node['title']?['english'] as String? ??
              node['title']?['romaji'] as String? ??
              'Unknown';
          final score = ((node['averageScore'] ?? 0) / 10.0);
          final year =
              node['startDate']?['year']?.toString() ??
              node['seasonYear']?.toString() ??
              '';
          final nodeGenres = (node['genres'] as List<dynamic>? ?? [])
              .map((g) => g.toString())
              .toList();

          recommendations.add(
            Anime(
              id: nodeId,
              title: title,
              posterUrl: cover,
              backdropUrl: cover,
              rating: score > 0 ? score : 4.0,
              year: year.isNotEmpty ? year : '2023',
              genres: nodeGenres.isNotEmpty ? nodeGenres : const ['Action'],
              status: _mapStatus(node['status'] as String? ?? ''),
              description: '',
              totalEpisodes: node['episodes'] ?? 0,
              malId: nodeMalId,
              aniListId: nodeAniListId,
              alternativeTitles: _titleAliases([
                node['title']?['english'],
                node['title']?['romaji'],
                node['title']?['userPreferred'],
              ]),
            ),
          );
        }

        final mediaGenres = (aniData['genres'] as List<dynamic>? ?? [])
            .map((g) => g.toString())
            .toList();
        final searchGenres = mediaGenres.isNotEmpty ? mediaGenres : genres;

        if (searchGenres.isNotEmpty) {
          final topGenres = searchGenres.take(3).toList();
          const genreQuery = r'''
            query ($page: Int, $perPage: Int, $genres: [String]) {
              Page (page: $page, perPage: $perPage) {
                media (
                  type: ANIME,
                  genre_in: $genres,
                  sort: SCORE_DESC,
                  isAdult: false,
                  averageScore_greater: 65,
                  format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]
                ) {
                  id idMal title { romaji english native userPreferred }
                  coverImage { extraLarge large medium } bannerImage averageScore status genres episodes seasonYear startDate { year month day } duration format
                }
              }
            }
          ''';
          final matched = await _fetchAniListCategory(genreQuery, {
            'page': 1,
            'perPage': 20,
            'genres': topGenres,
          });
          for (final a in matched) {
            final isSeen =
                seen.contains(a.id) ||
                (a.malId != null && seen.contains(a.malId)) ||
                (a.aniListId != null && seen.contains(a.aniListId));
            if (!isSeen) {
              seen.add(a.id);
              if (a.malId != null) seen.add(a.malId!);
              if (a.aniListId != null) seen.add(a.aniListId!);
              recommendations.add(a);
            }
          }
        }
      }
    } catch (_) {}

    if (recommendations.length >= 15) {
      return recommendations.take(20).toList();
    }

    // 2. Backup: Jikan recommendations API (using malId)
    try {
      final targetMalId =
          malId ?? (int.tryParse(cleanId) != null ? cleanId : null);
      if (targetMalId != null) {
        final decoded = await _getJsonObject(
          _jikanUri('anime/$targetMalId/recommendations'),
        );
        final data = decoded?['data'] as List?;
        if (data != null && data.isNotEmpty) {
          for (final item in data.take(20)) {
            final entry = item['entry'] as Map<String, dynamic>?;
            if (entry != null) {
              final recId = entry['mal_id']?.toString() ?? '';
              final title = entry['title'] as String? ?? 'Unknown';
              final images = entry['images']?['jpg'] ?? {};
              final poster =
                  images['large_image_url'] as String? ??
                  images['image_url'] as String? ??
                  '';
              if (recId.isNotEmpty && seen.add(recId)) {
                recommendations.add(
                  Anime(
                    id: recId,
                    title: title,
                    posterUrl: poster,
                    backdropUrl: poster,
                    rating: 4.5,
                    year: '2023',
                    genres: genres.isNotEmpty ? genres : const ['Action'],
                    status: 'Completed',
                    description: '',
                    totalEpisodes: 12,
                    malId: recId,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (_) {}

    if (recommendations.length >= 15) {
      return recommendations.take(20).toList();
    }

    // 3. Final Fallback: Match genres from trending/popular catalog
    try {
      final trending = await getTrendingAnime();
      for (final a in trending) {
        final isSeen =
            seen.contains(a.id) ||
            (a.malId != null && seen.contains(a.malId)) ||
            (a.aniListId != null && seen.contains(a.aniListId));
        if (!isSeen) {
          if (genres.isEmpty || a.genres.any((g) => genres.contains(g))) {
            recommendations.add(a);
            seen.add(a.id);
          }
        }
      }
    } catch (_) {}

    if (recommendations.length < 15) {
      for (final a in _fallbackAnimeList) {
        if (seen.add(a.id)) {
          recommendations.add(a);
        }
      }
    }

    return recommendations.take(20).toList();
  }

  // Get recent episode releases from seasonal anime
  Future<List<Episode>> getRecentReleases() async {
    if (metadataProvider == MetadataProvider.aniList) {
      final schedule = await getSchedule();
      final now = DateTime.now();
      return schedule
          .where((anime) {
            final date = DateTime.tryParse(anime.nextEpisodeDate ?? '');
            return date != null &&
                date.isBefore(now) &&
                anime.totalEpisodes > 0;
          })
          .map((anime) {
            final id = _rawAnimeId(anime.id);
            return Episode(
              id: '${id}_ep_${anime.totalEpisodes}',
              animeId: id,
              episodeNumber: anime.totalEpisodes,
              title: 'Episode ${anime.totalEpisodes}',
              thumbnailUrl: anime.backdropUrl,
              airDate: DateTime.parse(anime.nextEpisodeDate!),
              duration: Duration(minutes: anime.episodeDurationMinutes),
              videoUrls: const [],
            );
          })
          .toList();
    }
    try {
      final decoded = await _getJsonObject(_jikanUri('watch/episodes'));
      final data = decoded?['data'] as List?;
      if (data != null) {
        final recent = <({Anime anime, Episode episode})>[];
        for (var i = 0; i < data.length; i++) {
          final item = data[i];
          if (item is! Map<String, dynamic>) continue;
          final entry = item['entry'] as Map<String, dynamic>?;
          final episodesList = item['episodes'] as List?;
          if (entry == null || episodesList == null || episodesList.isEmpty) {
            continue;
          }

          final animeId = entry['mal_id']?.toString();
          if (animeId == null) continue;

          final animeTitle = entry['title'] as String? ?? 'Unknown Title';
          final posterUrl =
              entry['images']?['jpg']?['large_image_url'] as String? ??
              entry['images']?['jpg']?['image_url'] as String? ??
              '';

          // Cache the anime details so when details or cards fetch it, it is immediately available
          final cachedAnime = Anime(
            id: animeId,
            title: animeTitle,
            description: 'Recently released episode.',
            posterUrl: posterUrl,
            backdropUrl: posterUrl,
            rating: 4.5,
            status: 'Releasing',
            genres: const ['Action'],
            totalEpisodes: 12,
            year: DateTime.now().year.toString(),
            malId: animeId,
            alternativeTitles: _titleAliases([
              animeTitle,
              entry['title_japanese'],
            ]),
          );

          // Get the first (most recent) episode
          final ep = episodesList.first as Map<String, dynamic>;
          final epNum = ep['mal_id'] as int? ?? 1;
          final epTitle = ep['title'] as String? ?? 'Episode $epNum';

          recent.add((
            anime: cachedAnime,
            episode: Episode(
              id: '${animeId}_ep_$epNum',
              animeId: animeId,
              episodeNumber: epNum,
              title: epTitle,
              thumbnailUrl: posterUrl,
              airDate: DateTime.now().subtract(Duration(hours: i * 2)),
              duration: const Duration(minutes: 24),
              videoUrls: _mockVideoUrls,
            ),
          ));
        }
        if (recent.isNotEmpty) {
          final available = await _preserveMetadataResults(
            recent.map((item) => item.anime).toList(),
          );
          final availableKeys = available.map(_animeIdentityKey).toSet();
          final episodes = recent
              .where(
                (item) => availableKeys.contains(_animeIdentityKey(item.anime)),
              )
              .map((item) {
                _cacheAnime(item.anime);
                return item.episode;
              })
              .toList();
          if (episodes.isNotEmpty) return episodes;
        }
      }
    } catch (_) {}

    // Fallback to static list generator
    final recent = <({Anime anime, Episode episode})>[];
    for (var i = 0; i < _fallbackAnimeList.length; i++) {
      final anime = _fallbackAnimeList[i];
      recent.add((
        anime: anime,
        episode: Episode(
          id: '${anime.id}_ep_${anime.totalEpisodes}',
          animeId: anime.id,
          episodeNumber: anime.totalEpisodes,
          title: 'Episode ${anime.totalEpisodes}: Climax Arc Part $i',
          thumbnailUrl: anime.backdropUrl,
          airDate: DateTime.now().subtract(Duration(days: i)),
          duration: Duration(minutes: anime.episodeDurationMinutes),
          videoUrls: _mockVideoUrls,
        ),
      ));
    }
    final available = await _preserveMetadataResults(
      recent.map((item) => item.anime).toList(),
    );
    final availableKeys = available.map(_animeIdentityKey).toSet();
    return recent
        .where((item) => availableKeys.contains(_animeIdentityKey(item.anime)))
        .map((item) => item.episode)
        .toList();
  }

  // Search, filter, and sort anime from MyAnimeList Jikan API
  Future<List<Anime>> queryAnime({
    required String query,
    required String genre,
    required String sortBy,
  }) async {
    if (metadataProvider != null) {
      final key = _cacheKey('browse_${query.trim()}_${genre}_$sortBy');
      final cached = storage?.getCachedCategoryList(key);
      if (cached != null && cached.isNotEmpty) {
        _cacheAnimeList(cached);
        return cached;
      }
      var list = metadataProvider == MetadataProvider.aniList
          ? query.trim().isEmpty
                ? await _searchViaAniListGenreSort(genre, sortBy)
                : await _searchViaAniList(query)
          : await _searchViaJikan(query, genre, sortBy);
      if (genre != 'All') {
        list = list.where((anime) => anime.genres.contains(genre)).toList();
      }
      _sortAnimeList(list, sortBy, query);
      _cacheAnimeList(list);
      if (list.isNotEmpty && storage != null) {
        await storage!.saveCategoryListToCache(key, list);
      }
      return list;
    }
    final browseCacheKey = query.trim().isEmpty
        ? 'browse_${genre.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${sortBy.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}'
        : null;
    if (browseCacheKey != null && storage != null) {
      final cached = storage!.getCachedCategoryList(_cacheKey(browseCacheKey));
      if (cached != null && cached.isNotEmpty) {
        _cacheAnimeList(cached);
        return cached;
      }
    }

    // Run AniWings API search and Jikan search in parallel for fastest results
    if (query.trim().isNotEmpty) {
      final futures = <Future<List<Anime>>>[];

      // 1. AniWings API search
      futures.add(_searchViaAniwingsApi(query, genre, sortBy));

      // 2. Jikan search (direct, reliable)
      futures.add(_searchViaJikan(query, genre, sortBy));

      // 3. AniList GraphQL search
      futures.add(_searchViaAniList(query));

      try {
        final results = await Future.wait(futures, eagerError: false);
        // Merge all results, preferring earlier (faster) sources
        final merged = <String, Anime>{};
        for (final list in results) {
          for (final anime in list) {
            if (anime.id != 'unknown' && !merged.containsKey(anime.id)) {
              merged[anime.id] = anime;
            }
          }
        }
        if (merged.isNotEmpty) {
          var animeList = merged.values.toList();
          if (genre != 'All') {
            animeList = animeList
                .where((anime) => anime.genres.contains(genre))
                .toList();
          }
          _sortAnimeList(animeList, sortBy, query);
          animeList = await _preserveMetadataResults(animeList);
          _cacheAnimeList(animeList);
          return animeList;
        }
      } catch (_) {}
    } else {
      // Genre-only browsing (no query text, including genre = 'All')
      final futures = <Future<List<Anime>>>[
        _searchViaAniListGenreSort(genre, sortBy),
        _searchViaJikan('', genre, sortBy),
      ];

      try {
        // Browse only needs one healthy catalog source to paint the grid. Do
        // not make the UI wait for the slower service when the other has
        // already returned a complete page.
        final firstResult = await _firstNonEmptyAnimeList(futures);
        if (firstResult.isNotEmpty) {
          var animeList = firstResult
              .where((anime) => anime.id != 'unknown')
              .toList();
          _sortAnimeList(animeList, sortBy, query);
          animeList = await _preserveMetadataResults(animeList);
          _cacheAnimeList(animeList);
          if (browseCacheKey != null && storage != null) {
            unawaited(
              storage!.saveCategoryListToCache(
                _cacheKey(browseCacheKey),
                animeList,
              ),
            );
          }
          return animeList;
        }
      } catch (_) {}
    }

    // Fallback to offline queries
    List<Anime> filtered = List<Anime>.from(_fallbackAnimeList);
    if (query.trim().isNotEmpty) {
      final searchLower = query.toLowerCase().trim();
      filtered = filtered
          .where((anime) => anime.title.toLowerCase().contains(searchLower))
          .toList();
    }
    if (genre != 'All') {
      filtered = filtered
          .where((anime) => anime.genres.contains(genre))
          .toList();
    }
    _sortAnimeList(filtered, sortBy, query);
    return _preserveMetadataResults(filtered);
  }

  Future<List<Anime>> _firstNonEmptyAnimeList(
    List<Future<List<Anime>>> requests,
  ) {
    if (requests.isEmpty) return Future.value(const <Anime>[]);

    final completer = Completer<List<Anime>>();
    var remaining = requests.length;

    for (final request in requests) {
      request
          .then(
            (result) {
              if (!completer.isCompleted && result.isNotEmpty) {
                completer.complete(result);
              }
            },
            onError: (Object _, StackTrace _) {
              // A failed source is equivalent to an empty result. The other source
              // can still complete the Browse page.
            },
          )
          .whenComplete(() {
            remaining--;
            if (remaining == 0 && !completer.isCompleted) {
              completer.complete(const <Anime>[]);
            }
          });
    }

    return completer.future;
  }

  void _sortAnimeList(List<Anime> list, String sortBy, String query) {
    if (sortBy == 'Rating') {
      list.sort((a, b) => b.rating.compareTo(a.rating));
    } else if (sortBy == 'A-Z') {
      list.sort((a, b) => a.title.compareTo(b.title));
    } else if (sortBy == 'Latest') {
      list.sort((a, b) => b.year.compareTo(a.year));
    } else if (query.trim().isNotEmpty) {
      final queryLower = query.trim().toLowerCase();
      int relevance(Anime anime) {
        final title = anime.title.toLowerCase();
        if (title == queryLower) return 0;
        if (title.startsWith(queryLower)) return 1;
        if (title.contains(queryLower)) return 2;
        return 3;
      }

      list.sort((a, b) {
        final rank = relevance(a).compareTo(relevance(b));
        if (rank != 0) return rank;
        return b.rating.compareTo(a.rating);
      });
    }
    // Preserve the catalog's trending order when no explicit sort is selected.
  }

  Future<List<Anime>> _searchViaAniwingsApi(
    String query,
    String genre,
    String sortBy,
  ) async {
    try {
      final decoded = await _getJsonObject(
        _aniwingsApiUri('/api/search', {'q': query.trim()}),
        timeout: const Duration(seconds: 8),
      );
      final data = decoded?['data'];
      List<dynamic>? results;
      if (data is List) {
        results = data;
      } else if (data is Map<String, dynamic>) {
        results = data['results'] as List<dynamic>?;
      } else {
        results = decoded?['results'] as List<dynamic>?;
      }
      if (results != null && results.isNotEmpty) {
        return results
            .whereType<Map<String, dynamic>>()
            .map(_parseAniwingsApiAnime)
            .where((anime) => anime.id != 'unknown')
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Anime>> _searchViaJikan(
    String query,
    String genre,
    String sortBy,
  ) async {
    final queryParams = <String, String>{'limit': '24', 'sfw': 'true'};
    if (query.trim().isNotEmpty) {
      queryParams['q'] = query.trim();
    }

    final genreIds = {
      'Action': '1',
      'Adventure': '2',
      'Comedy': '4',
      'Drama': '8',
      'Fantasy': '10',
      'Romance': '22',
      'Sci-Fi': '24',
      'Slice of Life': '36',
      'Supernatural': '37',
      'Thriller': '41',
      'Mystery': '7',
      'Horror': '14',
      'Sports': '30',
      'Mecha': '18',
      'Isekai': '62',
      'Historical': '13',
    };

    if (genre != 'All' && genreIds.containsKey(genre)) {
      queryParams['genres'] = genreIds[genre]!;
    }

    if (sortBy == 'Rating') {
      queryParams['order_by'] = 'score';
      queryParams['sort'] = 'desc';
    } else if (sortBy == 'Latest') {
      queryParams['order_by'] = 'start_date';
      queryParams['sort'] = 'desc';
    } else if (sortBy == 'A-Z') {
      queryParams['order_by'] = 'title';
      queryParams['sort'] = 'asc';
    } else {
      queryParams['order_by'] = 'popularity';
      queryParams['sort'] = 'asc';
    }

    try {
      final decoded = await _getJsonObject(_jikanUri('anime', queryParams));
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        return data.map((item) => _parseJikanAnime(item)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Anime>> _searchViaAniList(String query) async {
    const gqlQuery = r'''
      query ($search: String) {
        Page (page: 1, perPage: 20) {
          media (search: $search, type: ANIME, isAdult: false, format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            tags { name }
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
          }
        }
      }
    ''';
    try {
      final response = await _client
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query': gqlQuery,
              'variables': {'search': query.trim()},
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = decoded['data']?['Page']?['media'] as List?;
        if (list != null) {
          return list
              .whereType<Map<String, dynamic>>()
              .map((item) => parseAniListMedia(item))
              .where((anime) => anime.id != 'unknown')
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<List<Anime>> _searchViaAniListGenreSort(
    String genre,
    String sortBy,
  ) async {
    const gqlQuery = r'''
      query ($page: Int, $perPage: Int, $genre: String, $tag: String, $sort: [MediaSort]) {
        Page (page: $page, perPage: $perPage) {
          media (genre: $genre, tag: $tag, sort: $sort, type: ANIME, isAdult: false, format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            tags { name }
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
            description
          }
        }
      }
    ''';

    final variables = <String, dynamic>{'page': 1, 'perPage': 24};

    if (genre != 'All') {
      final isTag = genre == 'Isekai' || genre == 'Historical';
      if (isTag) {
        variables['tag'] = genre;
      } else {
        variables['genre'] = genre;
      }
    }

    if (sortBy == 'Rating') {
      variables['sort'] = ['SCORE_DESC', 'POPULARITY_DESC'];
    } else if (sortBy == 'Latest') {
      variables['sort'] = ['START_DATE_DESC'];
    } else if (sortBy == 'A-Z') {
      variables['sort'] = ['TITLE_ROMAJI'];
    } else {
      // Trending/Popularity
      variables['sort'] = ['TRENDING_DESC', 'POPULARITY_DESC'];
    }

    try {
      final response = await _client
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'query': gqlQuery, 'variables': variables}),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = decoded['data']?['Page']?['media'] as List?;
        if (list != null) {
          return list
              .whereType<Map<String, dynamic>>()
              .map((item) => parseAniListMedia(item))
              .where((anime) => anime.id != 'unknown')
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  // Memory cache operations
  void addAnimeToMemoryCache(Anime anime) {
    _memoryCache[anime.id] = anime;
  }

  Anime parseMalAnime(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final title = item['title'] as String? ?? 'Unknown Title';
    final description =
        item['synopsis'] as String? ?? 'No description available.';
    final posterUrl =
        item['main_picture']?['large'] as String? ??
        item['main_picture']?['medium'] as String? ??
        '';
    final backdropUrl = posterUrl;

    final mean = (item['mean'] as num?)?.toDouble() ?? 8.0;
    final rating = (mean / 2.0).clamp(1.0, 5.0);

    final malStatus = item['status'] as String? ?? '';
    final status = _mapStatus(malStatus);

    final genresList =
        (item['genres'] as List?)?.map((g) => g['name'] as String).toList() ??
        ['Action'];

    final totalEpisodes = item['num_episodes'] as int? ?? 12;

    final year =
        item['start_season']?['year']?.toString() ??
        item['start_date']?.toString().split('-').first ??
        '2023';
    final averageEpisodeSeconds = (item['average_episode_duration'] as num?)
        ?.toDouble();
    final episodeDurationMinutes =
        averageEpisodeSeconds != null && averageEpisodeSeconds > 0
        ? (averageEpisodeSeconds / 60).round()
        : 24;

    return Anime(
      id: id,
      title: title,
      description: description,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      rating: rating,
      status: status,
      genres: genresList.isEmpty ? ['Action'] : genresList,
      totalEpisodes: totalEpisodes,
      year: year,
      episodeDurationMinutes: episodeDurationMinutes,
      malId: id,
      alternativeTitles: _titleAliases([
        item['title'],
        item['alternative_titles']?['en'],
        ...(item['alternative_titles']?['synonyms'] as List? ?? const []),
      ]),
    );
  }

  Anime parseMalLoadJsonAnime(Map<String, dynamic> item) {
    final id = item['anime_id'].toString();
    final title =
        item['anime_title_eng'] as String? ??
        item['anime_title'] as String? ??
        'Unknown Title';
    final description =
        'No description available.'; // load.json does not contain synopsis
    final posterUrl = item['anime_image_path'] as String? ?? '';
    final backdropUrl = posterUrl;

    final mean = (item['anime_score_val'] as num?)?.toDouble() ?? 8.0;
    final rating = (mean / 2.0).clamp(1.0, 5.0);

    final airStatusInt = item['anime_airing_status'] as int? ?? 2;
    String airStatusStr = 'finished_airing';
    if (airStatusInt == 1) airStatusStr = 'currently_airing';
    if (airStatusInt == 3) airStatusStr = 'not_yet_aired';
    final status = _mapStatus(airStatusStr);

    final genresList =
        (item['genres'] as List?)?.map((g) => g['name'] as String).toList() ??
        ['Action'];

    final totalEpisodes = item['anime_num_episodes'] as int? ?? 12;

    String year = '2023';
    final dateStr = item['anime_start_date_string'] as String?;
    if (dateStr != null && dateStr.isNotEmpty) {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final yy = parts[2];
        if (yy.length == 2) {
          final val = int.tryParse(yy) ?? 0;
          year = val > 50 ? '19$yy' : '20$yy';
        } else {
          year = yy;
        }
      } else {
        year = dateStr.split('-').first;
      }
    }

    return Anime(
      id: id,
      title: title,
      description: description,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      rating: rating,
      status: status,
      genres: genresList.isEmpty ? ['Action'] : genresList,
      totalEpisodes: totalEpisodes,
      year: year,
      episodeDurationMinutes: 24,
      malId: id,
      alternativeTitles: _titleAliases([
        item['anime_title_eng'],
        item['anime_title'],
      ]),
    );
  }

  Anime parseAniListMedia(Map<String, dynamic> media) {
    final malId = media['idMal']?.toString();
    final aniId = media['id']?.toString() ?? 'unknown';
    final id = (malId != null && malId != 'null' && malId.isNotEmpty)
        ? malId
        : aniId == 'unknown'
        ? 'unknown'
        : 'ani:$aniId';
    final titleObj = media['title'];
    final title =
        titleObj?['english'] as String? ??
        titleObj?['romaji'] as String? ??
        'Unknown Title';
    final description =
        media['description'] as String? ?? 'No description available.';
    final posterUrl =
        media['coverImage']?['extraLarge'] as String? ??
        media['coverImage']?['large'] as String? ??
        media['coverImage']?['medium'] as String? ??
        '';
    final backdropUrl = media['bannerImage'] as String? ?? posterUrl;

    final score = (media['averageScore'] as num?)?.toDouble() ?? 80.0;
    final rating = (score / 20.0).clamp(1.0, 5.0);

    final aniStatus = media['status'] as String? ?? '';
    final status = _mapStatus(aniStatus);

    final genresList =
        (media['genres'] as List?)?.map((g) => g as String).toList() ?? [];
    final tagsList =
        (media['tags'] as List?)
            ?.map((t) => (t as Map<String, dynamic>)['name'] as String)
            .toList() ??
        [];
    final mergedGenres = [...genresList, ...tagsList];
    final totalEpisodes = (media['episodes'] as num?)?.toInt() ?? 0;
    final year =
        media['seasonYear']?.toString() ??
        media['startDate']?['year']?.toString() ??
        '2023';
    final format = media['format'] as String? ?? 'TV';

    String? nextEpisodeDate;
    final startDate = media['startDate'] as Map<String, dynamic>?;
    if (startDate != null && startDate['year'] != null) {
      final y = startDate['year'];
      final m = startDate['month'];
      final d = startDate['day'];
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      if (m != null && d != null) {
        final monthStr = (m is int && m >= 1 && m <= 12) ? months[m - 1] : '$m';
        nextEpisodeDate = '$monthStr $d, $y';
      } else if (m != null) {
        final monthStr = (m is int && m >= 1 && m <= 12) ? months[m - 1] : '$m';
        nextEpisodeDate = '$monthStr $y';
      } else {
        nextEpisodeDate = '$y';
      }
    }
    final nextAiringEpisode =
        media['nextAiringEpisode'] as Map<String, dynamic>?;
    if (nextAiringEpisode != null && nextAiringEpisode['airingAt'] != null) {
      final airingAt = (nextAiringEpisode['airingAt'] as num?)?.toInt();
      if (airingAt != null && airingAt > 0) {
        final date = DateTime.fromMillisecondsSinceEpoch(
          airingAt * 1000,
        ).toLocal();
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        nextEpisodeDate = '${months[date.month - 1]} ${date.day}, ${date.year}';
      }
    }

    return Anime(
      id: id,
      title: title,
      description: description,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      rating: rating,
      status: status,
      genres: mergedGenres.isEmpty ? ['Action'] : mergedGenres,
      totalEpisodes: totalEpisodes,
      year: year,
      episodeDurationMinutes: _parseDurationMinutes(media['duration']),
      type: format,
      nextEpisodeDate: nextEpisodeDate,
      malId: malId != null && malId != 'null' && malId.isNotEmpty
          ? malId
          : null,
      aniListId: aniId != 'unknown' ? aniId : null,
      alternativeTitles: _titleAliases([
        titleObj?['english'],
        titleObj?['romaji'],
        titleObj?['native'],
        titleObj?['userPreferred'],
      ]),
    );
  }

  Future<Anime?> _cacheAvailableAnime(
    Anime anime, {
    bool persist = true,
  }) async {
    _cacheAnime(anime);
    if (persist && storage != null) {
      unawaited(storage!.saveAnimeToCache(anime));
      if (metadataProvider != null) {
        unawaited(
          storage!.saveProviderCachedAnime(metadataProvider!.name, anime),
        );
      }
    }
    return anime;
  }

  // Get anime details by ID from cache, AniWings API, Jikan, MAL, or storage.
  Future<Anime?> getAnimeById(String id) async {
    final cleanId = _rawAnimeId(id);
    if (metadataProvider != null) {
      final cached =
          _memoryCache[cleanId] ??
          storage?.getProviderCachedAnime(metadataProvider!.name, cleanId);
      if (cached != null) return _cacheAvailableAnime(cached, persist: false);
      final pending = _animeDetailsInFlight[cleanId];
      if (pending != null) return pending;
      final request = _loadSelectedMetadata(cleanId);
      _animeDetailsInFlight[cleanId] = request;
      try {
        return await request;
      } finally {
        _animeDetailsInFlight.remove(cleanId);
      }
    }
    if (_memoryCache.containsKey(cleanId)) {
      final cached = _memoryCache[cleanId];
      if (cached != null) return _cacheAvailableAnime(cached, persist: false);
    }
    if (_memoryCache.containsKey(id)) {
      final cached = _memoryCache[id];
      if (cached != null) return _cacheAvailableAnime(cached, persist: false);
    }

    if (storage != null) {
      final cached =
          storage!.getCachedAnimeById(cleanId) ??
          storage!.getCachedAnimeById(id);
      if (cached != null) return _cacheAvailableAnime(cached, persist: false);
    }

    final pending = _animeDetailsInFlight[cleanId] ?? _animeDetailsInFlight[id];
    if (pending != null) return pending;

    final request = _loadAnimeById(cleanId);
    _animeDetailsInFlight[cleanId] = request;
    _animeDetailsInFlight[id] = request;
    try {
      return await request;
    } finally {
      if (identical(_animeDetailsInFlight[cleanId], request)) {
        _animeDetailsInFlight.remove(cleanId);
      }
      if (identical(_animeDetailsInFlight[id], request)) {
        _animeDetailsInFlight.remove(id);
      }
    }
  }

  Future<Anime?> _loadAnimeById(String id) async {
    final cleanId = _rawAnimeId(id);
    final memoryCached = _memoryCache[cleanId] ?? _memoryCache[id];
    if (memoryCached != null) {
      return _cacheAvailableAnime(memoryCached, persist: false);
    }
    if (storage != null) {
      final cached =
          storage!.getCachedAnimeById(cleanId) ??
          storage!.getCachedAnimeById(id);
      if (cached != null) {
        return _cacheAvailableAnime(cached, persist: false);
      }
    }

    try {
      final data = await _getAniwingsApiInfoData(cleanId);
      if (data != null) {
        var anime = _parseAniwingsApiAnime(data);
        try {
          final aniData = await getAniListData(cleanId);
          if (aniData != null) {
            final aniAnime = parseAniListMedia(aniData);
            anime = anime.copyWith(
              posterUrl: aniAnime.posterUrl,
              backdropUrl: aniAnime.backdropUrl,
            );
          }
        } catch (_) {}

        return _cacheAvailableAnime(anime);
      }
    } catch (_) {}

    try {
      final data = await getAniListData(cleanId);
      if (data != null) {
        final anime = parseAniListMedia(data);
        final finalAnime = anime.id == 'unknown'
            ? Anime(
                id: cleanId,
                title: anime.title,
                description: anime.description,
                posterUrl: anime.posterUrl,
                backdropUrl: anime.backdropUrl,
                rating: anime.rating,
                status: anime.status,
                genres: anime.genres,
                totalEpisodes: anime.totalEpisodes,
                year: anime.year,
                episodeDurationMinutes: anime.episodeDurationMinutes,
              )
            : anime;
        return _cacheAvailableAnime(finalAnime);
      }
    } catch (_) {}

    try {
      final data = await _getJikanFullData(cleanId);
      if (data != null) {
        final anime = _parseJikanAnime(data);
        return _cacheAvailableAnime(anime);
      }
    } catch (_) {}

    final fallbackAnime = _fallbackAnimeById(cleanId) ?? _fallbackAnimeById(id);
    if (fallbackAnime != null) {
      return _cacheAvailableAnime(fallbackAnime, persist: false);
    }

    return null;
  }

  Future<Anime?> _loadSelectedMetadata(String id) async {
    if (metadataProvider == MetadataProvider.aniList) {
      final data = await getAniListData(id);
      return data == null
          ? null
          : _cacheAvailableAnime(parseAniListMedia(data));
    }
    var malId = id;
    if (id.startsWith('ani:')) {
      final data = await getAniListData(id);
      malId = data?['idMal']?.toString() ?? '';
    }
    if (int.tryParse(malId) == null) return null;
    final data = await _getJikanFullData(malId);
    return data == null ? null : _cacheAvailableAnime(_parseJikanAnime(data));
  }

  // Fetch full metadata, characters, and streaming episode data from AniList
  // Fetch full metadata, characters, and streaming episode data from AniList
  Future<Map<String, dynamic>?> _fetchAniListData(String animeId) async {
    final cleanId = _rawAnimeId(animeId);
    final known = _memoryCache[cleanId] ?? storage?.getCachedAnimeById(cleanId);
    final explicitAni = cleanId.startsWith('ani:');
    final useAni =
        explicitAni || (known?.malId == cleanId && known?.aniListId != null);
    final idVal = int.tryParse(
      explicitAni
          ? cleanId.substring(4)
          : useAni
          ? known!.aniListId!
          : cleanId,
    );
    if (idVal == null) return null;

    const query = r'''
      query ($id: Int, $byMal: Boolean!, $byAni: Boolean!) {
        mediaByMalId: Media(idMal: $id, type: ANIME) @include(if: $byMal) {
          id idMal title { romaji english native userPreferred }
          coverImage { extraLarge large medium } bannerImage averageScore status genres episodes seasonYear startDate { year month day } duration description
          nextAiringEpisode { episode airingAt }
          airingSchedule(notYetAired: false, page: 1, perPage: 100) { nodes { episode airingAt } }
          streamingEpisodes { title thumbnail }
          characters(sort: [ROLE, RELEVANCE], perPage: 12) { edges { role node { name { full } image { large } } } }
          relations { edges { relationType node { id idMal title { romaji english userPreferred } type coverImage { medium large } } } }
          tags { name rank isMediaSpoiler }
        }
        mediaById: Media(id: $id, type: ANIME) @include(if: $byAni) {
          id idMal title { romaji english native userPreferred }
          coverImage { extraLarge large medium } bannerImage averageScore status genres episodes seasonYear startDate { year month day } duration description
          nextAiringEpisode { episode airingAt }
          airingSchedule(notYetAired: false, page: 1, perPage: 100) { nodes { episode airingAt } }
          streamingEpisodes { title thumbnail }
          characters(sort: [ROLE, RELEVANCE], perPage: 12) { edges { role node { name { full } image { large } } } }
          relations { edges { relationType node { id idMal title { romaji english userPreferred } type coverImage { medium large } } } }
          tags { name rank isMediaSpoiler }
        }
      }
    ''';

    try {
      final response = await _client
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query': query,
              'variables': {'id': idVal, 'byMal': !useAni, 'byAni': useAni},
            }),
          )
          .timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded['data'] as Map<String, dynamic>?;
        if (data != null) {
          final mediaByMalId = data['mediaByMalId'] as Map<String, dynamic>?;
          final mediaById = data['mediaById'] as Map<String, dynamic>?;
          if (!useAni &&
              mediaByMalId != null &&
              mediaByMalId['idMal']?.toString() == cleanId) {
            return mediaByMalId;
          }
          if (useAni &&
              mediaById != null &&
              mediaById['id']?.toString() == idVal.toString()) {
            return mediaById;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getAniListData(String animeId) async {
    final cleanId = _rawAnimeId(animeId);
    if (_anilistCache.containsKey(cleanId)) {
      return _anilistCache[cleanId];
    }
    if (_anilistCache.containsKey(animeId)) {
      return _anilistCache[animeId];
    }

    final pending = _anilistInFlight[cleanId] ?? _anilistInFlight[animeId];
    if (pending != null) return pending;

    final request = _fetchAniListData(cleanId);
    _anilistInFlight[cleanId] = request;
    _anilistInFlight[animeId] = request;
    try {
      final data = await request;
      if (data != null) {
        _anilistCache[cleanId] = data;
        _anilistCache[animeId] = data;
        final malId = data['idMal']?.toString();
        final aniId = data['id']?.toString();
        if (malId != null && malId.isNotEmpty) _anilistCache[malId] = data;
        if (aniId != null && aniId.isNotEmpty) {
          _anilistCache['ani:$aniId'] = data;
        }
      }
      return data;
    } finally {
      if (identical(_anilistInFlight[cleanId], request)) {
        _anilistInFlight.remove(cleanId);
      }
      if (identical(_anilistInFlight[animeId], request)) {
        _anilistInFlight.remove(animeId);
      }
    }
  }

  // Get characters for an anime from AniList (primary) or Jikan v4 (fallback)
  Future<Map<String, dynamic>?> getMetadataExtraInfo(String id) async {
    if (metadataProvider != MetadataProvider.myAnimeList) {
      return getAniListData(id);
    }
    final anime = await getAnimeById(id);
    if (anime?.malId == null) return null;
    final data = await _getJikanFullData(anime!.malId!);
    if (data == null) return null;
    final edges = <Map<String, dynamic>>[];
    for (final relation in data['relations'] as List? ?? const []) {
      if (relation is! Map) continue;
      for (final entry in relation['entry'] as List? ?? const []) {
        if (entry is! Map || entry['type'] != 'anime') continue;
        edges.add({
          'relationType': relation['relation']
              ?.toString()
              .toUpperCase()
              .replaceAll(' ', '_'),
          'node': {
            'idMal': entry['mal_id'],
            'type': 'ANIME',
            'title': {'userPreferred': entry['name']},
          },
        });
      }
    }
    return {
      'description': data['synopsis'],
      'relations': {'edges': edges},
    };
  }

  Future<List<Character>> getCharactersForAnime(String animeId) async {
    var cleanId = _rawAnimeId(animeId);
    if (metadataProvider == MetadataProvider.myAnimeList &&
        cleanId.startsWith('ani:')) {
      cleanId = (await getAnimeById(cleanId))?.malId ?? '';
      if (cleanId.isEmpty) return [];
    }
    // 1. Try AniList first
    final aniListData = metadataProvider == MetadataProvider.myAnimeList
        ? null
        : await getAniListData(cleanId);
    if (aniListData != null) {
      final charEdges = aniListData['characters']?['edges'] as List?;
      if (charEdges != null && charEdges.isNotEmpty) {
        return charEdges.map<Character>((edge) {
          final role = edge['role'] as String? ?? 'Supporting';
          final node = edge['node'] as Map<String, dynamic>? ?? {};
          final name = node['name']?['full'] as String? ?? 'Unknown';
          final imageUrl = node['image']?['large'] as String? ?? '';
          return Character(
            name: name,
            role: role == 'MAIN' ? 'Protagonist' : 'Supporting',
            imageUrl: imageUrl,
          );
        }).toList();
      }
    }

    // 2. Try Jikan API fallback
    try {
      final decoded = await _getJsonObject(
        _jikanUri('anime/$cleanId/characters'),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        return data.take(12).map<Character>((item) {
          final role = item['role'] as String? ?? 'Supporting';
          final charObj = item['character'] as Map<String, dynamic>? ?? {};
          final name = charObj['name'] as String? ?? 'Unknown';
          final imageUrl =
              charObj['images']?['jpg']?['image_url'] as String? ?? '';
          return Character(
            name: name,
            role: role == 'Main' ? 'Protagonist' : 'Supporting',
            imageUrl: imageUrl,
          );
        }).toList();
      }
    } catch (_) {}

    return [];
  }

  bool _isEpisodeCacheFresh(String animeId) {
    final cachedAt = _episodesCacheTime[animeId];
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) < const Duration(minutes: 30);
  }

  int? _parseEpisodeNumberFromTitle(String title) {
    final regex = RegExp(r'(?:episode|ep|ep\.)\s*(\d+)', caseSensitive: false);
    final match = regex.firstMatch(title);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  Map<int, Map<String, dynamic>> _streamingEpisodeMap(Object? rawEpisodes) {
    final result = <int, Map<String, dynamic>>{};
    if (rawEpisodes is! List || rawEpisodes.isEmpty) return result;

    for (var i = 0; i < rawEpisodes.length; i++) {
      final rawItem = rawEpisodes[i];
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final title = item['title']?.toString() ?? '';
      final parsedNumber = _parseEpisodeNumberFromTitle(title);
      if (metadataProvider == MetadataProvider.aniList &&
          parsedNumber == null) {
        continue;
      }
      final episodeNumber = parsedNumber ?? (i + 1);
      result[episodeNumber] = item;
    }

    return result;
  }

  Map<int, DateTime> _releasedAiringScheduleMap(Object? rawSchedule) {
    final result = <int, DateTime>{};
    final nodes = rawSchedule is Map ? rawSchedule['nodes'] : null;
    if (nodes is! List || nodes.isEmpty) return result;

    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final rawNode in nodes) {
      if (rawNode is! Map) continue;
      final episode = (rawNode['episode'] as num?)?.toInt();
      final airingAt = (rawNode['airingAt'] as num?)?.toInt();
      if (episode == null || episode <= 0 || airingAt == null) continue;
      if (airingAt > nowSeconds) continue;
      result[episode] = DateTime.fromMillisecondsSinceEpoch(
        airingAt * 1000,
      ).toLocal();
    }

    return result;
  }

  int _maxEpisodeNumber(Iterable<Episode> episodes) {
    var maxEpisode = 0;
    for (final episode in episodes) {
      if (episode.episodeNumber > maxEpisode) {
        maxEpisode = episode.episodeNumber;
      }
    }
    return maxEpisode;
  }

  int _releasedEpisodeCount({
    required Anime? anime,
    required Map<String, dynamic>? aniData,
    required List<Episode> existingEpisodes,
  }) {
    var releasedCount = _maxEpisodeNumber(existingEpisodes);

    final streamingEpisodes = _streamingEpisodeMap(
      aniData?['streamingEpisodes'],
    );
    if (streamingEpisodes.isNotEmpty) {
      final streamingMax = streamingEpisodes.keys.reduce(math.max);
      releasedCount = math.max(releasedCount, streamingMax);
    }

    final schedule = _releasedAiringScheduleMap(aniData?['airingSchedule']);
    if (schedule.isNotEmpty) {
      final scheduleMax = schedule.keys.reduce(math.max);
      releasedCount = math.max(releasedCount, scheduleMax);
    }

    final nextEpisode = (aniData?['nextAiringEpisode']?['episode'] as num?)
        ?.toInt();
    if (nextEpisode != null && nextEpisode > 1) {
      releasedCount = math.max(releasedCount, nextEpisode - 1);
    }

    final aniListTotalEpisodes = (aniData?['episodes'] as num?)?.toInt() ?? 0;
    final totalEpisodes = aniListTotalEpisodes > 0
        ? aniListTotalEpisodes
        : anime?.status == 'Completed'
        ? anime?.totalEpisodes ?? 0
        : 0;
    if (totalEpisodes > 0) {
      releasedCount = releasedCount.clamp(0, totalEpisodes).toInt();
    }

    return releasedCount;
  }

  List<Episode> _ensureReleasedEpisodeRows({
    required String animeId,
    required Anime? anime,
    required Map<String, dynamic>? aniData,
    required List<Episode> episodes,
    required Duration episodeDuration,
  }) {
    final releasedCount = _releasedEpisodeCount(
      anime: anime,
      aniData: aniData,
      existingEpisodes: episodes,
    );
    if (releasedCount <= 0) return episodes;

    final byNumber = <int, Episode>{};
    for (final episode in episodes) {
      byNumber[episode.episodeNumber] = episode;
    }

    final streamingEpisodes = _streamingEpisodeMap(
      aniData?['streamingEpisodes'],
    );
    final airingDates = _releasedAiringScheduleMap(aniData?['airingSchedule']);
    final now = DateTime.now();

    for (var number = 1; number <= releasedCount; number++) {
      if (byNumber.containsKey(number)) continue;

      final streamingEpisode = streamingEpisodes[number];
      final title =
          streamingEpisode?['title']?.toString().trim().isNotEmpty == true
          ? streamingEpisode!['title'].toString().trim()
          : 'Episode $number';
      final thumbnail = streamingEpisode?['thumbnail']?.toString().trim();
      final airDate =
          airingDates[number] ??
          now.subtract(Duration(days: (releasedCount - number) * 7));

      byNumber[number] = Episode(
        id: '${animeId}_ep_$number',
        animeId: animeId,
        episodeNumber: number,
        title: title,
        thumbnailUrl: thumbnail?.isNotEmpty == true ? thumbnail : null,
        airDate: airDate,
        duration: episodeDuration,
        videoUrls: _mockVideoUrls,
      );
    }

    final fixedEpisodes = byNumber.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return fixedEpisodes;
  }

  // Get all episodes for an anime (fetched from Jikan, AniList, or generated locally)
  Future<List<Episode>> getEpisodesForAnime(String animeId) async {
    final cleanId = _rawAnimeId(animeId);
    if (_episodesCache.containsKey(cleanId) && _isEpisodeCacheFresh(cleanId)) {
      final cached = _episodesCache[cleanId];
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }
    if (_episodesCache.containsKey(animeId) && _isEpisodeCacheFresh(animeId)) {
      final cached = _episodesCache[animeId];
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    final persisted =
        storage?.getCachedEpisodes(_cacheKey(cleanId)) ??
        storage?.getCachedEpisodes(_cacheKey(animeId));
    if (persisted != null && persisted.isNotEmpty) {
      _episodesCache[cleanId] = persisted;
      _episodesCache[animeId] = persisted;
      _episodesCacheTime[cleanId] = DateTime.now();
      _episodesCacheTime[animeId] = DateTime.now();
      return persisted;
    }

    final pending = _episodesInFlight[cleanId] ?? _episodesInFlight[animeId];
    if (pending != null) return pending;

    final request = _loadEpisodesForAnime(cleanId);
    _episodesInFlight[cleanId] = request;
    _episodesInFlight[animeId] = request;
    try {
      return await request;
    } finally {
      if (identical(_episodesInFlight[cleanId], request)) {
        _episodesInFlight.remove(cleanId);
      }
      if (identical(_episodesInFlight[animeId], request)) {
        _episodesInFlight.remove(animeId);
      }
    }
  }

  Future<List<Episode>> _loadEpisodesForAnime(String animeId) async {
    final cleanId = _rawAnimeId(animeId);
    if (_episodesCache.containsKey(cleanId) && _isEpisodeCacheFresh(cleanId)) {
      final cached = _episodesCache[cleanId];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final metadata = await Future.wait<dynamic>([
      metadataProvider == MetadataProvider.myAnimeList
          ? Future<Map<String, dynamic>?>.value(null)
          : getAniListData(cleanId),
      getAnimeById(cleanId),
    ]);
    final aniData = metadata[0] as Map<String, dynamic>?;
    final anime = metadata[1] as Anime?;
    final liveStatus = _mapStatus(aniData?['status'] as String? ?? '');
    final hasReleasedLiveEpisodes =
        _releasedEpisodeCount(
          anime: anime,
          aniData: aniData,
          existingEpisodes: const [],
        ) >
        0;
    if (anime != null &&
        anime.status == 'Upcoming' &&
        liveStatus != 'Releasing' &&
        !hasReleasedLiveEpisodes) {
      _episodesCache[cleanId] = [];
      _episodesCache[animeId] = [];
      _episodesCacheTime[cleanId] = DateTime.now();
      _episodesCacheTime[animeId] = DateTime.now();
      return [];
    }

    if (metadataProvider == MetadataProvider.aniList) {
      final streaming = _streamingEpisodeMap(aniData?['streamingEpisodes']);
      final airing = _releasedAiringScheduleMap(aniData?['airingSchedule']);
      final released = _releasedEpisodeCount(
        anime: anime,
        aniData: aniData,
        existingEpisodes: const [],
      );
      final count = anime?.status == 'Completed'
          ? math.max(released, anime?.totalEpisodes ?? 0)
          : released;
      final result = List.generate(count, (index) {
        final number = index + 1;
        final item = streaming[number];
        return Episode(
          id: '${cleanId}_ep_$number',
          animeId: cleanId,
          episodeNumber: number,
          title: item?['title']?.toString() ?? 'Episode $number',
          thumbnailUrl: item?['thumbnail']?.toString(),
          airDate: airing[number] ?? DateTime.now(),
          duration: Duration(minutes: anime?.episodeDurationMinutes ?? 24),
          videoUrls: const [],
        );
      });
      _episodesCache[cleanId] = result;
      _episodesCacheTime[cleanId] = DateTime.now();
      if (storage != null && result.isNotEmpty) {
        await storage!.saveEpisodesToCache(_cacheKey(cleanId), result);
      }
      return result;
    }

    // Resolve MAL ID if animeId is an AniList ID
    String malId = cleanId;
    final idMalFromAni = aniData?['idMal']?.toString();
    if (idMalFromAni != null &&
        idMalFromAni.isNotEmpty &&
        idMalFromAni != 'null') {
      malId = idMalFromAni;
    } else if (anime?.malId != null && anime!.malId!.isNotEmpty) {
      malId = anime.malId!;
    } else if (anime != null &&
        anime.id.isNotEmpty &&
        anime.id != 'unknown' &&
        (int.tryParse(anime.id) ?? 0) < 100000) {
      malId = anime.id;
    }

    List<Episode> episodes = [];
    final episodeDuration = Duration(
      minutes: anime?.episodeDurationMinutes ?? 24,
    );

    try {
      var page = 1;
      var hasNextPage = true;
      while (hasNextPage) {
        final decoded = await _getJsonObject(
          _jikanUri('anime/$malId/episodes', {'page': page.toString()}),
        );
        final data = decoded?['data'] as List?;
        if (data != null && data.isNotEmpty) {
          episodes.addAll(
            data.map((item) {
              final epNum = item['mal_id'] as int? ?? 1;
              final title = item['title'] as String? ?? 'Episode $epNum';
              final airDateStr = item['aired'] as String?;
              final airDate = airDateStr != null
                  ? DateTime.tryParse(airDateStr) ?? DateTime.now()
                  : DateTime.now();

              return Episode(
                id: '${animeId}_ep_$epNum',
                animeId: animeId,
                episodeNumber: epNum,
                title: title,
                airDate: airDate,
                duration: episodeDuration,
                videoUrls: _mockVideoUrls,
              );
            }),
          );
        }

        final pagination = decoded?['pagination'] as Map<String, dynamic>?;
        hasNextPage = pagination?['has_next_page'] == true;
        page += 1;
      }
    } catch (_) {}

    // Fallback 1: try AniList API for episode list if Jikan returned nothing
    if (episodes.isEmpty) {
      try {
        if (aniData != null) {
          final streamingEpisodes = aniData['streamingEpisodes'] as List?;
          if (streamingEpisodes != null && streamingEpisodes.isNotEmpty) {
            episodes = streamingEpisodes.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final rawTitle = item['title'] as String? ?? 'Episode ${idx + 1}';
              final epNum = _parseEpisodeNumberFromTitle(rawTitle) ?? (idx + 1);
              final thumbnail = item['thumbnail'] as String? ?? '';
              return Episode(
                id: '${animeId}_ep_$epNum',
                animeId: animeId,
                episodeNumber: epNum,
                title: rawTitle,
                thumbnailUrl: thumbnail.isNotEmpty ? thumbnail : null,
                airDate: DateTime.now(),
                duration: episodeDuration,
                videoUrls: _mockVideoUrls,
              );
            }).toList();
          }
        }
      } catch (_) {}
    }

    // Ensure all episodes up to totalEpisodes or releasedCount are populated
    final releasedTarget = _releasedEpisodeCount(
      anime: anime,
      aniData: aniData,
      existingEpisodes: episodes,
    );
    final count = metadataProvider != null && anime?.status != 'Completed'
        ? metadataProvider == MetadataProvider.myAnimeList
              ? _maxEpisodeNumber(episodes)
              : releasedTarget
        : math.max(releasedTarget, anime?.totalEpisodes ?? 0);
    if (count > episodes.length) {
      final existingEpNumbers = episodes.map((e) => e.episodeNumber).toSet();
      final now = DateTime.now();
      for (var i = 1; i <= count; i++) {
        if (!existingEpNumbers.contains(i)) {
          episodes.add(
            Episode(
              id: '${animeId}_ep_$i',
              animeId: animeId,
              episodeNumber: i,
              title: 'Episode $i',
              airDate: now.subtract(Duration(days: (count - i) * 7)),
              duration: episodeDuration,
              videoUrls: _mockVideoUrls,
            ),
          );
        }
      }
      episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }

    // Enrich episodes with AniList thumbnails
    try {
      if (aniData != null) {
        final streamingEpisodes = aniData['streamingEpisodes'] as List?;
        if (streamingEpisodes != null && streamingEpisodes.isNotEmpty) {
          final thumbnailMap = <int, String>{};
          for (var item in streamingEpisodes) {
            final title = item['title'] as String? ?? '';
            final thumbnail = item['thumbnail'] as String?;
            if (thumbnail != null && thumbnail.isNotEmpty) {
              final num = _parseEpisodeNumberFromTitle(title);
              if (num != null) {
                thumbnailMap[num] = thumbnail;
              }
            }
          }

          final useSequential = thumbnailMap.isEmpty;

          for (var i = 0; i < episodes.length; i++) {
            final ep = episodes[i];
            String? thumbnail;
            if (useSequential) {
              if (i < streamingEpisodes.length) {
                thumbnail = streamingEpisodes[i]['thumbnail'] as String?;
              }
            } else {
              thumbnail = thumbnailMap[ep.episodeNumber];
            }

            if (thumbnail != null && thumbnail.isNotEmpty) {
              episodes[i] = Episode(
                id: ep.id,
                animeId: ep.animeId,
                episodeNumber: ep.episodeNumber,
                title: ep.title,
                thumbnailUrl: thumbnail,
                airDate: ep.airDate,
                duration: ep.duration,
                videoUrls: ep.videoUrls,
              );
            }
          }
        }
      }
    } catch (_) {}

    episodes = _ensureReleasedEpisodeRows(
      animeId: animeId,
      anime: anime,
      aniData: aniData,
      episodes: episodes,
      episodeDuration: episodeDuration,
    );

    // Filter released episodes for Ongoing/Releasing anime
    if (anime != null && anime.status != 'Completed') {
      try {
        final liveReleasedCount = _releasedEpisodeCount(
          anime: anime,
          aniData: aniData,
          existingEpisodes: const [],
        );
        if (liveReleasedCount > 0) {
          episodes = episodes
              .where((ep) => ep.episodeNumber <= liveReleasedCount)
              .toList();
        } else {
          final cutoff = DateTime.now().add(const Duration(days: 1));
          episodes = episodes
              .where((ep) => !ep.airDate.isAfter(cutoff))
              .toList();
        }
      } catch (_) {
        final cutoff = DateTime.now().add(const Duration(days: 1));
        episodes = episodes.where((ep) => !ep.airDate.isAfter(cutoff)).toList();
      }
    }

    if (episodes.isNotEmpty) {
      _episodesCache[animeId] = episodes;
      _episodesCacheTime[animeId] = DateTime.now();
      if (storage != null) {
        unawaited(storage!.saveEpisodesToCache(_cacheKey(animeId), episodes));
      }
    }
    return episodes;
  }

  Map<String, dynamic>? _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _jsonResultHtml(Map<String, dynamic>? decoded) {
    final result = decoded?['result'];
    if (result is String) return result;
    if (result is Map<String, dynamic>) {
      return result['html'] as String? ?? '';
    }
    return '';
  }

  String _decodeHtmlText(String value) {
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeTitleForMatch(String title) {
    final decoded = _decodeHtmlText(title).toLowerCase();
    return decoded
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _titleMatchScore(String candidate, List<String> aliases) {
    final normalizedCandidate = _normalizeTitleForMatch(candidate);
    if (normalizedCandidate.isEmpty) return 0;

    var best = 0.0;
    for (final alias in aliases) {
      final normalizedAlias = _normalizeTitleForMatch(alias);
      if (normalizedAlias.isEmpty) continue;
      if (normalizedCandidate == normalizedAlias) {
        best = math.max(best, 1.0);
        continue;
      }
      if (normalizedCandidate.contains(normalizedAlias) ||
          normalizedAlias.contains(normalizedCandidate)) {
        best = math.max(best, 0.86);
      }

      final candidateTokens = normalizedCandidate
          .split(' ')
          .where((token) => token.length > 1)
          .toSet();
      final aliasTokens = normalizedAlias
          .split(' ')
          .where((token) => token.length > 1)
          .toSet();
      if (candidateTokens.isEmpty || aliasTokens.isEmpty) continue;
      final common = candidateTokens.intersection(aliasTokens).length;
      final dice = (2 * common) / (candidateTokens.length + aliasTokens.length);
      best = math.max(best, dice);
    }
    return best;
  }

  String? _firstRegexGroup(String input, RegExp pattern) {
    return pattern.firstMatch(input)?.group(1);
  }

  String? _extractYear(String input) {
    return _firstRegexGroup(input, RegExp(r'((?:19|20)\d{2})'));
  }

  String? _tagAttribute(String attrs, String name) {
    final match = RegExp(
      """$name=["']([^"']+)["']""",
      caseSensitive: false,
    ).firstMatch(attrs);
    final value = match?.group(1);
    return value == null ? null : _decodeHtmlText(value);
  }

  String? _absoluteWatchUrl(String href, String baseUrl) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return null;
    try {
      if (trimmed.startsWith('//')) return 'https:$trimmed';
      final uri = Uri.parse(trimmed);
      if (uri.hasScheme) return trimmed;
      return Uri.parse(baseUrl).resolve(trimmed).toString();
    } catch (_) {
      return null;
    }
  }

  void _addAlias(List<String> aliases, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text == 'null') return;
    final normalized = _normalizeTitleForMatch(text);
    if (normalized.isEmpty) return;
    if (!aliases.any((alias) => _normalizeTitleForMatch(alias) == normalized)) {
      aliases.add(text);
    }
  }

  Future<_AnimeLookupTarget> _buildLookupTarget(
    String animeId,
    Anime? anime,
  ) async {
    Map<String, dynamic>? aniData;
    try {
      aniData = await getAniListData(animeId);
    } catch (_) {}

    final aliases = <String>[];
    _addAlias(aliases, anime?.title);
    final titleObj = aniData?['title'] as Map<String, dynamic>?;
    _addAlias(aliases, titleObj?['english'] as String?);
    _addAlias(aliases, titleObj?['romaji'] as String?);
    _addAlias(aliases, titleObj?['native'] as String?);
    _addAlias(aliases, titleObj?['userPreferred'] as String?);
    if (aliases.isEmpty) _addAlias(aliases, animeId);

    final malId = aniData?['idMal']?.toString();
    final aniListId = aniData?['id']?.toString();
    final year =
        anime?.year ??
        aniData?['seasonYear']?.toString() ??
        aniData?['startDate']?['year']?.toString();

    return _AnimeLookupTarget(
      requestId: animeId,
      malId: malId != null && malId != 'null' && malId.isNotEmpty
          ? malId
          : anime?.malId ?? (int.tryParse(animeId) != null ? animeId : null),
      aniListId:
          aniListId != null && aniListId != 'null' && aniListId.isNotEmpty
          ? aniListId
          : anime?.aniListId ??
                (animeId.startsWith('ani:') ? animeId.substring(4) : null),
      title: aliases.first,
      aliases: aliases,
      year: year != null && year != 'null' && year.isNotEmpty ? year : null,
      totalEpisodes: anime?.totalEpisodes ?? aniData?['episodes'] as int? ?? 0,
    );
  }

  List<_ProviderSearchCandidate> _parseWatchSearchCandidates(
    String html,
    String baseUrl,
    _AnimeLookupTarget target,
  ) {
    final matches = RegExp(
      r'''href=["']([^"']*/watch/[^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html);
    final seen = <String>{};
    final candidates = <_ProviderSearchCandidate>[];

    for (final match in matches) {
      final watchUrl = _absoluteWatchUrl(match.group(1) ?? '', baseUrl);
      if (watchUrl == null || !seen.add(watchUrl)) continue;

      final start = math.max(0, match.start - 700);
      final end = math.min(html.length, match.end + 1200);
      final chunk = html.substring(start, end);
      final titles = _extractCandidateTitles(chunk);
      final siteAnimeId =
          _firstRegexGroup(
            watchUrl,
            RegExp(r'/watch/(?:[^/?#]*-)?(\d+)(?:[/?#]|$)'),
          ) ??
          _firstRegexGroup(
            chunk,
            RegExp(r'''data-tip=["'](\d+)["']''', caseSensitive: false),
          ) ??
          _firstRegexGroup(
            chunk,
            RegExp(r'''data-id=["'](\d+)["']''', caseSensitive: false),
          );
      final candMalId = _firstRegexGroup(
        chunk,
        RegExp(r'''data-mal=["'](\d+)["']''', caseSensitive: false),
      );
      final isMalMatch = target.malId != null && candMalId == target.malId;
      var bestScore = 0.0;
      var bestTitle = '';
      for (final t in titles) {
        final score = _titleMatchScore(t, target.aliases);
        if (score > bestScore) {
          bestScore = score;
          bestTitle = t;
        }
      }
      final finalScore = isMalMatch ? 1.0 : bestScore;

      candidates.add(
        _ProviderSearchCandidate(
          watchUrl: watchUrl,
          title: bestTitle.isNotEmpty
              ? bestTitle
              : (titles.isNotEmpty ? titles.first : ''),
          score: finalScore,
          siteAnimeId: siteAnimeId,
        ),
      );
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  List<String> _extractCandidateTitles(String htmlChunk) {
    final titles = <String>[];
    final patterns = [
      RegExp(
        r'''class=["'][^"']*(?:name|title)[^"']*d-title[^"']*["'][^>]*>([^<]+)<''',
        caseSensitive: false,
      ),
      RegExp(
        r'''class=["'][^"']*(?:name|title)[^"']*["'][^>]*>([^<]+)<''',
        caseSensitive: false,
      ),
      RegExp(r'''data-jp=["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''title=["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''alt=["']([^"']+)["']''', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(htmlChunk)) {
        final value = match.group(1);
        if (value != null && value.trim().isNotEmpty) {
          final cleaned = _cleanProviderTitle(value);
          if (cleaned.isNotEmpty && !titles.contains(cleaned)) {
            titles.add(cleaned);
          }
        }
      }
    }
    return titles;
  }

  String _cleanProviderTitle(String value) {
    var title = _decodeHtmlText(value);
    title = title.replaceAll(
      RegExp(
        r'\s*[|-]\s*(AniKoto|AnimeWave|HiAnimes|AniNeko).*$',
        caseSensitive: false,
      ),
      '',
    );
    title = title.replaceAll(RegExp(r'^Watch\s+', caseSensitive: false), '');
    title = title.replaceAll(
      RegExp(r'\s+Anime\s+Online.*$', caseSensitive: false),
      '',
    );
    title = title.replaceAll(
      RegExp(r'\s+Watch\s+Online.*$', caseSensitive: false),
      '',
    );
    return title.trim();
  }

  String _extractPageTitle(String html) {
    final patterns = [
      RegExp(
        r'''<h1[^>]*class=["'][^"']*d-title[^"']*["'][^>]*>([\s\S]*?)</h1>''',
        caseSensitive: false,
      ),
      RegExp(
        r'''property=["']og:title["'][^>]*content=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''name=["']title["'][^>]*content=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(r'''<title[^>]*>([\s\S]*?)</title>''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final value = _firstRegexGroup(html, pattern);
      if (value != null && value.trim().isNotEmpty) {
        return _cleanProviderTitle(value);
      }
    }
    return '';
  }

  bool _candidateMatchesTarget({
    required _AnimeLookupTarget target,
    required String candidateTitle,
    required String pageTitle,
    required String? candidateMalId,
    required String pageHtml,
  }) {
    if (candidateMalId != null &&
        target.malId != null &&
        candidateMalId.isNotEmpty) {
      return candidateMalId == target.malId;
    }

    var titleScore = math.max(
      _titleMatchScore(pageTitle, target.aliases),
      _titleMatchScore(candidateTitle, target.aliases),
    );
    final pageTitles = _extractAllPageTitles(pageHtml);
    for (final pt in pageTitles) {
      titleScore = math.max(titleScore, _titleMatchScore(pt, target.aliases));
    }

    if (titleScore < 0.42) return false;

    final pageYear = _extractYear(pageHtml);
    if (target.year != null &&
        pageYear != null &&
        pageYear != target.year &&
        titleScore < 0.9) {
      return false;
    }

    return true;
  }

  List<String> _extractAllPageTitles(String html) {
    final titles = <String>[];
    final patterns = [
      RegExp(r'''<h1[^>]*>([\s\S]*?)</h1>''', caseSensitive: false),
      RegExp(r'''data-jp=["']([^"']+)["']''', caseSensitive: false),
      RegExp(
        r'''property=["']og:title["'][^>]*content=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''name=["']title["'][^>]*content=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(r'''<title[^>]*>([\s\S]*?)</title>''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final value = match.group(1);
        if (value != null && value.trim().isNotEmpty) {
          final cleaned = _cleanProviderTitle(value);
          if (cleaned.isNotEmpty && !titles.contains(cleaned)) {
            titles.add(cleaned);
          }
        }
      }
    }
    return titles;
  }

  bool _isDirectStreamUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('playlist.m3u8');
  }

  bool _isHttpUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool _looksLikeSubtitleUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.vtt') ||
        lower.contains('.srt') ||
        lower.contains('.ass') ||
        lower.contains('.ssa') ||
        lower.contains('subtitle') ||
        lower.contains('caption');
  }

  String _decodeEscapedMediaText(String value) {
    return value
        .replaceAll(RegExp(r'\\u002[fF]'), '/')
        .replaceAll(RegExp(r'\\u0026', caseSensitive: false), '&')
        .replaceAll(RegExp(r'\\u003[dD]'), '=')
        .replaceAll('\\/', '/')
        .replaceAll('&amp;', '&');
  }

  String? _absoluteMediaUrl(String url, String baseUrl) {
    final decoded = _decodeHtmlText(_decodeEscapedMediaText(url)).trim();
    if (decoded.isEmpty || decoded.startsWith('blob:')) return null;
    return _absoluteWatchUrl(decoded, baseUrl);
  }

  String? _originFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  Map<String, String> _streamHeadersForReferer(String referer) {
    final origin = _originFromUrl(referer);
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': referer,
    };
    if (origin != null) headers['Origin'] = origin;
    return headers;
  }

  List<String> _prioritizeDirectStreamUrls(Iterable<String> urls) {
    final seen = <String>{};
    final unique = urls.where((url) => seen.add(url)).toList();
    unique.sort((a, b) {
      final aLower = a.toLowerCase();
      final bLower = b.toLowerCase();
      final aM3u8 = aLower.contains('.m3u8') ? 0 : 1;
      final bM3u8 = bLower.contains('.m3u8') ? 0 : 1;
      if (aM3u8 != bM3u8) return aM3u8.compareTo(bM3u8);
      final aMaster = aLower.contains('master') || aLower.contains('playlist')
          ? 0
          : 1;
      final bMaster = bLower.contains('master') || bLower.contains('playlist')
          ? 0
          : 1;
      if (aMaster != bMaster) return aMaster.compareTo(bMaster);
      return a.length.compareTo(b.length);
    });
    return unique;
  }

  List<String> _extractDirectStreamUrls(String body, String baseUrl) {
    final decoded = _decodeEscapedMediaText(body);
    final urls = <String>[];

    void addUrl(String value) {
      final url = _absoluteMediaUrl(value, baseUrl);
      if (url != null && _isHttpUrl(url) && _isDirectStreamUrl(url)) {
        urls.add(url);
      }
    }

    final absoluteUrlPattern = RegExp(
      r'''https?:\/\/[^"'<>\\\s)]+''',
      caseSensitive: false,
    );
    for (final match in absoluteUrlPattern.allMatches(decoded)) {
      addUrl(match.group(0) ?? '');
    }

    final mediaFieldPattern = RegExp(
      r'''["'](?:file|url|src)["']\s*:\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in mediaFieldPattern.allMatches(decoded)) {
      addUrl(match.group(1) ?? '');
    }

    final sourceTagPattern = RegExp(
      r'''<source\b[^>]*\bsrc=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in sourceTagPattern.allMatches(decoded)) {
      addUrl(match.group(1) ?? '');
    }

    return _prioritizeDirectStreamUrls(urls);
  }

  String _normalizedSubtitleSearchText(String text) {
    return text
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll('\u00e1', 'a')
        .replaceAll('\u00e0', 'a')
        .replaceAll('\u00e2', 'a')
        .replaceAll('\u00e3', 'a')
        .replaceAll('\u00e4', 'a')
        .replaceAll('\u00e9', 'e')
        .replaceAll('\u00e8', 'e')
        .replaceAll('\u00ea', 'e')
        .replaceAll('\u00eb', 'e')
        .replaceAll('\u00ed', 'i')
        .replaceAll('\u00ec', 'i')
        .replaceAll('\u00ee', 'i')
        .replaceAll('\u00ef', 'i')
        .replaceAll('\u00f3', 'o')
        .replaceAll('\u00f2', 'o')
        .replaceAll('\u00f4', 'o')
        .replaceAll('\u00f5', 'o')
        .replaceAll('\u00f6', 'o')
        .replaceAll('\u00fa', 'u')
        .replaceAll('\u00f9', 'u')
        .replaceAll('\u00fb', 'u')
        .replaceAll('\u00fc', 'u')
        .replaceAll('\u00e7', 'c')
        .replaceAll('\u00f1', 'n');
  }

  String _subtitleLanguageFromText(String text) {
    final lower = _normalizedSubtitleSearchText(text);
    if (RegExp(r'(^|[^a-z])(en|eng|english)([^a-z]|$)').hasMatch(lower)) {
      return 'en';
    }
    if (RegExp(
      r'(^|[^a-z])(pt|pt-br|por|portuguese|portugues|brazilian)([^a-z]|$)',
    ).hasMatch(lower)) {
      return 'pt';
    }
    if (RegExp(
      r'(^|[^a-z])(es|spa|spanish|espanol|castilian|castellano)([^a-z]|$)',
    ).hasMatch(lower)) {
      return 'es';
    }
    return '';
  }

  String _subtitleLabelForLanguage(String language, String url) {
    final normalized = _normalizedSubtitleSearchText(language).trim();
    if (normalized == 'en' || normalized == 'eng' || normalized == 'english') {
      return 'English';
    }
    if (normalized == 'pt' ||
        normalized == 'pt-br' ||
        normalized == 'por' ||
        normalized == 'portuguese' ||
        normalized == 'portugues' ||
        normalized == 'brazilian') {
      return 'Portuguese';
    }
    if (normalized == 'es' ||
        normalized == 'spa' ||
        normalized == 'spanish' ||
        normalized == 'espanol' ||
        normalized == 'castilian' ||
        normalized == 'castellano') {
      return 'Spanish';
    }

    final uri = Uri.tryParse(url);
    final fileName = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    return fileName.isNotEmpty ? fileName : 'Subtitle';
  }

  SubtitleTrack? _subtitleTrackFromFields({
    required String? file,
    required String? label,
    required String? language,
    required String? kind,
    required String baseUrl,
  }) {
    final url = file == null ? null : _absoluteMediaUrl(file, baseUrl);
    if (url == null || !_isHttpUrl(url)) return null;

    final normalizedKind = kind?.toLowerCase().trim() ?? '';
    final isNonSubtitle =
        normalizedKind.contains('thumbnail') ||
        normalizedKind.contains('thumb') ||
        normalizedKind.contains('chapter') ||
        normalizedKind.contains('metadata');
    if (isNonSubtitle) return null;

    final isSubtitleKind =
        normalizedKind.isEmpty ||
        normalizedKind.contains('caption') ||
        normalizedKind.contains('subtitle');
    if (!isSubtitleKind && !_looksLikeSubtitleUrl(url)) return null;

    final resolvedLanguage = (language ?? '').trim().isNotEmpty
        ? language!.trim()
        : _subtitleLanguageFromText('${label ?? ''} $url');
    final resolvedLabel = (label ?? '').trim().isNotEmpty
        ? label!.trim()
        : _subtitleLabelForLanguage(resolvedLanguage, url);

    return SubtitleTrack(
      label: resolvedLabel,
      language: resolvedLanguage,
      url: url,
    );
  }

  List<SubtitleTrack> _mergeSubtitleTracks(
    Iterable<SubtitleTrack> first,
    Iterable<SubtitleTrack> second,
  ) {
    final tracks = <SubtitleTrack>[];
    final seen = <String>{};

    void add(SubtitleTrack track) {
      final url = track.url.trim();
      if (url.isEmpty || !seen.add(url)) return;
      tracks.add(track);
    }

    for (final track in first) {
      add(track);
    }
    for (final track in second) {
      add(track);
    }

    return tracks;
  }

  List<SubtitleTrack> _parseSubtitleTracksFromRaw(
    Object? rawTracks,
    String baseUrl,
  ) {
    if (rawTracks is! List || rawTracks.isEmpty) return const [];
    final tracks = <SubtitleTrack>[];

    for (final rawTrack in rawTracks) {
      if (rawTrack is! Map) continue;
      final track = _subtitleTrackFromFields(
        file: (rawTrack['file'] ?? rawTrack['url'] ?? rawTrack['src'])
            ?.toString(),
        label: (rawTrack['label'] ?? rawTrack['name'] ?? rawTrack['title'])
            ?.toString(),
        language:
            (rawTrack['lang'] ?? rawTrack['language'] ?? rawTrack['srclang'])
                ?.toString(),
        kind: (rawTrack['kind'] ?? rawTrack['type'])?.toString(),
        baseUrl: baseUrl,
      );
      if (track != null) tracks.add(track);
    }

    return _mergeSubtitleTracks(tracks, const []);
  }

  List<SubtitleTrack> _extractSubtitleTracksFromText(
    String body,
    String baseUrl,
  ) {
    final decoded = _decodeEscapedMediaText(body);
    final tracks = <SubtitleTrack>[];

    final trackTagPattern = RegExp(
      r'''<track\b([^>]*)>''',
      caseSensitive: false,
    );
    for (final match in trackTagPattern.allMatches(decoded)) {
      final attrs = match.group(1) ?? '';
      final track = _subtitleTrackFromFields(
        file: _tagAttribute(attrs, 'src'),
        label: _tagAttribute(attrs, 'label'),
        language:
            _tagAttribute(attrs, 'srclang') ?? _tagAttribute(attrs, 'lang'),
        kind: _tagAttribute(attrs, 'kind'),
        baseUrl: baseUrl,
      );
      if (track != null) tracks.add(track);
    }

    final subtitleUrlPattern = RegExp(
      r'''https?:\/\/[^"'<>\\\s)]+\.(?:vtt|srt|ass|ssa)[^"'<>\\\s)]*''',
      caseSensitive: false,
    );
    for (final match in subtitleUrlPattern.allMatches(decoded)) {
      final track = _subtitleTrackFromFields(
        file: match.group(0),
        label: null,
        language: null,
        kind: 'subtitles',
        baseUrl: baseUrl,
      );
      if (track != null) tracks.add(track);
    }

    final subtitleFieldPattern = RegExp(
      r'''["'](?:file|url|src)["']\s*:\s*["']([^"']+\.(?:vtt|srt|ass|ssa)[^"']*)["']''',
      caseSensitive: false,
    );
    for (final match in subtitleFieldPattern.allMatches(decoded)) {
      final track = _subtitleTrackFromFields(
        file: match.group(1),
        label: null,
        language: null,
        kind: 'subtitles',
        baseUrl: baseUrl,
      );
      if (track != null) tracks.add(track);
    }

    return _mergeSubtitleTracks(tracks, const []);
  }

  List<String> _extractIframeUrls(String body, String baseUrl) {
    final decoded = _decodeEscapedMediaText(body);
    final urls = <String>[];
    final seen = <String>{};

    void addUrl(String? value) {
      if (value == null || value.isEmpty) return;
      final url = _absoluteMediaUrl(value, baseUrl);
      if (url == null || !_isHttpUrl(url) || !seen.add(url)) return;
      urls.add(url);
    }

    final iframePattern = RegExp(
      r'''<iframe\b[^>]*\bsrc=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in iframePattern.allMatches(decoded)) {
      addUrl(match.group(1));
    }

    final srcFieldPattern = RegExp(
      r'''["'](?:embed|iframe|player|url|src)["']\s*:\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in srcFieldPattern.allMatches(decoded)) {
      final value = match.group(1) ?? '';
      if (!_isDirectStreamUrl(value) && !_looksLikeSubtitleUrl(value)) {
        addUrl(value);
      }
    }

    return urls;
  }

  String? _englishSubtitleUrl(List<SubtitleTrack> tracks) {
    if (tracks.isEmpty) return null;
    final englishIndex = tracks.indexWhere((track) {
      final label = _normalizedSubtitleSearchText(track.label);
      final language = _normalizedSubtitleSearchText(track.language);
      return label.contains('english') || language.startsWith('en');
    });
    return englishIndex == -1 ? null : tracks[englishIndex].url;
  }

  int _subtitleTrackPriority(SubtitleTrack track) {
    final text = _normalizedSubtitleSearchText(
      '${track.language} ${track.label} ${track.url}',
    );
    if (RegExp(r'(^|[^a-z])(en|eng|english)([^a-z]|$)').hasMatch(text)) {
      return 0;
    }
    if (RegExp(
      r'(^|[^a-z])(es|spa|spanish|espanol|castilian|castellano)([^a-z]|$)',
    ).hasMatch(text)) {
      return 1;
    }
    if (RegExp(
      r'(^|[^a-z])(pt|pt-br|por|portuguese|portugues|brazilian)([^a-z]|$)',
    ).hasMatch(text)) {
      return 2;
    }
    return 3;
  }

  List<SubtitleTrack>? _prioritizeKakashiSubtitleTracks(
    List<SubtitleTrack>? tracks,
  ) {
    if (tracks == null || tracks.isEmpty) return tracks;
    final indexed = tracks.asMap().entries.toList()
      ..sort((a, b) {
        final priority = _subtitleTrackPriority(
          a.value,
        ).compareTo(_subtitleTrackPriority(b.value));
        if (priority != 0) return priority;
        return a.key.compareTo(b.key);
      });
    return List.unmodifiable(indexed.map((entry) => entry.value));
  }

  String? _kakashiSubtitleUrl(
    List<SubtitleTrack>? prioritizedTracks,
    String? fallbackUrl,
  ) {
    if (prioritizedTracks == null || prioritizedTracks.isEmpty) {
      return fallbackUrl;
    }
    return _englishSubtitleUrl(prioritizedTracks) ?? fallbackUrl;
  }

  _ResolvedProviderStream? _parseZokoPlayerPage(String body, String pageUrl) {
    if (Uri.tryParse(pageUrl)?.host != 'zokoanime.video') return null;
    try {
      final match = RegExp(
        r'''window\.__P\s*=\s*["']([A-Za-z0-9+/=]+)["']''',
      ).firstMatch(body);
      if (match == null) return null;
      final bytes = base64.decode(match.group(1)!);
      final key = utf8.encode('otaku-embed-v1');
      final decoded = utf8.decode(
        List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length]),
      );
      final payload = jsonDecode(decoded);
      if (payload is! Map<String, dynamic>) return null;
      final source = payload['src'];
      if (source is! String) return null;
      final url = _absoluteMediaUrl(source, pageUrl);
      if (url == null || !_isHttpUrl(url) || !_isDirectStreamUrl(url)) {
        return null;
      }
      final tracks = _parseSubtitleTracksFromRaw(payload['subtitles'], pageUrl);
      return _ResolvedProviderStream(
        videoUrls: [url],
        headers: _streamHeadersForReferer(pageUrl),
        subtitleUrl: _englishSubtitleUrl(tracks),
        subtitleTracks: tracks.isEmpty ? null : tracks,
        skipTimes: EpisodeSkipTimes.fromProvider(payload['skip']),
      );
    } catch (_) {
      // Unknown or malformed configurations can still use the embed player.
      return null;
    }
  }

  @visibleForTesting
  VideoProviderSource? parseZokoPlayerPageForTesting(
    String body,
    String pageUrl,
  ) {
    final result = _parseZokoPlayerPage(body, pageUrl);
    if (result == null) return null;
    return VideoProviderSource(
      name: 'Luffy',
      description: 'ZokoAnime Native',
      languageType: 'SUB',
      videoUrls: result.videoUrls,
      speedStatus: 'Fast',
      isEmbed: false,
      headers: result.headers,
      subtitleUrl: result.subtitleUrl,
      subtitleTracks: result.subtitleTracks,
      skipTimes: result.skipTimes,
    );
  }

  Future<_ResolvedProviderStream?> _resolveDirectProviderStream({
    required String streamUrl,
    required String baseUrl,
    required Map<String, String> headers,
    Object? rawTracks,
    List<SubtitleTrack> inheritedSubtitleTracks = const [],
    int depth = 0,
  }) async {
    final resolvedStreamUrl = _absoluteMediaUrl(streamUrl, baseUrl);
    if (resolvedStreamUrl == null || !_isHttpUrl(resolvedStreamUrl)) {
      return null;
    }

    var subtitleTracks = _mergeSubtitleTracks(
      inheritedSubtitleTracks,
      _parseSubtitleTracksFromRaw(rawTracks, baseUrl),
    );

    if (_isDirectStreamUrl(resolvedStreamUrl)) {
      return _ResolvedProviderStream(
        videoUrls: [resolvedStreamUrl],
        headers: _streamHeadersForReferer(baseUrl),
        subtitleUrl: _englishSubtitleUrl(subtitleTracks),
        subtitleTracks: subtitleTracks.isEmpty ? null : subtitleTracks,
      );
    }

    final pageHeaders = {
      ...headers,
      ..._streamHeadersForReferer(baseUrl),
      'Referer': headers['Referer'] ?? '$baseUrl/',
    };
    final response = await _getResponse(
      Uri.parse(resolvedStreamUrl),
      headers: pageHeaders,
      timeout: const Duration(seconds: 5),
    );
    if (response == null || response.statusCode != 200) return null;

    final pageUrl = response.request?.url.toString() ?? resolvedStreamUrl;
    final zokoStream = _parseZokoPlayerPage(response.body, pageUrl);
    if (zokoStream != null) return zokoStream;
    subtitleTracks = _mergeSubtitleTracks(
      subtitleTracks,
      _extractSubtitleTracksFromText(response.body, pageUrl),
    );

    if (_isDirectStreamUrl(pageUrl)) {
      return _ResolvedProviderStream(
        videoUrls: [pageUrl],
        headers: _streamHeadersForReferer(resolvedStreamUrl),
        subtitleUrl: _englishSubtitleUrl(subtitleTracks),
        subtitleTracks: subtitleTracks.isEmpty ? null : subtitleTracks,
      );
    }

    final directUrls = _extractDirectStreamUrls(response.body, pageUrl);
    if (directUrls.isNotEmpty) {
      return _ResolvedProviderStream(
        videoUrls: directUrls,
        headers: _streamHeadersForReferer(pageUrl),
        subtitleUrl: _englishSubtitleUrl(subtitleTracks),
        subtitleTracks: subtitleTracks.isEmpty ? null : subtitleTracks,
      );
    }

    if (depth >= 2) return null;

    for (final iframeUrl in _extractIframeUrls(
      response.body,
      pageUrl,
    ).take(4)) {
      final nested = await _resolveDirectProviderStream(
        streamUrl: iframeUrl,
        baseUrl: pageUrl,
        headers: _streamHeadersForReferer(pageUrl),
        inheritedSubtitleTracks: subtitleTracks,
        depth: depth + 1,
      );
      if (nested != null) return nested;
    }

    return null;
  }

  String _normalizeProviderLanguage(String type) {
    final normalized = type.toLowerCase().trim();
    return normalized == 'dub' ? 'DUB' : 'SUB';
  }

  int _serverRank(_ProviderServerEntry server) {
    final name = server.name.toLowerCase();
    if (name.contains('vidstream')) return 0;
    if (name == 'hd' || name.contains(' hd')) return 1;
    if (name.contains('vidcloud')) return 2;
    if (name.contains('stream')) return 3;
    return 5;
  }

  List<_ProviderServerEntry> _parseProviderServerEntries(String html) {
    final entries = <_ProviderServerEntry>[];
    final sectionReg = RegExp(
      r'''data-type=["'](\w+)["']([\s\S]*?)(?=data-type=["']|$)''',
      caseSensitive: false,
    );
    final linkReg = RegExp(
      r'''data-link-id=["']([^"']+)["'][^>]*>([^<]*)<''',
      caseSensitive: false,
    );

    for (final section in sectionReg.allMatches(html)) {
      final type = section.group(1) ?? 'sub';
      final block = section.group(2) ?? '';
      for (final link in linkReg.allMatches(block)) {
        final linkId = link.group(1);
        if (linkId == null || linkId.isEmpty) continue;
        entries.add(
          _ProviderServerEntry(
            type: type,
            linkId: linkId,
            name: _decodeHtmlText(link.group(2) ?? ''),
          ),
        );
      }
    }

    if (entries.isNotEmpty) return entries;
    for (final link in linkReg.allMatches(html)) {
      final linkId = link.group(1);
      if (linkId == null || linkId.isEmpty) continue;
      entries.add(
        _ProviderServerEntry(
          type: 'sub',
          linkId: linkId,
          name: _decodeHtmlText(link.group(2) ?? ''),
        ),
      );
    }
    return entries;
  }

  Future<_AniWatchEpisodeMatch?> _loadAniWatchEpisodeMatch({
    required String baseUrl,
    required String siteAnimeId,
    required int episodeNumber,
    required Map<String, String> headers,
    required String pageTitle,
  }) async {
    final epListUrl = Uri.parse('$baseUrl/ajax/episode/list/$siteAnimeId');
    final epRes = await _getResponse(
      epListUrl,
      headers: headers,
      timeout: const Duration(seconds: 5),
    );
    if (epRes == null || epRes.statusCode != 200) return null;

    final epHtml = _jsonResultHtml(_decodeJsonObject(epRes.body));
    final epNum = RegExp.escape(episodeNumber.toString());
    final epReg = RegExp(
      """<a\\b(?=[^>]*data-num=["']$epNum["'])([^>]*)>""",
      caseSensitive: false,
    );
    final epMatch = epReg.firstMatch(epHtml);
    if (epMatch == null) return null;

    final attrs = epMatch.group(1) ?? '';
    final serverIds = _tagAttribute(attrs, 'data-ids');
    if (serverIds == null || serverIds.isEmpty) return null;

    return _AniWatchEpisodeMatch(
      siteAnimeId: siteAnimeId,
      serverIds: serverIds,
      malId: _tagAttribute(attrs, 'data-mal'),
      pageTitle: pageTitle,
    );
  }

  Future<List<VideoProviderSource>> _resolveAniWatchServerEntries({
    required String baseUrl,
    required String providerName,
    required String description,
    required String serverIds,
    required Map<String, String> headers,
  }) async {
    final serverListUrl = Uri.parse(
      '$baseUrl/ajax/server/list?servers=$serverIds',
    );
    final serverRes = await _getResponse(
      serverListUrl,
      headers: headers,
      timeout: const Duration(seconds: 5),
    );
    if (serverRes == null || serverRes.statusCode != 200) return [];

    final serverHtml = _jsonResultHtml(_decodeJsonObject(serverRes.body));
    final entries = _parseProviderServerEntries(serverHtml)
      ..sort((a, b) => _serverRank(a).compareTo(_serverRank(b)));

    final futures = entries.map((entry) async {
      try {
        final getUrl = Uri.parse('$baseUrl/ajax/server?get=${entry.linkId}');
        final streamRes = await _getResponse(
          getUrl,
          headers: headers,
          timeout: const Duration(seconds: 4),
        );
        if (streamRes == null || streamRes.statusCode != 200) return null;

        final streamJson = _decodeJsonObject(streamRes.body);
        final result = streamJson?['result'];
        final streamUrl = result is Map<String, dynamic>
            ? result['url'] as String?
            : null;
        if (streamUrl == null || streamUrl.isEmpty) return null;

        final rawTracks = result is Map<String, dynamic>
            ? (result['tracks'] as List? ?? result['subtitles'] as List?)
            : (streamJson?['tracks'] as List? ??
                  streamJson?['subtitles'] as List?);
        final resolvedStream = await _resolveDirectProviderStream(
          streamUrl: streamUrl,
          baseUrl: baseUrl,
          headers: headers,
          rawTracks: rawTracks,
        );
        if (resolvedStream == null) return null;

        return VideoProviderSource(
          name: providerName,
          description: description,
          languageType: _normalizeProviderLanguage(entry.type),
          videoUrls: resolvedStream.videoUrls,
          speedStatus: 'Fast',
          isEmbed: false,
          subtitleUrl: resolvedStream.subtitleUrl,
          subtitleTracks: resolvedStream.subtitleTracks,
          headers: resolvedStream.headers,
        );
      } catch (_) {
        return null;
      }
    }).toList();

    final resolved = await Future.wait(futures);
    return resolved.whereType<VideoProviderSource>().toList();
  }

  Future<List<VideoProviderSource>> _resolveAniWatchStyleServers({
    required _AnimeLookupTarget target,
    required int episodeNumber,
    required String baseUrl,
    required String providerName,
    required String description,
    required Map<String, String> cache,
  }) async {
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': '$baseUrl/',
    };

    final cachedSiteAnimeId = cache[target.cacheKey];
    if (cachedSiteAnimeId != null) {
      try {
        final match = await _loadAniWatchEpisodeMatch(
          baseUrl: baseUrl,
          siteAnimeId: cachedSiteAnimeId,
          episodeNumber: episodeNumber,
          headers: headers,
          pageTitle: target.title,
        );
        if (match != null) {
          return _resolveAniWatchServerEntries(
            baseUrl: baseUrl,
            providerName: providerName,
            description: description,
            serverIds: match.serverIds,
            headers: headers,
          );
        }
      } catch (_) {
        cache.remove(target.cacheKey);
      }
    }

    final searchTerms = <String>[];
    // Only search by title aliases — searching by numeric MAL ID returns no
    // results on these sites (they use it as a data attribute, not a keyword).
    searchTerms.addAll(target.aliases);

    final candidateMap = <String, _ProviderSearchCandidate>{};
    for (final term in searchTerms.take(5)) {
      try {
        final encodedTerm = Uri.encodeQueryComponent(term);
        final searchPaths = [
          if (baseUrl.contains('aniwaves.ru')) '/filter?keyword=$encodedTerm',
          if (baseUrl.contains('aniwaves.ru'))
            '/ajax/anime/search?keyword=$encodedTerm',
          if (baseUrl.contains('anizone.to')) '/anime?search=$encodedTerm',
          if (baseUrl.contains('animex.one')) '/catalog?keyword=$encodedTerm',
          if (baseUrl.contains('reanime.to')) '/search?keyword=$encodedTerm',
          '/browser?keyword=$encodedTerm',
          '/filter?keyword=$encodedTerm',
          '/search?keyword=$encodedTerm',
          '/ajax/anime/search?keyword=$encodedTerm',
        ];

        for (final path in searchPaths) {
          final searchUrl = Uri.parse('$baseUrl$path');
          final searchRes = await _getResponse(
            searchUrl,
            headers: headers,
            timeout: const Duration(seconds: 5),
          );
          if (searchRes == null || searchRes.statusCode != 200) continue;
          final searchHtml = searchRes.body.startsWith('{')
              ? _jsonResultHtml(_decodeJsonObject(searchRes.body))
              : searchRes.body;
          final foundCandidates = _parseWatchSearchCandidates(
            searchHtml,
            baseUrl,
            target,
          );
          if (foundCandidates.isNotEmpty) {
            for (final candidate in foundCandidates) {
              final existing = candidateMap[candidate.watchUrl];
              if (existing == null || candidate.score > existing.score) {
                candidateMap[candidate.watchUrl] = candidate;
              }
            }
            break;
          }
        }
      } catch (_) {}
    }

    final candidates = candidateMap.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    for (final candidate in candidates.take(8)) {
      if (candidate.score < 0.42) continue;
      try {
        final candidateSiteAnimeId = candidate.siteAnimeId;
        if (candidateSiteAnimeId != null && candidateSiteAnimeId.isNotEmpty) {
          final episodeMatch = await _loadAniWatchEpisodeMatch(
            baseUrl: baseUrl,
            siteAnimeId: candidateSiteAnimeId,
            episodeNumber: episodeNumber,
            headers: headers,
            pageTitle: candidate.title,
          );
          if (episodeMatch != null) {
            cache[target.cacheKey] = episodeMatch.siteAnimeId;
            return _resolveAniWatchServerEntries(
              baseUrl: baseUrl,
              providerName: providerName,
              description: description,
              serverIds: episodeMatch.serverIds,
              headers: headers,
            );
          }
        }

        final watchRes = await _getResponse(
          Uri.parse(candidate.watchUrl),
          headers: headers,
          timeout: const Duration(seconds: 5),
        );
        if (watchRes == null || watchRes.statusCode != 200) continue;

        final watchHtml = watchRes.body;
        final siteAnimeId =
            _firstRegexGroup(
              watchHtml,
              RegExp(r'data-anime-id="(\d+)"', caseSensitive: false),
            ) ??
            _firstRegexGroup(
              watchHtml,
              RegExp(r'data-id="(\d+)"', caseSensitive: false),
            );
        if (siteAnimeId == null) continue;

        final pageTitle = _extractPageTitle(watchHtml);
        final episodeMatch = await _loadAniWatchEpisodeMatch(
          baseUrl: baseUrl,
          siteAnimeId: siteAnimeId,
          episodeNumber: episodeNumber,
          headers: headers,
          pageTitle: pageTitle,
        );
        if (episodeMatch == null) continue;

        if (!_candidateMatchesTarget(
          target: target,
          candidateTitle: candidate.title,
          pageTitle: episodeMatch.pageTitle,
          candidateMalId: episodeMatch.malId,
          pageHtml: watchHtml,
        )) {
          continue;
        }

        cache[target.cacheKey] = episodeMatch.siteAnimeId;
        return _resolveAniWatchServerEntries(
          baseUrl: baseUrl,
          providerName: providerName,
          description: description,
          serverIds: episodeMatch.serverIds,
          headers: headers,
        );
      } catch (_) {}
    }

    return [];
  }

  String? _extractAniNekoStreamUrl(String html) {
    final m3u8Match = RegExp(
      r'''["'](https?://[^"']+\.m3u8[^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final iframeMatch = RegExp(
      r'''<iframe[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    return m3u8Match?.group(1) ?? iframeMatch?.group(1);
  }

  Future<VideoProviderSource?> _resolveAniNekoSlug({
    required String slug,
    required String candidateTitle,
    required _AnimeLookupTarget target,
    required int episodeNumber,
    required String baseUrl,
    required Map<String, String> headers,
  }) async {
    final epUrl = Uri.parse('$baseUrl/watch/$slug/ep-$episodeNumber');
    final epRes = await _getResponse(
      epUrl,
      headers: headers,
      timeout: const Duration(seconds: 5),
    );
    if (epRes == null || epRes.statusCode != 200) return null;

    final html = epRes.body;
    final pageTitle = _extractPageTitle(html);
    if (!_candidateMatchesTarget(
      target: target,
      candidateTitle: candidateTitle,
      pageTitle: pageTitle,
      candidateMalId: null,
      pageHtml: html,
    )) {
      return null;
    }

    final streamUrl = _extractAniNekoStreamUrl(html);
    if (streamUrl == null || streamUrl.isEmpty) return null;
    final resolvedStream = await _resolveDirectProviderStream(
      streamUrl: streamUrl,
      baseUrl: baseUrl,
      headers: headers,
      inheritedSubtitleTracks: _extractSubtitleTracksFromText(
        html,
        epUrl.toString(),
      ),
    );
    if (resolvedStream == null) return null;

    return VideoProviderSource(
      name: 'Levi',
      description: 'AniNeko Stream (ep-$episodeNumber)',
      languageType: 'SUB',
      videoUrls: resolvedStream.videoUrls,
      speedStatus: 'Fast',
      isEmbed: false,
      subtitleUrl: resolvedStream.subtitleUrl,
      subtitleTracks: resolvedStream.subtitleTracks,
      headers: resolvedStream.headers,
    );
  }

  Map<String, String> _embedHeadersForOrigin(String origin) {
    return {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Referer': '$origin/',
      'Origin': origin,
    };
  }

  String _providerIdSource(String idType) {
    final normalized = idType.toLowerCase().trim();
    return normalized == 'ani' || normalized == 'anilist' ? 'ani' : 'mal';
  }

  // VidHawk calls its own provider backend "zuri". Without this explicit
  // mapping its embed route defaults to "kari", so the Tanjiro card would
  // silently play a different provider.
  static const String _tanjiroVidHawkServer = 'zuri';

  List<VideoProviderSource> _buildMegaPlayEmbedProviders({
    required String idType,
    required String id,
    required int episodeNumber,
    bool includeLevi = true,
  }) {
    final providers = <VideoProviderSource>[];
    final providerIdSource = _providerIdSource(idType);

    for (final lang in ['sub', 'dub']) {
      final embedUrl =
          'https://megaplay.buzz/stream/$idType/$id/$episodeNumber/$lang?server=gojo';
      providers.add(
        VideoProviderSource(
          name: 'Gojo',
          description: 'MegaPlay Buzz',
          languageType: lang.toUpperCase(),
          videoUrls: [embedUrl],
          speedStatus: 'Stable',
          isEmbed: true,
          headers: _embedHeadersForOrigin('https://megaplay.buzz'),
        ),
      );

      final animePlayerUrl =
          'https://ani.megaplay.su/$idType/$id/$episodeNumber/$lang';
      providers.add(
        VideoProviderSource(
          name: 'Kakashi',
          description: 'Anime Player Embed',
          languageType: lang.toUpperCase(),
          videoUrls: [animePlayerUrl],
          speedStatus: 'Stable',
          isEmbed: true,
          headers: _embedHeadersForOrigin('https://ani.megaplay.su'),
        ),
      );

      final zokoUrl =
          'https://zokoanime.video/stream/$providerIdSource/$id/$episodeNumber/$lang';
      providers.add(
        VideoProviderSource(
          name: 'Luffy',
          description: 'ZokoAnime Embed',
          languageType: lang.toUpperCase(),
          videoUrls: [zokoUrl],
          speedStatus: 'Stable',
          isEmbed: true,
          headers: _embedHeadersForOrigin('https://zokoanime.video'),
        ),
      );

      final vidhawkUrl =
          'https://vidhawk.buzz/embed/$providerIdSource/$id/$episodeNumber/$lang?server=$_tanjiroVidHawkServer';
      providers.add(
        VideoProviderSource(
          name: 'Tanjiro',
          description: 'VidHawk Zuri Embed',
          languageType: lang.toUpperCase(),
          videoUrls: [vidhawkUrl],
          speedStatus: 'Stable',
          isEmbed: true,
          headers: _embedHeadersForOrigin('https://vidhawk.buzz'),
        ),
      );

      if (includeLevi) {
        final leviUrl =
            'https://megaplay.buzz/stream/$idType/$id/$episodeNumber/$lang?server=levi';
        providers.add(
          VideoProviderSource(
            name: 'Levi',
            description: 'Torrent Stream • P2P High Speed',
            languageType: lang.toUpperCase(),
            videoUrls: [leviUrl],
            speedStatus: 'Fallback',
            isEmbed: true,
            headers: _embedHeadersForOrigin('https://megaplay.buzz'),
          ),
        );
      }
    }

    return providers;
  }

  Future<({String idType, String id})> _resolveMegaPlayCatalogId(
    String animeId, {
    Anime? anime,
  }) async {
    if (anime != null) {
      final candidates = await _resolveMegaPlayCatalogCandidates(anime);
      if (candidates.isNotEmpty) return candidates.first;
    }

    String finalId = animeId;
    String idType = 'mal';

    if (int.tryParse(animeId) != null) {
      return (idType: idType, id: finalId);
    }

    try {
      final aniData = await getAniListData(animeId);
      if (aniData != null) {
        final malIdStr = aniData['idMal']?.toString();
        final aniIdStr = aniData['id']?.toString();

        if (malIdStr != null && malIdStr != 'null' && malIdStr.isNotEmpty) {
          finalId = malIdStr;
          idType = 'mal';
        } else if (int.tryParse(animeId) != null) {
          finalId = animeId;
          idType = 'mal';
        } else if (aniIdStr != null &&
            aniIdStr != 'null' &&
            aniIdStr.isNotEmpty) {
          finalId = aniIdStr;
          idType = 'ani';
        }
      } else if (int.tryParse(animeId) != null) {
        finalId = animeId;
        idType = 'mal';
      }
    } catch (_) {
      if (int.tryParse(animeId) != null) {
        finalId = animeId;
        idType = 'mal';
      }
    }

    return (idType: idType, id: finalId);
  }

  Future<_ResolvedProviderStream?> _resolveMegaPlayEncryptedStream({
    required String streamUrl,
    required String baseUrl,
  }) async {
    try {
      final pageHeaders = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': '$baseUrl/',
        'Sec-Fetch-Dest': 'iframe',
      };
      final pageResponse = await _getResponse(
        Uri.parse(streamUrl),
        headers: pageHeaders,
        timeout: const Duration(seconds: 6),
      );
      if (pageResponse == null || pageResponse.statusCode != 200) {
        return null;
      }

      final dataIdMatch = RegExp(
        r'data-id="(\d+)"',
      ).firstMatch(pageResponse.body);
      if (dataIdMatch == null) {
        return null;
      }
      final dataId = dataIdMatch.group(1)!;

      final sourcesUri = Uri.parse('$baseUrl/stream/getSourcesNew?id=$dataId');
      final sourcesResponse = await _getResponse(
        sourcesUri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': streamUrl,
          'X-Requested-With': 'XMLHttpRequest',
        },
        timeout: const Duration(seconds: 6),
      );
      if (sourcesResponse == null || sourcesResponse.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(sourcesResponse.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final enc = decoded['enc'] as String?;
      if (enc == null || enc.isEmpty) {
        return null;
      }

      const keyStr = 'i?LMTAx0Q6,:}50U';
      const ivStr = "W0;27ToaUpl_P%'c";

      final keyBytes = Uint8List(32);
      final keyRaw = utf8.encode(keyStr);
      keyBytes.setRange(0, keyRaw.length.clamp(0, 32), keyRaw);

      final ivBytes = Uint8List(16);
      final ivRaw = utf8.encode(ivStr);
      ivBytes.setRange(0, ivRaw.length.clamp(0, 16), ivRaw);

      final cipherBytes = base64Url.decode(base64Url.normalize(enc));
      final algorithm = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
      final secretKey = SecretKey(keyBytes);
      final secretBox = SecretBox(cipherBytes, nonce: ivBytes, mac: Mac.empty);

      final decryptedBytes = await algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      final decryptedText = utf8.decode(decryptedBytes);
      final payload = jsonDecode(decryptedText);
      if (payload is! Map<String, dynamic>) return null;

      final m3u8Url = payload['file'] as String?;
      if (m3u8Url == null || m3u8Url.isEmpty) return null;

      final tracks = decoded['tracks'] as List?;
      final subtitleTracks = <SubtitleTrack>[];
      if (tracks != null) {
        for (final item in tracks) {
          if (item is Map<String, dynamic>) {
            final url = item['file'] as String? ?? item['url'] as String?;
            final label =
                item['label'] as String? ??
                item['name'] as String? ??
                'Subtitles';
            if (url != null && url.isNotEmpty) {
              subtitleTracks.add(
                SubtitleTrack(url: url, label: label, language: label),
              );
            }
          }
        }
      }

      return _ResolvedProviderStream(
        videoUrls: [m3u8Url],
        headers: {
          'Referer': '$baseUrl/',
          'Origin': baseUrl,
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
        subtitleUrl: _englishSubtitleUrl(subtitleTracks),
        subtitleTracks: subtitleTracks.isEmpty ? null : subtitleTracks,
      );
    } catch (_) {
      return null;
    }
  }

  Future<VideoProviderSource?> _resolveSingleMegaPlayTarget({
    required ({
      String name,
      String description,
      String embedUrl,
      String baseUrl,
      String query,
    })
    target,
    required String lang,
  }) async {
    try {
      final querySuffix = target.query.isEmpty ? '' : '?${target.query}';
      final streamUrl = '${target.embedUrl}/$lang$querySuffix';

      _ResolvedProviderStream? resolvedStream;
      // MegaPlay / Gojo servers use encrypted AES-256 stream endpoints
      if (target.baseUrl.contains('megaplay.buzz') ||
          target.name.toLowerCase() == 'gojo') {
        resolvedStream = await _resolveMegaPlayEncryptedStream(
          streamUrl: streamUrl,
          baseUrl: target.baseUrl,
        );
      }

      // Fall back to direct/nested iframe extraction if needed
      resolvedStream ??= await _resolveDirectProviderStream(
        streamUrl: streamUrl,
        baseUrl: target.baseUrl,
        headers: {
          ..._embedHeadersForOrigin(target.baseUrl),
          'Sec-Fetch-Dest': 'iframe',
        },
      );
      if (resolvedStream == null || resolvedStream.videoUrls.isEmpty) {
        return null;
      }

      final subtitleTracks = _prioritizeKakashiSubtitleTracks(
        resolvedStream.subtitleTracks,
      );

      return VideoProviderSource(
        name: target.name,
        description: target.description,
        languageType: lang.toUpperCase(),
        videoUrls: resolvedStream.videoUrls,
        speedStatus: 'Fast',
        isEmbed: false,
        headers: resolvedStream.headers,
        subtitleUrl: _kakashiSubtitleUrl(
          subtitleTracks,
          resolvedStream.subtitleUrl,
        ),
        subtitleTracks: subtitleTracks,
        skipTimes: resolvedStream.skipTimes,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<VideoProviderSource>> _resolveMegaPlayNativeProviders({
    required String idType,
    required String id,
    required int episodeNumber,
    Anime? anime,
  }) async {
    if (kIsWeb) return const [];

    final providers = <VideoProviderSource>[];
    final providerIdSource = _providerIdSource(idType);
    final nativeTargets = [
      (
        name: 'Gojo',
        description: 'MegaPlay Buzz Native',
        embedUrl: 'https://megaplay.buzz/stream/$idType/$id/$episodeNumber',
        baseUrl: 'https://megaplay.buzz',
        query: 'server=gojo',
      ),
      (
        name: 'Kakashi',
        description: 'Anime Player Native',
        embedUrl: 'https://ani.megaplay.su/$idType/$id/$episodeNumber',
        baseUrl: 'https://ani.megaplay.su',
        query: '',
      ),
      (
        name: 'Luffy',
        description: 'ZokoAnime Native',
        embedUrl:
            'https://zokoanime.video/stream/$providerIdSource/$id/$episodeNumber',
        baseUrl: 'https://zokoanime.video',
        query: '',
      ),
      (
        name: 'Tanjiro',
        description: 'VidHawk Zuri Native',
        embedUrl:
            'https://vidhawk.buzz/embed/$providerIdSource/$id/$episodeNumber',
        baseUrl: 'https://vidhawk.buzz',
        query: 'server=$_tanjiroVidHawkServer',
      ),
    ];

    final resolutions = <Future<VideoProviderSource?>>[];
    for (final lang in ['sub', 'dub']) {
      for (final target in nativeTargets) {
        resolutions.add(
          _resolveSingleMegaPlayTarget(target: target, lang: lang),
        );
      }
    }

    final directResultsFuture = Future.wait(resolutions);
    final leviFuture = supportsLeviNativeStreaming
        ? _resolveLeviNativeProviders(
            idType: idType,
            id: id,
            episodeNumber: episodeNumber,
            anime: anime,
          ).timeout(const Duration(seconds: 8), onTimeout: () => const [])
        : Future.value(const <VideoProviderSource>[]);

    final results = await Future.wait([
      directResultsFuture.then(
        (list) => list.whereType<VideoProviderSource>().toList(),
      ),
      leviFuture,
    ]);

    for (final list in results) {
      providers.addAll(list);
    }

    return providers;
  }

  Future<List<VideoProviderSource>> _resolveLeviNativeProviders({
    required String idType,
    required String id,
    required int episodeNumber,
    Anime? anime,
  }) async {
    if (!supportsLeviNativeStreaming) return const [];
    final resolutions = <Future<VideoProviderSource?>>[];
    for (final server in ['Levi', 'Eren', 'Mikasa']) {
      for (final language in ['sub', 'dub']) {
        resolutions.add(
          _resolveLeviNativeProvider(
            idType: idType,
            id: id,
            episodeNumber: episodeNumber,
            language: language,
            anime: anime,
            serverName: server,
          ),
        );
      }
    }
    final results = await Future.wait(resolutions);
    return results.whereType<VideoProviderSource>().toList();
  }

  Future<VideoProviderSource?> _resolveLeviNativeProvider({
    required String idType,
    required String id,
    required int episodeNumber,
    required String language,
    Anime? anime,
    String serverName = 'Levi',
  }) async {
    if (!supportsLeviNativeStreaming) return null;
    var cancelled = false;
    final isDonghua = anime?.countryOfOrigin?.trim().toUpperCase() == 'CN';
    return LeviTorrentProvider(
          prepareStream: (url) =>
              prepareLeviNativeStream(url, episodeNumber: episodeNumber),
          stopStream: stopLeviNativeStream,
        )
        .resolve(
          idType: idType,
          id: id,
          episodeNumber: episodeNumber,
          language: language,
          isCancelled: () => cancelled,
          anime: anime,
          isDonghua: isDonghua,
          serverName: serverName,
          deferStreaming: true,
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            cancelled = true;
            return null;
          },
        );
  }

  Future<List<VideoProviderSource>> _getMegaPlayProviders(
    Anime anime,
    int episodeNumber,
  ) async {
    final catalogId = await _resolveMegaPlayCatalogId(anime.id, anime: anime);
    final nativeProviders = await _resolveMegaPlayNativeProviders(
      idType: catalogId.idType,
      id: catalogId.id,
      episodeNumber: episodeNumber,
      anime: anime,
    );
    final playableLanguages = nativeProviders
        .where((provider) => provider.videoUrls.isNotEmpty)
        .map((provider) => provider.languageType.toUpperCase())
        .toSet();
    if (playableLanguages.isEmpty) {
      playableLanguages.addAll(
        await _playableMegaPlayEmbedLanguages(
          idType: catalogId.idType,
          id: catalogId.id,
          episodeNumber: episodeNumber,
        ),
      );
    }
    if (playableLanguages.isEmpty) return const [];

    final providers = _buildMegaPlayEmbedProviders(
      idType: catalogId.idType,
      id: catalogId.id,
      episodeNumber: episodeNumber,
      includeLevi: !supportsLeviNativeStreaming,
    ).where((provider) => playableLanguages.contains(provider.languageType));

    return [...providers, ...nativeProviders];
  }

  List<VideoProviderSource> _sortAndDedupVideoProviders(
    Iterable<VideoProviderSource> providers,
  ) {
    final indexed = List<VideoProviderSource>.from(
      providers,
    ).asMap().entries.toList();
    indexed.sort((aEntry, bEntry) {
      final a = aEntry.value;
      final b = bEntry.value;

      final languageComparison = _providerLanguageRank(
        a.languageType,
      ).compareTo(_providerLanguageRank(b.languageType));
      if (languageComparison != 0) return languageComparison;

      final nameRankComparison = _providerNameRank(
        a.name,
      ).compareTo(_providerNameRank(b.name));
      if (nameRankComparison != 0) return nameRankComparison;

      if (a.isEmbed != b.isEmbed) return a.isEmbed ? 1 : -1;

      final nameComparison = a.name.compareTo(b.name);
      if (nameComparison != 0) return nameComparison;

      return aEntry.key.compareTo(bEntry.key);
    });

    final seen = <String>{};
    final deduped = <VideoProviderSource>[];
    for (final entry in indexed) {
      final provider = entry.value;
      final key =
          '${provider.name.toLowerCase()}|${provider.languageType.toUpperCase()}';
      if (seen.add(key)) deduped.add(provider);
    }
    return deduped;
  }

  int _providerLanguageRank(String languageType) {
    final language = languageType.toUpperCase().trim();
    if (language == 'SUB' || language == 'HSUB') return 0;
    if (language == 'DUB') return 1;
    return 2;
  }

  int _providerNameRank(String name) {
    switch (name.toLowerCase().trim()) {
      case 'gojo':
        return 0;
      case 'kakashi':
        return 1;
      case 'luffy':
        return 2;
      case 'tanjiro':
        return 3;
      case 'levi':
        return 4;
      case 'eren':
        return 5;
      case 'mikasa':
        return 6;
      default:
        return 10;
    }
  }

  @visibleForTesting
  List<VideoProviderSource> sortVideoProvidersForTesting(
    Iterable<VideoProviderSource> providers,
  ) {
    return _sortAndDedupVideoProviders(providers);
  }

  @visibleForTesting
  List<VideoProviderSource> buildMegaPlayEmbedProvidersForTesting({
    required String idType,
    required String id,
    required int episodeNumber,
  }) {
    return _buildMegaPlayEmbedProviders(
      idType: idType,
      id: id,
      episodeNumber: episodeNumber,
      includeLevi: idType == 'mal',
    );
  }

  final Map<String, String> _animeWaveAnimeIdCache = {};
  final Map<String, String> _aniNekoAnimeIdCache = {};
  final Map<String, String> _reAnimeAnimeIdCache = {};
  final Map<String, String> _miruroAnimeIdCache = {};
  final Map<String, String> _aniWavesRuAnimeIdCache = {};
  final Map<String, String> _animeXAnimeIdCache = {};

  Future<List<VideoProviderSource>> _resolveValidatedAniNekoServers(
    _AnimeLookupTarget target,
    int episodeNumber,
  ) async {
    const baseUrl = 'https://anineko.to';
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': '$baseUrl/',
    };

    final cachedSlug = _aniNekoAnimeIdCache[target.cacheKey];
    if (cachedSlug != null) {
      final cachedProvider = await _resolveAniNekoSlug(
        slug: cachedSlug,
        candidateTitle: target.title,
        target: target,
        episodeNumber: episodeNumber,
        baseUrl: baseUrl,
        headers: headers,
      );
      if (cachedProvider != null) return [cachedProvider];
      _aniNekoAnimeIdCache.remove(target.cacheKey);
    }

    final candidateMap = <String, _ProviderSearchCandidate>{};
    for (final alias in target.aliases.take(4)) {
      try {
        final searchUrl = Uri.parse(
          '$baseUrl/browser?keyword=${Uri.encodeQueryComponent(alias)}',
        );
        final searchRes = await _getResponse(
          searchUrl,
          headers: headers,
          timeout: const Duration(seconds: 5),
        );
        if (searchRes == null || searchRes.statusCode != 200) continue;
        for (final candidate in _parseWatchSearchCandidates(
          searchRes.body,
          baseUrl,
          target,
        )) {
          final existing = candidateMap[candidate.watchUrl];
          if (existing == null || candidate.score > existing.score) {
            candidateMap[candidate.watchUrl] = candidate;
          }
        }
      } catch (_) {}
    }

    final candidates = candidateMap.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    for (final candidate in candidates.take(8)) {
      if (candidate.score < 0.42) continue;
      final slug = RegExp(
        r'/watch/([^/?#]+)',
        caseSensitive: false,
      ).firstMatch(candidate.watchUrl)?.group(1);
      if (slug == null || slug.isEmpty) continue;

      final provider = await _resolveAniNekoSlug(
        slug: slug,
        candidateTitle: candidate.title,
        target: target,
        episodeNumber: episodeNumber,
        baseUrl: baseUrl,
        headers: headers,
      );
      if (provider != null) {
        _aniNekoAnimeIdCache[target.cacheKey] = slug;
        return [provider];
      }
    }

    return [];
  }

  Future<List<VideoProviderSource>> getVideoProvidersForEpisode(
    String animeId,
    int episodeNumber,
  ) async {
    final providers = <VideoProviderSource>[];
    try {
      final anime = await getAnimeById(animeId);
      if (anime != null) {
        providers.addAll(await _getMegaPlayProviders(anime, episodeNumber));
      }
    } catch (_) {}

    if (!_enableScraperProviders) {
      return _sortAndDedupVideoProviders(providers);
    }

    // Append legacy site-specific scrapers only when explicitly enabled.
    try {
      final anime = await getAnimeById(animeId);
      final target = await _buildLookupTarget(animeId, anime);
      if (target.aliases.isNotEmpty) {
        final results = await Future.wait([
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://aniwaves.ru',
            providerName: 'Goku',
            description: 'AniWaves Stream',
            cache: _aniWavesRuAnimeIdCache,
          ),
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://anizone.to',
            providerName: 'Zoro',
            description: 'AniZone Stream',
            cache: _animeWaveAnimeIdCache,
          ),
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://animex.one',
            providerName: 'Eren',
            description: 'AnimeX Stream',
            cache: _animeXAnimeIdCache,
          ),
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://reanime.to',
            providerName: 'Sukuna',
            description: 'ReAnime Stream',
            cache: _reAnimeAnimeIdCache,
          ),
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://www.miruro.bz',
            providerName: 'Itachi',
            description: 'Miruro Stream',
            cache: _miruroAnimeIdCache,
          ),
          _resolveValidatedAniNekoServers(target, episodeNumber),
        ]);
        for (final r in results) {
          providers.addAll(r);
        }
      }
    } catch (_) {}

    return _sortAndDedupVideoProviders(providers);
  }

  /// Streams only MegaPlay providers with a verified source for the requested
  /// episode. Legacy scraper-backed providers stay disabled until live checks.
  Stream<List<VideoProviderSource>> streamVideoProvidersForEpisode(
    String animeId,
    int episodeNumber,
  ) async* {
    // Yield source-aware embed URLs before doing any provider probing. Native
    // extraction is an optional upgrade and must never block the player UI.
    List<VideoProviderSource> current = [];
    Anime? anime;
    ({String idType, String id})? catalogId;
    List<VideoProviderSource> embedProviders = [];
    try {
      anime = await getAnimeById(animeId);
      if (anime == null) return;
      catalogId = await _resolveMegaPlayCatalogId(anime.id, anime: anime);
      embedProviders = _buildMegaPlayEmbedProviders(
        idType: catalogId.idType,
        id: catalogId.id,
        episodeNumber: episodeNumber,
        includeLevi: !supportsLeviNativeStreaming,
      );
    } catch (_) {
      return;
    }

    // Resolve native HLS providers as soon as they are ready. Prefer a native
    // source before initializing an embedded browser player.
    if (!kIsWeb) {
      final providerIdSource = _providerIdSource(catalogId.idType);
      final nativeTargets = [
        (
          name: 'Gojo',
          description: 'MegaPlay Buzz Native',
          embedUrl:
              'https://megaplay.buzz/stream/${catalogId.idType}/${catalogId.id}/$episodeNumber',
          baseUrl: 'https://megaplay.buzz',
          query: 'server=gojo',
        ),
        (
          name: 'Kakashi',
          description: 'Anime Player Native',
          embedUrl:
              'https://ani.megaplay.su/${catalogId.idType}/${catalogId.id}/$episodeNumber',
          baseUrl: 'https://ani.megaplay.su',
          query: '',
        ),
        (
          name: 'Luffy',
          description: 'ZokoAnime Native',
          embedUrl:
              'https://zokoanime.video/stream/$providerIdSource/${catalogId.id}/$episodeNumber',
          baseUrl: 'https://zokoanime.video',
          query: '',
        ),
        (
          name: 'Tanjiro',
          description: 'VidHawk Zuri Native',
          embedUrl:
              'https://vidhawk.buzz/embed/$providerIdSource/${catalogId.id}/$episodeNumber',
          baseUrl: 'https://vidhawk.buzz',
          query: 'server=$_tanjiroVidHawkServer',
        ),
      ];

      final preferredLang =
          storage?.getDefaultAudioPreference().toLowerCase() == 'dub'
          ? 'dub'
          : 'sub';
      final otherLang = preferredLang == 'sub' ? 'dub' : 'sub';
      final langOrder = [preferredLang, otherLang];

      final nativeFutures = <Future<VideoProviderSource?>>[];
      for (final lang in langOrder) {
        for (final target in nativeTargets) {
          nativeFutures.add(
            _resolveSingleMegaPlayTarget(target: target, lang: lang),
          );
        }
      }

      if (supportsLeviNativeStreaming) {
        for (final server in ['Levi', 'Eren', 'Mikasa']) {
          for (final lang in ['sub', 'dub']) {
            nativeFutures.add(
              _resolveLeviNativeProvider(
                idType: catalogId.idType,
                id: catalogId.id,
                episodeNumber: episodeNumber,
                language: lang,
                anime: anime,
                serverName: server,
              ),
            );
          }
        }
      }

      final controller = StreamController<List<VideoProviderSource>>();
      final resolvedNative = <VideoProviderSource>[];
      var activeCount = nativeFutures.length;
      var hasYielded = false;

      for (final future in nativeFutures) {
        future
            .then((result) {
              if (result != null) {
                resolvedNative.add(result);
                current = _sortAndDedupVideoProviders([
                  ...resolvedNative,
                  ...embedProviders,
                ]);
                hasYielded = true;
                if (!controller.isClosed) {
                  controller.add(List.unmodifiable(current));
                }
              }
            })
            .catchError((_) {})
            .whenComplete(() {
              activeCount--;
              if (activeCount <= 0) {
                if (!hasYielded && embedProviders.isNotEmpty) {
                  current = _sortAndDedupVideoProviders(embedProviders);
                  if (!controller.isClosed) {
                    controller.add(List.unmodifiable(current));
                  }
                  hasYielded = true;
                }
                if (!controller.isClosed) {
                  controller.close();
                }
              }
            });
      }

      Timer? fallbackTimer;
      fallbackTimer = Timer(const Duration(milliseconds: 3500), () {
        if (!hasYielded && embedProviders.isNotEmpty && !controller.isClosed) {
          hasYielded = true;
          current = _sortAndDedupVideoProviders(embedProviders);
          controller.add(List.unmodifiable(current));
        }
      });

      await for (final updatedList in controller.stream) {
        yield updatedList;
      }
      fallbackTimer.cancel();
    } else {
      current = _sortAndDedupVideoProviders(embedProviders);
      if (current.isNotEmpty) yield List.unmodifiable(current);
    }

    if (!_enableScraperProviders) return;

    // Fire legacy site-specific scrapers concurrently when enabled.
    try {
      final target = await _buildLookupTarget(animeId, anime);
      if (target.aliases.isNotEmpty) {
        final scraperFutures = [
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://aniwaves.ru',
            providerName: 'Goku',
            description: 'AniWaves Stream',
            cache: _aniWavesRuAnimeIdCache,
          ),
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://anizone.to',
            providerName: 'Zoro',
            description: 'AniZone Stream',
            cache: _animeWaveAnimeIdCache,
          ),
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://animex.one',
            providerName: 'Eren',
            description: 'AnimeX Stream',
            cache: _animeXAnimeIdCache,
          ),
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://reanime.to',
            providerName: 'Sukuna',
            description: 'ReAnime Stream',
            cache: _reAnimeAnimeIdCache,
          ),
          _resolveAniWatchStyleServers(
            target: target,
            episodeNumber: episodeNumber,
            baseUrl: 'https://www.miruro.bz',
            providerName: 'Itachi',
            description: 'Miruro Stream',
            cache: _miruroAnimeIdCache,
          ),
          _resolveValidatedAniNekoServers(target, episodeNumber),
        ];

        final controller = StreamController<List<VideoProviderSource>>();
        var activeCount = scraperFutures.length;

        for (final future in scraperFutures) {
          future
              .then((results) {
                if (results.isNotEmpty) {
                  current = _sortAndDedupVideoProviders([
                    ...current,
                    ...results,
                  ]);
                  if (!controller.isClosed) {
                    controller.add(List.unmodifiable(current));
                  }
                }
              })
              .catchError((_) {})
              .whenComplete(() {
                activeCount--;
                if (activeCount <= 0 && !controller.isClosed) {
                  controller.close();
                }
              });
        }

        await for (final updatedList in controller.stream) {
          yield updatedList;
        }
      }
    } catch (_) {}
  }

  // Get single episode details
  Future<Episode?> getEpisodeById(String animeId, String episodeId) async {
    final episodes = await getEpisodesForAnime(animeId);
    try {
      return episodes.firstWhere((ep) => ep.id == episodeId);
    } catch (_) {
      return null;
    }
  }

  // --- New Categories for AniLab Home Screen Layout ---

  // --- New Categories for AniLab Home Screen Layout ---

  Future<List<Anime>> _fetchAniListCategory(
    String query,
    Map<String, dynamic> variables,
  ) async {
    if (metadataProvider == MetadataProvider.myAnimeList) return [];
    try {
      final response = await _client
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = decoded['data']?['Page']?['media'] as List?;
        if (list != null) {
          final mapped = list
              .whereType<Map<String, dynamic>>()
              .map((item) => parseAniListMedia(item))
              .toList();
          final available = await _preserveMetadataResults(mapped);
          _cacheAnimeList(available);
          return available;
        }
      }
    } catch (_) {}
    return [];
  }

  String _getCurrentSeason() {
    final month = DateTime.now().month;
    if (month <= 3) return 'WINTER';
    if (month <= 6) return 'SPRING';
    if (month <= 9) return 'SUMMER';
    return 'FALL';
  }

  // Get Hot Right Now (popular current season)
  Future<List<Anime>> getHotRightNow() async {
    final cached = await _readFilteredCategoryCache(
      'hot_right_now',
      upcomingOnly: false,
    );
    if (cached != null) {
      return cached;
    }

    const query = r'''
      query ($page: Int, $perPage: Int, $season: MediaSeason, $seasonYear: Int) {
        Page (page: $page, perPage: $perPage) {
          media (type: ANIME, season: $season, seasonYear: $seasonYear, sort: POPULARITY_DESC, isAdult: false, format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
          }
        }
      }
    ''';
    final currentYear = DateTime.now().year;
    final currentSeason = _getCurrentSeason();

    final list = await _fetchAniListCategory(query, {
      'page': 1,
      'perPage': 30,
      'season': currentSeason,
      'seasonYear': currentYear,
    });
    if (list.isNotEmpty) {
      return _saveFilteredCategoryList(
        'hot_right_now',
        list,
        upcomingOnly: false,
      );
    }
    // Backup: Jikan current season
    try {
      final decoded = await _getJsonObject(
        _jikanUri('seasons/now', {'limit': '30'}),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final jikanList = data.map((item) => _parseJikanAnime(item)).toList();
        final filtered = await _saveFilteredCategoryList(
          'hot_right_now',
          jikanList,
          upcomingOnly: false,
        );
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return List<Anime>.from(_fallbackAnimeList);
  }

  // Get Everyone's Watching (popular of all time)
  Future<List<Anime>> getEveryonesWatching() async {
    final cached = await _readFilteredCategoryCache(
      'everyones_watching',
      upcomingOnly: false,
    );
    if (cached != null) {
      return cached;
    }

    const query = r'''
      query ($page: Int, $perPage: Int) {
        Page (page: $page, perPage: $perPage) {
          media (type: ANIME, sort: POPULARITY_DESC, isAdult: false, format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
          }
        }
      }
    ''';
    final list = await _fetchAniListCategory(query, {'page': 1, 'perPage': 30});
    if (list.isNotEmpty) {
      return _saveFilteredCategoryList(
        'everyones_watching',
        list,
        upcomingOnly: false,
      );
    }
    // Backup: Jikan top anime by popularity
    try {
      final decoded = await _getJsonObject(
        _jikanUri('top/anime', {'filter': 'bypopularity', 'limit': '30'}),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final jikanList = data.map((item) => _parseJikanAnime(item)).toList();
        final filtered = await _saveFilteredCategoryList(
          'everyones_watching',
          jikanList,
          upcomingOnly: false,
        );
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return List<Anime>.from(_fallbackAnimeList);
  }

  // Get top-rated animes from previous year in descending order by score
  Future<List<Anime>> getRecentlyUpdated() async {
    final cached = await _readFilteredCategoryCache(
      'recently_updated',
      upcomingOnly: false,
    );
    if (cached != null) {
      return cached;
    }

    final previousYear = DateTime.now().year - 1;
    const query = r'''
      query ($page: Int, $perPage: Int, $year: Int) {
        Page (page: $page, perPage: $perPage) {
          media (
            type: ANIME,
            seasonYear: $year,
            sort: SCORE_DESC,
            isAdult: false,
            averageScore_greater: 60,
            format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]
          ) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
          }
        }
      }
    ''';
    final list = await _fetchAniListCategory(query, {
      'page': 1,
      'perPage': 30,
      'year': previousYear,
    });
    if (list.isNotEmpty) {
      // Ensure descending sort by rating client-side as well
      list.sort((a, b) => b.rating.compareTo(a.rating));
      return _saveFilteredCategoryList(
        'recently_updated',
        list,
        upcomingOnly: false,
      );
    }
    // Jikan fallback: top anime from previous year
    try {
      if (metadataProvider == MetadataProvider.aniList) return [];
      final response = await _client.get(
        Uri.parse(
          'https://api.jikan.moe/v4/anime?start_year=$previousYear&end_year=$previousYear&order_by=score&sort=desc&limit=30&sfw=true',
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['data'] as List<dynamic>? ?? [];
        final results = items.map((item) {
          final images = item['images']?['jpg'] ?? {};
          final title = item['title_english'] ?? item['title'] ?? 'Unknown';
          return Anime(
            id: item['mal_id']?.toString() ?? '',
            title: title,
            posterUrl: images['large_image_url'] ?? images['image_url'] ?? '',
            backdropUrl: images['large_image_url'] ?? images['image_url'] ?? '',
            rating: (item['score'] ?? 0).toDouble(),
            year: previousYear.toString(),
            genres: (item['genres'] as List<dynamic>? ?? [])
                .map((g) => g['name']?.toString() ?? '')
                .where((g) => g.isNotEmpty)
                .toList(),
            status: _mapStatus(item['status'] ?? ''),
            description: item['synopsis'] ?? '',
            totalEpisodes: item['episodes'] ?? 0,
            malId: item['mal_id']?.toString(),
            alternativeTitles: _titleAliases([
              item['title_english'],
              item['title'],
              item['title_japanese'],
            ]),
          );
        }).toList();
        results.sort((a, b) => b.rating.compareTo(a.rating));
        final res = results.isNotEmpty
            ? results
            : List<Anime>.from(_fallbackAnimeList);
        final filtered = await _saveFilteredCategoryList(
          'recently_updated',
          res,
          upcomingOnly: false,
        );
        return filtered;
      }
    } catch (_) {}
    return List<Anime>.from(_fallbackAnimeList);
  }

  // Get Top Picks (highest scored)
  Future<List<Anime>> getTopPicks() async {
    final cached = await _readFilteredCategoryCache(
      'top_picks',
      upcomingOnly: false,
    );
    if (cached != null) {
      return cached;
    }

    const query = r'''
      query ($page: Int, $perPage: Int) {
        Page (page: $page, perPage: $perPage) {
          media (type: ANIME, sort: SCORE_DESC, isAdult: false, format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
          }
        }
      }
    ''';
    final list = await _fetchAniListCategory(query, {'page': 1, 'perPage': 30});
    if (list.isNotEmpty) {
      return _saveFilteredCategoryList('top_picks', list, upcomingOnly: false);
    }
    // Backup: Jikan top anime
    try {
      final decoded = await _getJsonObject(
        _jikanUri('top/anime', {'limit': '30'}),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final jikanList = data.map((item) => _parseJikanAnime(item)).toList();
        final filtered = await _saveFilteredCategoryList(
          'top_picks',
          jikanList,
          upcomingOnly: false,
        );
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return List<Anime>.from(_fallbackAnimeList);
  }

  // Get Top Movies
  Future<List<Anime>> getTopMovies() async {
    final cached = await _readFilteredCategoryCache(
      'top_movies',
      upcomingOnly: false,
    );
    if (cached != null) {
      return cached;
    }

    const query = r'''
      query ($page: Int, $perPage: Int) {
        Page (page: $page, perPage: $perPage) {
          media (type: ANIME, format: MOVIE, sort: SCORE_DESC, isAdult: false) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
          }
        }
      }
    ''';
    final list = await _fetchAniListCategory(query, {'page': 1, 'perPage': 30});
    if (list.isNotEmpty) {
      return _saveFilteredCategoryList('top_movies', list, upcomingOnly: false);
    }
    // Backup: Jikan top movies
    try {
      final decoded = await _getJsonObject(
        _jikanUri('top/anime', {'type': 'movie', 'limit': '30'}),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final jikanList = data.map((item) => _parseJikanAnime(item)).toList();
        final filtered = await _saveFilteredCategoryList(
          'top_movies',
          jikanList,
          upcomingOnly: false,
        );
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    final movieFallbacks = _fallbackAnimeList
        .where((a) => a.type == 'MOVIE')
        .toList();
    return movieFallbacks.isNotEmpty
        ? movieFallbacks
        : List<Anime>.from(_fallbackAnimeList);
  }

  // Get Curated For You (favorites desc)
  Future<List<Anime>> getCuratedForYou() async {
    final cached = await _readFilteredCategoryCache(
      'curated_for_you',
      upcomingOnly: false,
    );
    if (cached != null) {
      return cached;
    }

    const query = r'''
      query ($page: Int, $perPage: Int) {
        Page (page: $page, perPage: $perPage) {
          media (type: ANIME, sort: FAVOURITES_DESC, isAdult: false, format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
          }
        }
      }
    ''';
    final list = await _fetchAniListCategory(query, {'page': 2, 'perPage': 30});
    if (list.isNotEmpty) {
      return _saveFilteredCategoryList(
        'curated_for_you',
        list,
        upcomingOnly: false,
      );
    }
    // Backup: Jikan top favorites
    try {
      final decoded = await _getJsonObject(
        _jikanUri('top/anime', {'filter': 'favorite', 'limit': '30'}),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final jikanList = data.map((item) => _parseJikanAnime(item)).toList();
        final filtered = await _saveFilteredCategoryList(
          'curated_for_you',
          jikanList,
          upcomingOnly: false,
        );
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return List<Anime>.from(_fallbackAnimeList);
  }

  // Get Recommended
  Future<List<Anime>> getRecommended() async {
    final cached = await _readFilteredCategoryCache(
      'recommended',
      upcomingOnly: false,
    );
    if (cached != null) {
      return cached;
    }

    const query = r'''
      query ($page: Int, $perPage: Int) {
        Page (page: $page, perPage: $perPage) {
          media (type: ANIME, sort: POPULARITY_DESC, isAdult: false, format_in: [TV, TV_SHORT, MOVIE, OVA, ONA, SPECIAL]) {
            id
            idMal
            title { romaji english native userPreferred }
            coverImage { extraLarge large medium }
            bannerImage
            averageScore
            status
            genres
            episodes
            seasonYear
            startDate { year month day }
            duration
            format
          }
        }
      }
    ''';
    final list = await _fetchAniListCategory(query, {'page': 1, 'perPage': 30});
    if (list.isNotEmpty) {
      return _saveFilteredCategoryList(
        'recommended',
        list,
        upcomingOnly: false,
      );
    }
    // Backup: Jikan top popularity page 2
    try {
      final decoded = await _getJsonObject(
        _jikanUri('top/anime', {
          'filter': 'bypopularity',
          'page': '2',
          'limit': '30',
        }),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final jikanList = data.map((item) => _parseJikanAnime(item)).toList();
        final filtered = await _saveFilteredCategoryList(
          'recommended',
          jikanList,
          upcomingOnly: false,
        );
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return List<Anime>.from(_fallbackAnimeList);
  }

  // Get Schedule
  Future<List<Anime>> getSchedule() async {
    if (storage != null) {
      final cached = storage!.getCachedCategoryList(_cacheKey('schedule'));
      if (cached != null && cached.isNotEmpty) {
        final todayStr =
            "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
        // Ensure cache contains data for today's date
        final hasTodayData = cached.any((a) => a.nextEpisodeDate == todayStr);
        if (hasTodayData) {
          _cacheAnimeList(cached);
          return cached;
        }
      }
    }
    try {
      if (metadataProvider == MetadataProvider.myAnimeList) {
        throw StateError('Use MAL schedule');
      }
      final now = DateTime.now();
      // Fetch schedule from 3 days ago to 10 days in the future (matching schedule_screen.dart range)
      final start =
          now.subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000;
      final end =
          now.add(const Duration(days: 10)).millisecondsSinceEpoch ~/ 1000;

      const query = r'''
        query ($start: Int, $end: Int, $page: Int) {
          Page (page: $page, perPage: 50) {
            pageInfo {
              hasNextPage
            }
            airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
              id
              airingAt
              episode
              media {
                id
                idMal
                title { romaji english native userPreferred }
                coverImage { extraLarge large medium }
                bannerImage
                averageScore
                status
                genres
                episodes
                seasonYear
                startDate { year month day }
                duration
                format
                description
              }
            }
          }
        }
      ''';

      final List<Anime> scheduleAnimes = [];
      final Set<String> seenScheduleKeys = {};

      final pageFutures = [1, 2, 3]
          .map(
            (page) => _client
                .post(
                  Uri.parse('https://graphql.anilist.co'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                  },
                  body: jsonEncode({
                    'query': query,
                    'variables': {'start': start, 'end': end, 'page': page},
                  }),
                )
                .timeout(const Duration(seconds: 5)),
          )
          .toList();

      final responses = await Future.wait(
        pageFutures,
      ).catchError((_) => <http.Response>[]);

      for (final response in responses) {
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final pageData = decoded['data']?['Page'];
          final list = pageData?['airingSchedules'] as List?;

          if (list != null && list.isNotEmpty) {
            for (final item in list) {
              if (item is! Map<String, dynamic>) continue;
              final media = item['media'] as Map<String, dynamic>?;
              final airingAt = item['airingAt'] as int?;
              if (media == null || airingAt == null) continue;

              final anime = parseAniListMedia(media);
              if (anime.id == 'unknown') continue;

              final airingDateTime = DateTime.fromMillisecondsSinceEpoch(
                airingAt * 1000,
              ).toLocal();
              final dateStr =
                  "${airingDateTime.year}-${airingDateTime.month.toString().padLeft(2, '0')}-${airingDateTime.day.toString().padLeft(2, '0')}";

              final scheduleKey = '${anime.id}_$dateStr';
              if (seenScheduleKeys.contains(scheduleKey)) continue;
              seenScheduleKeys.add(scheduleKey);

              final isPm = airingDateTime.hour >= 12;
              final displayHour = airingDateTime.hour == 0
                  ? 12
                  : (airingDateTime.hour > 12
                        ? airingDateTime.hour - 12
                        : airingDateTime.hour);
              final minuteStr = airingDateTime.minute.toString().padLeft(
                2,
                '0',
              );
              final period = isPm ? 'PM' : 'AM';
              final broadcastTime = '$displayHour:$minuteStr $period';

              final weekdays = [
                'monday',
                'tuesday',
                'wednesday',
                'thursday',
                'friday',
                'saturday',
                'sunday',
              ];
              final broadcastDay = weekdays[airingDateTime.weekday - 1];

              final enrichedAnime = Anime(
                id: scheduleKey,
                title: anime.title,
                description: anime.description,
                posterUrl: anime.posterUrl,
                backdropUrl: anime.backdropUrl,
                rating: anime.rating,
                status: anime.status,
                genres: anime.genres,
                totalEpisodes: item['episode'] as int? ?? anime.totalEpisodes,
                year: anime.year,
                episodeDurationMinutes: anime.episodeDurationMinutes,
                nextEpisodeDate: dateStr,
                broadcastDay: broadcastDay,
                broadcastTime: broadcastTime,
                type: anime.type,
                malId: anime.malId,
                aniListId: anime.aniListId,
                alternativeTitles: anime.alternativeTitles,
              );

              scheduleAnimes.add(enrichedAnime);
            }
          }
        }
      }

      if (scheduleAnimes.isNotEmpty) {
        _cacheAnimeList(scheduleAnimes);
        if (storage != null) {
          await storage!.saveCategoryListToCache(
            _cacheKey('schedule'),
            scheduleAnimes,
          );
        }
        return scheduleAnimes;
      }
    } catch (_) {}

    // Backup: Jikan schedules API
    try {
      final decoded = await _getJsonObject(
        _jikanUri('schedules', {'limit': '50'}),
      );
      final data = decoded?['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final List<Anime> scheduleAnimes = [];
        final Set<String> seenScheduleKeys = {};
        final now = DateTime.now();
        final weekdays = [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday',
        ];

        for (final item in data) {
          if (item is! Map<String, dynamic>) continue;
          final anime = _parseJikanAnime(item);
          final rawDay =
              (item['broadcast']?['day'] as String?)?.toLowerCase() ?? 'monday';
          final broadcastTime =
              item['broadcast']?['time'] as String? ?? '6:30 PM';

          int targetWeekdayIndex = 0;
          for (int w = 0; w < weekdays.length; w++) {
            if (rawDay.contains(weekdays[w])) {
              targetWeekdayIndex = w;
              break;
            }
          }

          for (int i = -3; i <= 10; i++) {
            final date = now.add(Duration(days: i));
            if (date.weekday - 1 == targetWeekdayIndex) {
              final dateStr =
                  "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
              final scheduleKey = '${anime.id}_$dateStr';
              if (seenScheduleKeys.add(scheduleKey)) {
                scheduleAnimes.add(
                  anime.copyWith(
                    id: scheduleKey,
                    nextEpisodeDate: dateStr,
                    broadcastDay: weekdays[targetWeekdayIndex],
                    broadcastTime: broadcastTime,
                  ),
                );
              }
            }
          }
        }
        if (scheduleAnimes.isNotEmpty) {
          _cacheAnimeList(scheduleAnimes);
          if (storage != null) {
            await storage!.saveCategoryListToCache(
              _cacheKey('schedule'),
              scheduleAnimes,
            );
          }
          return scheduleAnimes;
        }
      }
    } catch (_) {}

    // Fallback schedule with computed date strings for offline/fallback mode
    final List<Anime> fallbackSchedule = [];
    final now = DateTime.now();
    final weekdays = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];

    for (int i = -3; i <= 10; i++) {
      final date = now.add(Duration(days: i));
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final dayName = weekdays[date.weekday - 1];

      final animeIndex1 = (i.abs() + 3) % _fallbackAnimeList.length;
      final animeIndex2 = (i.abs() + 7) % _fallbackAnimeList.length;

      final base1 = _fallbackAnimeList[animeIndex1];
      final base2 = _fallbackAnimeList[animeIndex2];

      fallbackSchedule.add(
        base1.copyWith(
          id: '${base1.id}_$dateStr',
          nextEpisodeDate: dateStr,
          broadcastDay: dayName,
          broadcastTime: '6:30 PM',
        ),
      );
      if (base1.id != base2.id) {
        fallbackSchedule.add(
          base2.copyWith(
            id: '${base2.id}_$dateStr',
            nextEpisodeDate: dateStr,
            broadcastDay: dayName,
            broadcastTime: '9:00 PM',
          ),
        );
      }
    }

    return fallbackSchedule;
  }

  // Get Upcoming Anime (AniList directly)
  Future<List<Anime>> getUpcomingAnime() async {
    final cached = await _readFilteredCategoryCache(
      'upcoming',
      upcomingOnly: true,
    );
    if (cached != null) {
      return cached;
    }

    try {
      const query = r'''
        query ($page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC, isAdult: false) {
              id
              idMal
              title { romaji english native userPreferred }
              coverImage { extraLarge large medium }
              bannerImage
              averageScore
              status
              genres
              episodes
              seasonYear
              startDate { year month day }
              nextAiringEpisode { episode airingAt }
              duration
              description
              format
            }
          }
        }
      ''';
      final list = await _fetchAniListCategory(query, {
        'page': 1,
        'perPage': 30,
      });
      if (list.isNotEmpty) {
        return _saveFilteredCategoryList('upcoming', list, upcomingOnly: true);
      }
    } catch (_) {}

    // Fallback to Jikan seasons/upcoming
    try {
      final decoded = await _getJsonObject(
        _jikanUri('seasons/upcoming', {'limit': '30'}),
      );
      final data = decoded?['data'] as List?;
      if (data != null) {
        final list = data.map((item) => _parseJikanAnime(item)).toList();
        final filtered = await _saveFilteredCategoryList(
          'upcoming',
          list,
          upcomingOnly: true,
        );
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (_) {}

    return [];
  }
}

// --- Riverpod Future Providers for Jikan API endpoints ---

final trendingAnimeProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getTrendingAnime();
});

final recentReleasesProvider = FutureProvider<List<Episode>>((ref) async {
  return ref.watch(animeServiceProvider).getRecentReleases();
});

final animeDetailsProvider = FutureProvider.family<Anime?, String>((
  ref,
  id,
) async {
  return ref.watch(animeServiceProvider).getAnimeById(id);
});

final animeExtraInfoProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) async {
      return ref.watch(animeServiceProvider).getMetadataExtraInfo(id);
    });

final animeEpisodesProvider = FutureProvider.family<List<Episode>, String>((
  ref,
  id,
) async {
  return ref.watch(animeServiceProvider).getEpisodesForAnime(id);
});

final videoProvidersProvider =
    StreamProvider.family<
      List<VideoProviderSource>,
      ({String animeId, int episodeNumber})
    >((ref, params) {
      return ref
          .watch(animeServiceProvider)
          .streamVideoProvidersForEpisode(params.animeId, params.episodeNumber);
    });

final animeCharactersProvider = FutureProvider.family<List<Character>, String>((
  ref,
  id,
) async {
  return ref.watch(animeServiceProvider).getCharactersForAnime(id);
});

final recommendedAnimeProvider = FutureProvider.family<List<Anime>, String>((
  ref,
  id,
) async {
  final service = ref.watch(animeServiceProvider);
  return service.getRecommendationsForAnime(id);
});

// New Providers for Home Screen layout

final hotRightNowProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getHotRightNow();
});

final everyonesWatchingProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getEveryonesWatching();
});

final recentlyUpdatedProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getRecentlyUpdated();
});

final topPicksProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getTopPicks();
});

final topMoviesProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getTopMovies();
});

final curatedForYouProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getCuratedForYou();
});

final recommendedProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getRecommended();
});

final scheduleProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getSchedule();
});

final upcomingAnimeProvider = FutureProvider<List<Anime>>((ref) async {
  return ref.watch(animeServiceProvider).getUpcomingAnime();
});
