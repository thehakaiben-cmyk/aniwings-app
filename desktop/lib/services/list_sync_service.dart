import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/anime.dart';
import '../models/external_list_integration.dart';
import '../models/watch_entry.dart';
import 'storage_service.dart';

export '../models/external_list_integration.dart';

final listSyncServiceProvider = Provider<ListSyncService>((ref) {
  final service = ListSyncService(storage: ref.watch(storageServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});

class ExternalListSyncException implements Exception {
  final String message;

  const ExternalListSyncException(this.message);

  @override
  String toString() => message;
}

class ExternalListSyncResult {
  final ExternalListProvider provider;
  final String username;
  final int scannedCount;
  final int importedCount;
  final int unchangedCount;
  final int skippedCount;
  final List<String> importedTitles;

  const ExternalListSyncResult({
    required this.provider,
    required this.username,
    required this.scannedCount,
    required this.importedCount,
    required this.unchangedCount,
    required this.skippedCount,
    required this.importedTitles,
  });
}

class ExternalListProgressSyncResult {
  final ExternalListProvider provider;
  final String username;
  final int progress;
  final bool isCompleted;

  const ExternalListProgressSyncResult({
    required this.provider,
    required this.username,
    required this.progress,
    required this.isCompleted,
  });
}

class ExternalListAuthorizationStart {
  final ExternalListProvider provider;
  final Uri authorizationUri;
  final ExternalListAuthResponseMode responseMode;

  const ExternalListAuthorizationStart({
    required this.provider,
    required this.authorizationUri,
    required this.responseMode,
  });
}

class ExternalListOAuthConfig {
  static const String _bundledAniListClientId = '39669';
  static const String _bundledAniListRedirectUri =
      'https://anilist.co/api/v2/oauth/pin';
  static const String _bundledMalClientId = '9d65f887365fdad91bb0503c2c84fc01';

  static const String _aniwingsAniListClientId = String.fromEnvironment(
    'ANIWINGS_ANILIST_CLIENT_ID',
  );
  static const String _aniwingsAniListRedirectUri = String.fromEnvironment(
    'ANIWINGS_ANILIST_REDIRECT_URI',
  );
  static const String _aniListClientId = String.fromEnvironment(
    'ANILIST_CLIENT_ID',
  );
  static const String _aniListRedirectUri = String.fromEnvironment(
    'ANILIST_REDIRECT_URI',
  );

  static const String _aniwingsMalClientId = String.fromEnvironment(
    'ANIWINGS_MAL_CLIENT_ID',
  );
  static const String _aniwingsMalRedirectUri = String.fromEnvironment(
    'ANIWINGS_MAL_REDIRECT_URI',
  );
  static const String _malClientId = String.fromEnvironment('MAL_CLIENT_ID');
  static const String _malRedirectUri = String.fromEnvironment(
    'MAL_REDIRECT_URI',
  );

  final ExternalListProvider provider;
  final String clientId;
  final String redirectUri;

  const ExternalListOAuthConfig({
    required this.provider,
    required this.clientId,
    required this.redirectUri,
  });

  bool get hasClientId => clientId.trim().isNotEmpty;

  // AniList's implicit OAuth grant uses the redirect URI registered with the
  // client by default. Supplying one is only needed when a build provides a
  // different, app-owned callback URI.
  bool get requiresExplicitRedirectUri {
    return provider == ExternalListProvider.aniList &&
        redirectUri != _bundledAniListRedirectUri;
  }

  bool get usesCodeGrant {
    return provider == ExternalListProvider.myAnimeList;
  }

  static ExternalListOAuthConfig forProvider(ExternalListProvider provider) {
    return switch (provider) {
      ExternalListProvider.aniList => ExternalListOAuthConfig(
        provider: provider,
        clientId: _firstNonEmpty(
          _aniwingsAniListClientId,
          _aniListClientId,
          _bundledAniListClientId,
        ),
        redirectUri: _firstNonEmpty(
          _aniwingsAniListRedirectUri,
          _aniListRedirectUri,
          _bundledAniListRedirectUri,
        ),
      ),
      ExternalListProvider.myAnimeList => ExternalListOAuthConfig(
        provider: provider,
        clientId: _firstNonEmpty(
          _aniwingsMalClientId,
          _malClientId,
          _bundledMalClientId,
        ),
        redirectUri: _firstNonEmpty(
          _aniwingsMalRedirectUri,
          _malRedirectUri,
          'aniwings://oauth/mal',
        ),
      ),
    };
  }
}

class ListSyncService {
  final StorageService storage;
  final http.Client _client;
  final bool _ownsClient;
  final Uri _aniListEndpoint;
  final Uri _jikanBaseUri;
  final Uri _myAnimeListApiBaseUri;

  ListSyncService({
    required this.storage,
    http.Client? client,
    Uri? aniListEndpoint,
    Uri? jikanBaseUri,
    Uri? myAnimeListApiBaseUri,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _aniListEndpoint =
           aniListEndpoint ?? Uri.parse('https://graphql.anilist.co'),
       _jikanBaseUri = jikanBaseUri ?? Uri.parse('https://api.jikan.moe'),
       _myAnimeListApiBaseUri =
           myAnimeListApiBaseUri ?? Uri.parse('https://api.myanimelist.net');

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Map<ExternalListProvider, ExternalListConnection> getConnections() {
    return storage.getExternalListConnections();
  }

  ExternalListConnection? getConnection(ExternalListProvider provider) {
    return storage.getExternalListConnection(provider);
  }

  bool hasPendingAuthorization(ExternalListProvider provider) {
    return storage.getExternalListPendingAuthorization(provider) != null;
  }

  Future<ExternalListAuthorizationStart> beginAuthorization(
    ExternalListProvider provider,
  ) async {
    final activeConnection = storage.getActiveExternalListConnection();
    if (activeConnection != null && activeConnection.provider != provider) {
      throw ExternalListSyncException(
        'Disconnect ${activeConnection.provider.label} before syncing ${provider.label}. Only one list sync account can be active.',
      );
    }

    final config = ExternalListOAuthConfig.forProvider(provider);
    if (!config.hasClientId) {
      throw ExternalListSyncException(
        '${provider.label} OAuth is not configured. Add ${_clientIdDefineName(provider)} as a --dart-define value.',
      );
    }

    final state = _randomUrlSafeString(24);
    final responseMode = config.usesCodeGrant
        ? ExternalListAuthResponseMode.code
        : ExternalListAuthResponseMode.token;
    final codeVerifier = provider == ExternalListProvider.myAnimeList
        ? _randomUrlSafeString(64)
        : null;

    await storage.saveExternalListPendingAuthorization(
      ExternalListPendingAuthorization(
        provider: provider,
        state: state,
        codeVerifier: codeVerifier,
        responseMode: responseMode,
        startedAt: DateTime.now(),
      ),
    );

    return ExternalListAuthorizationStart(
      provider: provider,
      authorizationUri: _authorizationUriFor(
        provider: provider,
        config: config,
        state: state,
        responseMode: responseMode,
        codeVerifier: codeVerifier,
      ),
      responseMode: responseMode,
    );
  }

  Future<ExternalListConnection> completeAuthorization({
    required ExternalListProvider provider,
    required String callbackOrCode,
  }) async {
    final pending = storage.getExternalListPendingAuthorization(provider);
    if (pending == null) {
      throw ExternalListSyncException(
        'Start ${provider.label} connection first.',
      );
    }

    final value = callbackOrCode.trim();
    if (value.isEmpty) {
      throw const ExternalListSyncException(
        'Complete the sign-in in the opened window, then try connecting again.',
      );
    }

    final config = ExternalListOAuthConfig.forProvider(provider);
    if (!config.hasClientId) {
      throw ExternalListSyncException(
        '${provider.label} OAuth is not configured.',
      );
    }

    final tokenResponse =
        pending.responseMode == ExternalListAuthResponseMode.token
        ? _tokenResponseFromImplicitCallback(value, pending)
        : await _exchangeAuthorizationCode(
            provider: provider,
            callbackOrCode: value,
            pending: pending,
            config: config,
          );

    final connection = await _connectionFromTokenResponse(
      provider: provider,
      tokenResponse: tokenResponse,
    );
    await storage.saveExternalListConnection(connection);
    await storage.clearExternalListPendingAuthorization(provider);
    return connection;
  }

  Future<void> disconnect(ExternalListProvider provider) async {
    await storage.removeExternalListConnection(provider);
  }

  Future<void> cancelAuthorization(ExternalListProvider provider) {
    return storage.clearExternalListPendingAuthorization(provider);
  }

  Future<ExternalListSyncResult> importConnectedWatchProgress({
    required ExternalListProvider provider,
    required String userId,
  }) async {
    final connection = await _freshConnectionFor(provider);
    final remoteEntries = await switch (provider) {
      ExternalListProvider.aniList => _fetchAniListEntriesForConnection(
        connection,
      ),
      ExternalListProvider.myAnimeList => _fetchMyAnimeListEntriesForConnection(
        connection,
      ),
    };

    return _applyRemoteEntries(
      provider: provider,
      username: connection.username,
      userId: userId,
      remoteEntries: remoteEntries,
    );
  }

  Future<ExternalListProgressSyncResult?> syncCompletedWatchProgress({
    required Anime anime,
    required WatchEntry entry,
  }) async {
    if (!entry.isCompleted || entry.isExternalSync) return null;

    final activeConnection = storage.getActiveExternalListConnection();
    if (activeConnection == null) return null;

    final connection = await _freshConnectionFor(activeConnection.provider);
    final completedAnime = _entryCompletesAnime(anime: anime, entry: entry);

    await switch (connection.provider) {
      ExternalListProvider.aniList => _pushAniListWatchProgress(
        connection: connection,
        anime: anime,
        entry: entry,
        completedAnime: completedAnime,
      ),
      ExternalListProvider.myAnimeList => _pushMyAnimeListWatchProgress(
        connection: connection,
        anime: anime,
        entry: entry,
        completedAnime: completedAnime,
      ),
    };

    return ExternalListProgressSyncResult(
      provider: connection.provider,
      username: connection.username,
      progress: entry.lastWatchedEpisode,
      isCompleted: completedAnime,
    );
  }

  Future<ExternalListSyncResult> importWatchProgress({
    required ExternalListProvider provider,
    required String username,
    required String userId,
  }) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) {
      throw const ExternalListSyncException('Enter a username to sync.');
    }
    if (userId.trim().isEmpty) {
      throw const ExternalListSyncException('Sign in before syncing.');
    }

    final remoteEntries = await switch (provider) {
      ExternalListProvider.myAnimeList => _fetchMyAnimeListEntries(
        normalizedUsername,
      ),
      ExternalListProvider.aniList => _fetchAniListEntries(normalizedUsername),
    };

    return _applyRemoteEntries(
      provider: provider,
      username: normalizedUsername,
      userId: userId,
      remoteEntries: remoteEntries,
    );
  }

  Future<ExternalListConnection> _freshConnectionFor(
    ExternalListProvider provider,
  ) async {
    final connection = storage.getActiveExternalListConnection();
    if (connection == null || connection.provider != provider) {
      throw ExternalListSyncException('Connect ${provider.label} first.');
    }

    if (!connection.isExpired && !connection.shouldRefresh) {
      return connection;
    }

    if (!connection.canRefresh) {
      throw ExternalListSyncException(
        '${provider.label} authorization expired. Reconnect your account.',
      );
    }

    return _refreshConnection(connection);
  }

  bool _entryCompletesAnime({required Anime anime, required WatchEntry entry}) {
    final totalEpisodes = anime.totalEpisodes;
    if (totalEpisodes > 0) {
      return entry.lastWatchedEpisode >= totalEpisodes;
    }

    final status = _normalizedStatus(anime.status);
    return status == 'completed' ||
        status == 'finished' ||
        status == 'complete';
  }

  Future<void> _pushAniListWatchProgress({
    required ExternalListConnection connection,
    required Anime anime,
    required WatchEntry entry,
    required bool completedAnime,
  }) async {
    final mediaId = await _resolveAniListMediaId(anime);
    final response = await _client
        .post(
          _aniListEndpoint,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${connection.accessToken}',
          },
          body: jsonEncode({
            'query': r'''
              mutation ($mediaId: Int, $status: MediaListStatus, $progress: Int) {
                SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress) {
                  id
                  status
                  progress
                }
              }
            ''',
            'variables': {
              'mediaId': mediaId,
              'status': completedAnime ? 'COMPLETED' : 'CURRENT',
              'progress': max(0, entry.lastWatchedEpisode),
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    _throwIfProviderWriteFailed(
      response: response,
      fallbackMessage: 'AniList progress update failed.',
    );
  }

  Future<void> _pushMyAnimeListWatchProgress({
    required ExternalListConnection connection,
    required Anime anime,
    required WatchEntry entry,
    required bool completedAnime,
  }) async {
    final animeId = await _resolveMyAnimeListId(anime);
    final response = await _client
        .patch(
          _myAnimeListApiUri('v2/anime/$animeId/my_list_status', const {}),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Authorization': 'Bearer ${connection.accessToken}',
          },
          body: {
            'status': completedAnime ? 'completed' : 'watching',
            'num_watched_episodes': max(0, entry.lastWatchedEpisode).toString(),
            if (completedAnime) 'finish_date': _dateOnly(entry.lastWatchedAt),
          },
        )
        .timeout(const Duration(seconds: 15));

    _throwIfProviderWriteFailed(
      response: response,
      fallbackMessage: 'MyAnimeList progress update failed.',
    );
  }

  void _throwIfProviderWriteFailed({
    required http.Response response,
    required String fallbackMessage,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.trim().isEmpty) return;
      final decoded = _decodeObject(response.body);
      final errors = _asList(decoded['errors']);
      if (errors.isEmpty) return;

      final firstError = _asMap(errors.first);
      throw ExternalListSyncException(
        _stringFrom(firstError?['message']) ?? fallbackMessage,
      );
    }

    final message = _messageFromJson(response.body);
    throw ExternalListSyncException(
      message ?? '$fallbackMessage (${response.statusCode})',
    );
  }

  Future<int> _resolveAniListMediaId(Anime anime) async {
    final candidateId = int.tryParse(anime.id);
    if (candidateId == null) {
      throw ExternalListSyncException(
        'Could not match "${anime.title}" to AniList.',
      );
    }

    final byMalId = await _lookupAniListIds(idMal: candidateId);
    if (byMalId?.aniListId != null) return byMalId!.aniListId!;

    final byAniListId = await _lookupAniListIds(id: candidateId);
    if (byAniListId?.aniListId != null) return byAniListId!.aniListId!;

    throw ExternalListSyncException(
      'Could not match "${anime.title}" to AniList.',
    );
  }

  Future<int> _resolveMyAnimeListId(Anime anime) async {
    final candidateId = int.tryParse(anime.id);
    if (candidateId == null) {
      throw ExternalListSyncException(
        'Could not match "${anime.title}" to MyAnimeList.',
      );
    }

    final byMalId = await _lookupAniListIds(idMal: candidateId);
    if (byMalId?.malId != null) return byMalId!.malId!;

    final byAniListId = await _lookupAniListIds(id: candidateId);
    if (byAniListId?.malId != null) return byAniListId!.malId!;

    return candidateId;
  }

  Future<({int? aniListId, int? malId})?> _lookupAniListIds({
    int? id,
    int? idMal,
  }) async {
    final lookupId = idMal ?? id;
    if (lookupId == null) return null;
    final filter = idMal != null ? 'idMal' : 'id';

    final response = await _client
        .post(
          _aniListEndpoint,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'query':
                '''
              query (\$id: Int) {
                Media($filter: \$id, type: ANIME) {
                  id
                  idMal
                }
              }
            ''',
            'variables': {'id': lookupId},
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) return null;

    final decoded = _decodeObject(response.body);
    final media = _asMap(_asMap(decoded['data'])?['Media']);
    if (media == null) return null;

    return (aniListId: _intFrom(media['id']), malId: _intFrom(media['idMal']));
  }

  Future<ExternalListConnection> _refreshConnection(
    ExternalListConnection connection,
  ) async {
    final config = ExternalListOAuthConfig.forProvider(connection.provider);
    final refreshToken = connection.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty || !config.hasClientId) {
      return connection;
    }

    final response = await switch (connection.provider) {
      ExternalListProvider.aniList => _client.post(
        Uri.parse('https://anilist.co/api/v2/oauth/token'),
        headers: const {'Accept': 'application/json'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': config.clientId,
          'refresh_token': refreshToken,
        },
      ),
      ExternalListProvider.myAnimeList => _client.post(
        Uri.parse('https://myanimelist.net/v1/oauth2/token'),
        headers: const {'Accept': 'application/json'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': config.clientId,
          'refresh_token': refreshToken,
        },
      ),
    }.timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExternalListSyncException(
        '${connection.provider.label} token refresh failed. Reconnect your account.',
      );
    }

    final token = _decodeTokenResponse(response.body);
    final refreshed = connection.copyWith(
      accessToken: token.accessToken,
      refreshToken: token.refreshToken ?? connection.refreshToken,
      expiresAt: token.expiresAt,
    );
    await storage.saveExternalListConnection(refreshed);
    return refreshed;
  }

  Future<ExternalListSyncResult> _applyRemoteEntries({
    required ExternalListProvider provider,
    required String username,
    required String userId,
    required List<_ExternalProgress> remoteEntries,
  }) async {
    final dedupedEntries = <String, _ExternalProgress>{};
    var skippedCount = 0;

    for (final entry in remoteEntries) {
      if (!entry.shouldImportToWatchlist) {
        skippedCount++;
        continue;
      }

      final current = dedupedEntries[entry.animeId];
      if (current == null || entry.isBetterThan(current)) {
        dedupedEntries[entry.animeId] = entry;
      }
    }

    var importedCount = 0;
    var unchangedCount = 0;
    final importedTitles = <String>[];
    final watchlistIds = storage.getWatchlist().toSet();
    final existingEntries = <String, WatchEntry>{
      for (final entry in storage.getWatchHistory(userId: userId))
        entry.animeId: entry,
    };
    final watchlistAdditions = <Anime>[];
    final cacheEntries = <Anime>[];
    final watchEntryUpdates = <WatchEntry>[];

    for (final entry in dedupedEntries.values) {
      var changed = false;
      if (watchlistIds.add(entry.animeId)) {
        watchlistAdditions.add(entry.anime);
        changed = true;
      }
      cacheEntries.add(entry.anime);

      final existing = existingEntries[entry.animeId];

      if (existing == null || entry.shouldReplace(existing)) {
        final updatedEntry = WatchEntry(
          id: '${entry.animeId}_history',
          userId: userId,
          animeId: entry.animeId,
          lastWatchedEpisode: entry.progress,
          watchedDuration: Duration.zero,
          lastWatchedAt: entry.updatedAt,
          isCompleted: entry.isCompleted,
          isExternalSync: true,
          externalListStatus: entry.status,
        );
        watchEntryUpdates.add(updatedEntry);
        existingEntries[entry.animeId] = updatedEntry;
        changed = true;
      } else if (existing.externalListStatus != entry.status) {
        // Progress and list state are independent. Keep newer local playback
        // progress, but do not lose the remote list state (notably AniList's
        // PAUSED status) just because its episode count is behind locally.
        final statusUpdatedEntry = WatchEntry(
          id: existing.id,
          userId: existing.userId,
          animeId: existing.animeId,
          lastWatchedEpisode: existing.lastWatchedEpisode,
          watchedDuration: existing.watchedDuration,
          lastWatchedAt: existing.lastWatchedAt,
          isCompleted: existing.isCompleted,
          isExternalSync: existing.isExternalSync,
          externalListStatus: entry.status,
        );
        watchEntryUpdates.add(statusUpdatedEntry);
        existingEntries[entry.animeId] = statusUpdatedEntry;
        changed = true;
      }

      if (changed) {
        importedCount++;
        if (importedTitles.length < 3) {
          importedTitles.add(entry.title);
        }
      } else {
        unchangedCount++;
      }
    }

    await storage.applyExternalListImport(
      watchlistAdditions: watchlistAdditions,
      cacheEntries: cacheEntries,
      watchEntryUpdates: watchEntryUpdates,
    );

    return ExternalListSyncResult(
      provider: provider,
      username: username,
      scannedCount: remoteEntries.length,
      importedCount: importedCount,
      unchangedCount: unchangedCount,
      skippedCount: skippedCount,
      importedTitles: importedTitles,
    );
  }

  Uri _authorizationUriFor({
    required ExternalListProvider provider,
    required ExternalListOAuthConfig config,
    required String state,
    required ExternalListAuthResponseMode responseMode,
    required String? codeVerifier,
  }) {
    return switch (provider) {
      ExternalListProvider.aniList =>
        Uri.https('anilist.co', '/api/v2/oauth/authorize', {
          'client_id': config.clientId,
          'response_type': responseMode == ExternalListAuthResponseMode.code
              ? 'code'
              : 'token',
          'state': state,
          if (config.requiresExplicitRedirectUri)
            'redirect_uri': config.redirectUri,
        }),
      ExternalListProvider.myAnimeList =>
        Uri.https('myanimelist.net', '/v1/oauth2/authorize', {
          'response_type': 'code',
          'client_id': config.clientId,
          'redirect_uri': config.redirectUri,
          'state': state,
          'code_challenge': codeVerifier ?? '',
          'code_challenge_method': 'plain',
        }),
    };
  }

  Future<_TokenResponse> _exchangeAuthorizationCode({
    required ExternalListProvider provider,
    required String callbackOrCode,
    required ExternalListPendingAuthorization pending,
    required ExternalListOAuthConfig config,
  }) async {
    final parsed = _parseCallbackOrCode(callbackOrCode, pending);
    final code = parsed.code;
    if (code.isEmpty) {
      throw const ExternalListSyncException('No authorization code was found.');
    }

    final tokenUri = switch (provider) {
      ExternalListProvider.aniList => Uri.parse(
        'https://anilist.co/api/v2/oauth/token',
      ),
      ExternalListProvider.myAnimeList => Uri.parse(
        'https://myanimelist.net/v1/oauth2/token',
      ),
    };
    final body = switch (provider) {
      ExternalListProvider.aniList => <String, String>{
        'grant_type': 'authorization_code',
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'code': code,
      },
      ExternalListProvider.myAnimeList => <String, String>{
        'grant_type': 'authorization_code',
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'code': code,
        'code_verifier': pending.codeVerifier ?? '',
      },
    };

    var response = await _client
        .post(
          tokenUri,
          headers: const {'Accept': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    if (provider == ExternalListProvider.myAnimeList &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      final retryBody = Map<String, String>.from(body)..remove('redirect_uri');
      response = await _client
          .post(
            tokenUri,
            headers: const {'Accept': 'application/json'},
            body: retryBody,
          )
          .timeout(const Duration(seconds: 15));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _messageFromJson(response.body);
      throw ExternalListSyncException(
        message ?? '${provider.label} authorization failed.',
      );
    }

    return _decodeTokenResponse(response.body);
  }

  _TokenResponse _tokenResponseFromImplicitCallback(
    String callbackUrl,
    ExternalListPendingAuthorization pending,
  ) {
    final uri = Uri.tryParse(callbackUrl);
    if (uri == null || (!uri.hasFragment && uri.queryParameters.isEmpty)) {
      final rawToken = _accessTokenFromText(callbackUrl);
      if (rawToken != null) {
        return _TokenResponse(
          accessToken: rawToken,
          refreshToken: null,
          expiresAt: null,
        );
      }
      throw const ExternalListSyncException('No access token was found.');
    }

    final fragmentParams = Uri.splitQueryString(uri.fragment);
    _throwIfAuthorizationWasDenied(
      queryParameters: uri.queryParameters,
      fragmentParameters: fragmentParams,
    );
    final state = fragmentParams['state'] ?? uri.queryParameters['state'];
    if (state != null && state != pending.state) {
      throw const ExternalListSyncException(
        'Authorization state did not match. Try connecting again.',
      );
    }

    final accessToken = fragmentParams['access_token'];
    if (accessToken == null || accessToken.isEmpty) {
      throw const ExternalListSyncException(
        'No access token was found in the callback URL.',
      );
    }

    final expiresIn = _intFrom(fragmentParams['expires_in']);
    return _TokenResponse(
      accessToken: accessToken,
      refreshToken: null,
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  _ParsedAuthorizationCode _parseCallbackOrCode(
    String callbackOrCode,
    ExternalListPendingAuthorization pending,
  ) {
    final uri = Uri.tryParse(callbackOrCode);
    if (uri != null && (uri.queryParameters.isNotEmpty || uri.hasFragment)) {
      final fragmentParams = uri.hasFragment
          ? Uri.splitQueryString(uri.fragment)
          : const <String, String>{};
      _throwIfAuthorizationWasDenied(
        queryParameters: uri.queryParameters,
        fragmentParameters: fragmentParams,
      );
      final state = uri.queryParameters['state'] ?? fragmentParams['state'];
      if (state != null && state != pending.state) {
        throw const ExternalListSyncException(
          'Authorization state did not match. Try connecting again.',
        );
      }
      return _ParsedAuthorizationCode(
        uri.queryParameters['code'] ?? fragmentParams['code'] ?? '',
      );
    }

    return _ParsedAuthorizationCode(callbackOrCode.trim());
  }

  void _throwIfAuthorizationWasDenied({
    required Map<String, String> queryParameters,
    required Map<String, String> fragmentParameters,
  }) {
    final error = fragmentParameters['error'] ?? queryParameters['error'];
    if (error == null || error.isEmpty) return;

    final description =
        fragmentParameters['error_description'] ??
        queryParameters['error_description'];
    throw ExternalListSyncException(
      description?.trim().isNotEmpty == true
          ? description!.trim()
          : 'Authorization was cancelled or denied.',
    );
  }

  Future<ExternalListConnection> _connectionFromTokenResponse({
    required ExternalListProvider provider,
    required _TokenResponse tokenResponse,
  }) async {
    final username = await switch (provider) {
      ExternalListProvider.aniList => _fetchAniListViewerName(
        tokenResponse.accessToken,
      ),
      ExternalListProvider.myAnimeList => _fetchMyAnimeListViewerName(
        tokenResponse.accessToken,
      ),
    };

    return ExternalListConnection(
      provider: provider,
      username: username,
      accessToken: tokenResponse.accessToken,
      refreshToken: tokenResponse.refreshToken,
      expiresAt: tokenResponse.expiresAt,
      connectedAt: DateTime.now(),
    );
  }

  Future<String> _fetchAniListViewerName(String accessToken) async {
    final response = await _client
        .post(
          _aniListEndpoint,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'query': r'''
              query {
                Viewer {
                  name
                }
              }
            ''',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ExternalListSyncException(
        'Could not verify the AniList account.',
      );
    }

    final decoded = _decodeObject(response.body);
    final viewer = _asMap(_asMap(decoded['data'])?['Viewer']);
    final name = _stringFrom(viewer?['name']);
    if (name == null) {
      throw const ExternalListSyncException(
        'AniList did not return an account name.',
      );
    }
    return name;
  }

  Future<String> _fetchMyAnimeListViewerName(String accessToken) async {
    final response = await _client
        .get(
          _myAnimeListApiUri('v2/users/@me', {'fields': 'name'}),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ExternalListSyncException(
        'Could not verify the MyAnimeList account.',
      );
    }

    final decoded = _decodeObject(response.body);
    final name = _stringFrom(decoded['name']);
    if (name == null) {
      throw const ExternalListSyncException(
        'MyAnimeList did not return an account name.',
      );
    }
    return name;
  }

  Future<List<_ExternalProgress>> _fetchAniListEntriesForConnection(
    ExternalListConnection connection,
  ) {
    return _fetchAniListEntries(
      connection.username,
      accessToken: connection.accessToken,
    );
  }

  Future<List<_ExternalProgress>> _fetchAniListEntries(
    String username, {
    String? accessToken,
  }) async {
    final response = await _client
        .post(
          _aniListEndpoint,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (accessToken != null && accessToken.isNotEmpty)
              'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'query': r'''
              query ($userName: String) {
                MediaListCollection(userName: $userName, type: ANIME) {
                  lists {
                    name
                    status
                    entries {
                      status
                      progress
                      updatedAt
                      media {
                        id
                        idMal
                        episodes
                        coverImage {
                          extraLarge
                          large
                          medium
                        }
                        averageScore
                        status
                        seasonYear
                        startDate {
                          year
                        }
                        duration
                        format
                        title {
                          romaji
                          english
                          native
                          userPreferred
                        }
                      }
                    }
                  }
                }
              }
            ''',
            'variables': {'userName': username},
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExternalListSyncException(
        'AniList sync failed (${response.statusCode}). Try again later.',
      );
    }

    final decoded = _decodeObject(response.body);
    final errors = _asList(decoded['errors']);
    if (errors.isNotEmpty) {
      final firstError = _asMap(errors.first);
      final message = _stringFrom(firstError?['message']);
      throw ExternalListSyncException(message ?? 'AniList sync failed.');
    }

    final collection = _asMap(_asMap(decoded['data'])?['MediaListCollection']);

    if (collection == null) {
      throw ExternalListSyncException(
        'AniList did not return an anime list for "$username".',
      );
    }

    final entries = <_ExternalProgress>[];
    for (final list in _asList(collection['lists'])) {
      final listMap = _asMap(list);
      final fallbackStatus = listMap?['status'];

      for (final rawEntry in _asList(listMap?['entries'])) {
        final entry = _asMap(rawEntry);
        if (entry == null) continue;

        final media = _asMap(entry['media']);
        if (media == null) continue;

        final animeId = _stringFrom(media['idMal']) ?? _stringFrom(media['id']);
        if (animeId == null || animeId.isEmpty) continue;

        final totalEpisodes = _intFrom(media['episodes']);
        final status = _statusText(entry['status'] ?? fallbackStatus);
        final progress = _progressFrom(
          rawProgress: entry['progress'],
          totalEpisodes: totalEpisodes,
          status: status,
        );

        entries.add(
          _ExternalProgress(
            animeId: animeId,
            title: _titleFromAniList(media['title']) ?? 'Anime #$animeId',
            anime: _animeFromAniListMedia(animeId, media),
            status: status,
            progress: progress,
            totalEpisodes: totalEpisodes,
            updatedAt: _dateFromEpochSeconds(entry['updatedAt']),
          ),
        );
      }
    }

    return entries;
  }

  Future<List<_ExternalProgress>> _fetchMyAnimeListEntriesForConnection(
    ExternalListConnection connection,
  ) async {
    final entries = <_ExternalProgress>[];
    Uri? nextUri = _myAnimeListApiUri('v2/users/@me/animelist', {
      'fields': 'list_status,num_episodes,main_picture,mean,status,media_type',
      'limit': '1000',
      'sort': 'list_updated_at',
    });

    while (nextUri != null) {
      final response = await _client
          .get(
            nextUri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer ${connection.accessToken}',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _messageFromJson(response.body);
        throw ExternalListSyncException(
          message ?? 'MyAnimeList import failed.',
        );
      }

      final decoded = _decodeObject(response.body);
      for (final rawEntry in _asList(decoded['data'])) {
        final progress = _progressFromMyAnimeListApi(rawEntry);
        if (progress != null) {
          entries.add(progress);
        }
      }

      final next = _stringFrom(_asMap(decoded['paging'])?['next']);
      nextUri = next == null ? null : Uri.tryParse(next);
    }

    if (entries.isEmpty) {
      throw ExternalListSyncException(
        'No MyAnimeList anime progress was found for "${connection.username}".',
      );
    }

    return entries;
  }

  Future<List<_ExternalProgress>> _fetchMyAnimeListEntries(
    String username,
  ) async {
    final entries = <_ExternalProgress>[];
    var page = 1;
    var hasNextPage = true;

    while (hasNextPage && page <= 10) {
      final uri = _jikanBaseUri.replace(
        pathSegments: [
          ..._jikanBaseUri.pathSegments.where((segment) => segment.isNotEmpty),
          'v4',
          'users',
          username,
          'animelist',
        ],
        queryParameters: {'page': '$page', 'limit': '300'},
      );

      final response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'AniWingsTV/1.0',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _messageFromJson(response.body);
        if (response.statusCode == 403 || response.statusCode == 504) {
          throw const ExternalListSyncException(
            'MyAnimeList public list import is unavailable right now. Use Connect after adding MAL OAuth credentials.',
          );
        }
        throw ExternalListSyncException(
          message ??
              'MyAnimeList sync failed (${response.statusCode}). Public MAL list import may be unavailable right now.',
        );
      }

      final decoded = _decodeObject(response.body);
      final pageData = _asList(decoded['data']);

      for (final rawEntry in pageData) {
        final progress = _progressFromMyAnimeList(rawEntry);
        if (progress != null) {
          entries.add(progress);
        }
      }

      final pagination = _asMap(decoded['pagination']);
      hasNextPage = pagination?['has_next_page'] == true && pageData.isNotEmpty;
      page++;

      if (hasNextPage) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
    }

    if (entries.isEmpty) {
      throw ExternalListSyncException(
        'No public MyAnimeList anime progress was found for "$username".',
      );
    }

    return entries;
  }

  _ExternalProgress? _progressFromMyAnimeList(dynamic rawEntry) {
    final entry = _asMap(rawEntry);
    if (entry == null) return null;

    final anime = _asMap(entry['anime']);
    final node = _asMap(entry['node']);
    final listStatus = _asMap(entry['list_status']);

    final animeId =
        _stringFrom(entry['mal_id']) ??
        _stringFrom(entry['anime_id']) ??
        _stringFrom(anime?['mal_id']) ??
        _stringFrom(node?['id']);
    if (animeId == null || animeId.isEmpty) return null;

    final status = _statusText(
      entry['status'] ??
          entry['watching_status'] ??
          listStatus?['status'] ??
          entry['watch_status'],
    );
    final totalEpisodes =
        _intFrom(entry['episodes']) ??
        _intFrom(entry['anime_num_episodes']) ??
        _intFrom(anime?['episodes']) ??
        _intFrom(node?['num_episodes']);
    final progress = _progressFrom(
      rawProgress:
          entry['watched_episodes'] ??
          entry['num_watched_episodes'] ??
          entry['my_watched_episodes'] ??
          entry['progress'] ??
          listStatus?['num_episodes_watched'],
      totalEpisodes: totalEpisodes,
      status: status,
    );
    final title =
        _stringFrom(entry['title']) ??
        _stringFrom(entry['anime_title']) ??
        _stringFrom(anime?['title']) ??
        _stringFrom(node?['title']) ??
        'Anime #$animeId';

    return _ExternalProgress(
      animeId: animeId,
      title: title,
      anime: _animeFromMyAnimeListEntry(
        animeId: animeId,
        title: title,
        entry: entry,
        anime: anime,
        node: node,
        totalEpisodes: totalEpisodes,
        listStatus: status,
      ),
      status: status,
      progress: progress,
      totalEpisodes: totalEpisodes,
      updatedAt:
          _dateFromAny(entry['updated_at']) ??
          _dateFromAny(entry['updatedAt']) ??
          _dateFromAny(entry['watching_updated']) ??
          _dateFromAny(listStatus?['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  _ExternalProgress? _progressFromMyAnimeListApi(dynamic rawEntry) {
    final entry = _asMap(rawEntry);
    if (entry == null) return null;

    final node = _asMap(entry['node']);
    final listStatus = _asMap(entry['list_status']);
    if (node == null || listStatus == null) return null;

    final animeId = _stringFrom(node['id']);
    if (animeId == null || animeId.isEmpty) return null;

    final status = _statusText(listStatus['status']);
    final totalEpisodes = _intFrom(node['num_episodes']);
    final progress = _progressFrom(
      rawProgress: listStatus['num_episodes_watched'],
      totalEpisodes: totalEpisodes,
      status: status,
    );
    final title = _stringFrom(node['title']) ?? 'Anime #$animeId';

    return _ExternalProgress(
      animeId: animeId,
      title: title,
      anime: _animeFromMyAnimeListApiNode(
        animeId: animeId,
        title: title,
        node: node,
        totalEpisodes: totalEpisodes,
        listStatus: status,
      ),
      status: status,
      progress: progress,
      totalEpisodes: totalEpisodes,
      updatedAt:
          _dateFromAny(listStatus['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Uri _myAnimeListApiUri(String path, Map<String, String> queryParameters) {
    final baseSegments = _myAnimeListApiBaseUri.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    return _myAnimeListApiBaseUri.replace(
      pathSegments: [
        ...baseSegments,
        ...path.split('/').where((segment) => segment.isNotEmpty),
      ],
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }
}

class _TokenResponse {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  const _TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });
}

class _ParsedAuthorizationCode {
  final String code;

  const _ParsedAuthorizationCode(this.code);
}

Anime _animeFromAniListMedia(String animeId, Map<String, dynamic> media) {
  final coverImage = _asMap(media['coverImage']);
  final posterUrl = _firstText([
    coverImage?['extraLarge'],
    coverImage?['large'],
    coverImage?['medium'],
  ]);
  final backdropUrl = _firstText([media['bannerImage'], posterUrl]);

  return Anime(
    id: animeId,
    title: _titleFromAniList(media['title']) ?? 'Anime #$animeId',
    description:
        _stringFrom(media['description']) ?? 'No description available.',
    posterUrl: posterUrl,
    backdropUrl: backdropUrl,
    rating: _scoreToFiveStars(media['averageScore']),
    status: _animeStatusFrom(media['status']),
    genres: _genreNames(media['genres']),
    totalEpisodes: _intFrom(media['episodes']) ?? 0,
    year: _yearFromValues([
      media['seasonYear'],
      _asMap(media['startDate'])?['year'],
    ]),
    episodeDurationMinutes: _durationMinutesFromAny(media['duration']),
    type: _stringFrom(media['format']) ?? 'TV',
    malId: _stringFrom(media['idMal']),
    aniListId: _stringFrom(media['id']) ?? animeId,
    alternativeTitles: _titleAliasesFromAniList(media['title']),
  );
}

Anime _animeFromMyAnimeListEntry({
  required String animeId,
  required String title,
  required Map<String, dynamic> entry,
  required Map<String, dynamic>? anime,
  required Map<String, dynamic>? node,
  required int? totalEpisodes,
  required String listStatus,
}) {
  final source = anime ?? node ?? entry;
  final images = _asMap(source['images']);
  final jpgImages = _asMap(images?['jpg']);
  final webpImages = _asMap(images?['webp']);
  final mainPicture = _asMap(source['main_picture']);
  final airedFrom = _asMap(_asMap(_asMap(source['aired'])?['prop'])?['from']);
  final posterUrl = _firstText([
    entry['anime_image_path'],
    source['anime_image_path'],
    mainPicture?['large'],
    mainPicture?['medium'],
    jpgImages?['large_image_url'],
    jpgImages?['image_url'],
    webpImages?['large_image_url'],
    webpImages?['image_url'],
    source['image_url'],
  ]);

  return Anime(
    id: animeId,
    title: title,
    description:
        _stringFrom(source['synopsis']) ??
        _stringFrom(entry['synopsis']) ??
        'No description available.',
    posterUrl: posterUrl,
    backdropUrl: posterUrl,
    rating: _scoreToFiveStars(
      source['score'] ?? source['mean'] ?? entry['anime_score_val'],
    ),
    status: _animeStatusFrom(
      entry['anime_status'] ??
          entry['anime_airing_status'] ??
          source['status'] ??
          listStatus,
    ),
    genres: _genreNames(source['genres'] ?? entry['genres']),
    totalEpisodes:
        totalEpisodes ??
        _intFrom(source['episodes']) ??
        _intFrom(source['num_episodes']) ??
        0,
    year: _yearFromValues([
      source['year'],
      entry['year'],
      airedFrom?['year'],
      _asMap(source['start_season'])?['year'],
      source['start_date'],
      entry['anime_start_date_string'],
    ]),
    episodeDurationMinutes: _durationMinutesFromAny(
      source['duration'] ?? entry['duration'],
    ),
    type: _stringFrom(source['type']) ?? _stringFrom(source['media_type']),
    malId: animeId,
    alternativeTitles: _titleAliasesFromMyAnimeList(source, entry),
  );
}

Anime _animeFromMyAnimeListApiNode({
  required String animeId,
  required String title,
  required Map<String, dynamic> node,
  required int? totalEpisodes,
  required String listStatus,
}) {
  final mainPicture = _asMap(node['main_picture']);
  final posterUrl = _firstText([mainPicture?['large'], mainPicture?['medium']]);

  return Anime(
    id: animeId,
    title: title,
    description: _stringFrom(node['synopsis']) ?? 'No description available.',
    posterUrl: posterUrl,
    backdropUrl: posterUrl,
    rating: _scoreToFiveStars(node['mean']),
    status: _animeStatusFrom(node['status'] ?? listStatus),
    genres: _genreNames(node['genres']),
    totalEpisodes: totalEpisodes ?? _intFrom(node['num_episodes']) ?? 0,
    year: _yearFromValues([
      _asMap(node['start_season'])?['year'],
      node['start_date'],
    ]),
    episodeDurationMinutes: _durationMinutesFromSeconds(
      node['average_episode_duration'],
    ),
    type: _stringFrom(node['media_type']),
    malId: animeId,
    alternativeTitles: [title],
  );
}

class _ExternalProgress {
  final String animeId;
  final String title;
  final Anime anime;
  final String status;
  final int progress;
  final int? totalEpisodes;
  final DateTime updatedAt;

  const _ExternalProgress({
    required this.animeId,
    required this.title,
    required this.anime,
    required this.status,
    required this.progress,
    required this.totalEpisodes,
    required this.updatedAt,
  });

  bool get isCompleted {
    if (_isCompletedStatus(status)) return true;
    if (_isPlanningStatus(status) ||
        _isPausedStatus(status) ||
        _isDroppedStatus(status)) {
      return false;
    }
    final total = totalEpisodes;
    return total != null && total > 0 && progress >= total;
  }

  bool get shouldImportToWatchlist {
    return true;
  }

  bool isBetterThan(_ExternalProgress other) {
    if (isCompleted && !other.isCompleted) return true;
    if (progress != other.progress) return progress > other.progress;
    return updatedAt.isAfter(other.updatedAt);
  }

  bool shouldReplace(WatchEntry existing) {
    if (existing.isExternalSync) return true;
    if (existing.watchedDuration == Duration.zero &&
        progress == existing.lastWatchedEpisode &&
        isCompleted == existing.isCompleted &&
        !updatedAt.isBefore(existing.lastWatchedAt)) {
      return true;
    }
    if (isCompleted && !existing.isCompleted) return true;
    if (progress > existing.lastWatchedEpisode) return true;
    if (progress == existing.lastWatchedEpisode &&
        isCompleted == existing.isCompleted &&
        updatedAt.isAfter(existing.lastWatchedAt)) {
      return true;
    }
    return false;
  }
}

_TokenResponse _decodeTokenResponse(String body) {
  final decoded = _decodeObject(body);
  final accessToken = _stringFrom(decoded['access_token']);
  if (accessToken == null) {
    throw const ExternalListSyncException(
      'Provider did not return an access token.',
    );
  }

  final expiresIn = _intFrom(decoded['expires_in']);
  return _TokenResponse(
    accessToken: accessToken,
    refreshToken: _stringFrom(decoded['refresh_token']),
    expiresAt: expiresIn == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresIn)),
  );
}

String? _accessTokenFromText(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;

  final accessTokenMatch = RegExp(
    r'access_token\s*[=:]\s*([A-Za-z0-9._~+/\-]+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (accessTokenMatch != null) {
    return accessTokenMatch.group(1)?.trim();
  }

  final jwtMatch = RegExp(
    r'\b[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
  ).firstMatch(text);
  if (jwtMatch != null) return jwtMatch.group(0);

  if (RegExp(r'^[A-Za-z0-9._~+/\-]{24,}$').hasMatch(text)) {
    return text;
  }

  return null;
}

Map<String, dynamic> _decodeObject(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const ExternalListSyncException(
    'Provider returned an invalid response.',
  );
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

List<dynamic> _asList(dynamic value) {
  if (value is List) return value;
  return const [];
}

String _firstText(List<dynamic> values, [String fallback = '']) {
  for (final value in values) {
    final text = _stringFrom(value);
    if (text != null) return text;
  }
  return fallback;
}

String? _stringFrom(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? null : text;
}

int? _intFrom(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _scoreToFiveStars(dynamic value) {
  final score = value is num ? value.toDouble() : double.tryParse('$value');
  if (score == null || score <= 0) return 4.0;
  return (score > 10 ? score / 20.0 : score / 2.0).clamp(1.0, 5.0).toDouble();
}

String _animeStatusFrom(dynamic value) {
  if (value is num) {
    return switch (value.toInt()) {
      1 => 'Releasing',
      3 => 'Upcoming',
      _ => 'Completed',
    };
  }

  final normalized = _normalizedStatus(_stringFrom(value) ?? '');
  if (normalized.contains('releasing') ||
      normalized.contains('currently') ||
      normalized.contains('airing') ||
      normalized == 'watching' ||
      normalized == 'current') {
    return 'Releasing';
  }
  if (normalized.contains('not_yet') ||
      normalized.contains('upcoming') ||
      normalized.contains('not_released')) {
    return 'Upcoming';
  }
  return 'Completed';
}

List<String> _genreNames(dynamic value) {
  final genres = _asList(value)
      .map((item) {
        if (item is Map) return _stringFrom(item['name']);
        return _stringFrom(item);
      })
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList();
  return genres.isEmpty ? const ['Action'] : genres;
}

String _yearFromValues(List<dynamic> values) {
  for (final value in values) {
    final direct = _intFrom(value);
    if (direct != null && direct > 0) return direct.toString();

    final text = _stringFrom(value);
    if (text == null) continue;
    final match = RegExp(r'(19|20)\d{2}').firstMatch(text);
    if (match != null) return match.group(0)!;
  }
  return '2023';
}

int _durationMinutesFromAny(dynamic value, {int fallback = 24}) {
  if (value is num && value > 0) return value.round();
  final text = _stringFrom(value);
  if (text == null) return fallback;

  var total = 0;
  final unitPattern = RegExp(
    r'(\d+)\s*(hr|hrs|hour|hours|h|min|mins|minute|minutes|m)',
  );
  for (final match in unitPattern.allMatches(text.toLowerCase())) {
    final amount = int.tryParse(match.group(1) ?? '') ?? 0;
    final unit = match.group(2) ?? '';
    total += unit.startsWith('h') ? amount * 60 : amount;
  }
  if (total > 0) return total;

  final parsed = int.tryParse(RegExp(r'\d+').firstMatch(text)?.group(0) ?? '');
  return parsed != null && parsed > 0 ? parsed : fallback;
}

int _durationMinutesFromSeconds(dynamic value, {int fallback = 24}) {
  final seconds = value is num ? value.toDouble() : double.tryParse('$value');
  if (seconds == null || seconds <= 0) return fallback;
  return (seconds / 60).round().clamp(1, 24 * 60).toInt();
}

int _progressFrom({
  required dynamic rawProgress,
  required int? totalEpisodes,
  required String status,
}) {
  final parsed = _intFrom(rawProgress) ?? 0;
  if (parsed > 0) return parsed;
  if (_isCompletedStatus(status)) {
    final total = totalEpisodes;
    return total != null && total > 0 ? total : 1;
  }
  return 0;
}

String _statusText(dynamic value) {
  final rawText = _stringFrom(value)?.trim();
  final statusCode = value is num ? value.toInt() : int.tryParse(rawText ?? '');
  if (statusCode != null) {
    return switch (statusCode) {
      1 => 'WATCHING',
      2 => 'COMPLETED',
      3 => 'ON_HOLD',
      4 => 'DROPPED',
      6 => 'PLAN_TO_WATCH',
      _ => rawText ?? statusCode.toString(),
    };
  }

  final normalized = _normalizedStatus(rawText ?? '');
  if (normalized == 'onhold') return 'ON_HOLD';
  if (normalized == 'plantowatch') return 'PLAN_TO_WATCH';
  return normalized.toUpperCase();
}

String _normalizedStatus(String status) {
  return status.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

bool _isCompletedStatus(String status) {
  final normalized = _normalizedStatus(status);
  return normalized == 'completed' || normalized == 'complete';
}

bool _isPlanningStatus(String status) {
  final normalized = _normalizedStatus(status);
  return normalized == 'planning' ||
      normalized == 'plan_to_watch' ||
      normalized == 'ptw';
}

bool _isPausedStatus(String status) {
  final normalized = _normalizedStatus(status);
  return normalized == 'paused' || normalized == 'on_hold';
}

bool _isDroppedStatus(String status) {
  return _normalizedStatus(status) == 'dropped';
}

String _dateOnly(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

DateTime _dateFromEpochSeconds(dynamic value) {
  final seconds = _intFrom(value);
  if (seconds == null || seconds <= 0) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

DateTime? _dateFromAny(dynamic value) {
  if (value == null) return null;
  final seconds = _intFrom(value);
  if (seconds != null && seconds > 0) {
    final multiplier = seconds > 100000000000 ? 1 : 1000;
    return DateTime.fromMillisecondsSinceEpoch(seconds * multiplier);
  }
  final text = _stringFrom(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

List<String> _uniqueTitles(Iterable<dynamic> values) {
  final titles = <String>[];
  for (final value in values) {
    final title = _stringFrom(value);
    if (title == null || title.isEmpty) continue;
    if (!titles.any(
      (existing) => existing.toLowerCase() == title.toLowerCase(),
    )) {
      titles.add(title);
    }
  }
  return titles;
}

List<String> _titleAliasesFromAniList(dynamic value) {
  final title = _asMap(value);
  return _uniqueTitles([
    title?['english'],
    title?['romaji'],
    title?['native'],
    title?['userPreferred'],
  ]);
}

List<String> _titleAliasesFromMyAnimeList(
  Map<String, dynamic> source,
  Map<String, dynamic> entry,
) {
  final alternativeTitles = _asMap(source['alternative_titles']);
  return _uniqueTitles([
    source['title'],
    source['title_english'],
    source['title_japanese'],
    entry['anime_title_eng'],
    entry['anime_title'],
    alternativeTitles?['en'],
    ...(alternativeTitles?['synonyms'] as List? ?? const []),
  ]);
}

String? _titleFromAniList(dynamic value) {
  final title = _asMap(value);
  if (title == null) return null;

  return _stringFrom(title['english']) ??
      _stringFrom(title['userPreferred']) ??
      _stringFrom(title['romaji']) ??
      _stringFrom(title['native']);
}

String? _messageFromJson(String body) {
  try {
    final decoded = _decodeObject(body);
    return _stringFrom(decoded['message']) ?? _stringFrom(decoded['error']);
  } catch (_) {
    return null;
  }
}

String _randomUrlSafeString(int byteLength) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _clientIdDefineName(ExternalListProvider provider) {
  return switch (provider) {
    ExternalListProvider.aniList => 'ANIWINGS_ANILIST_CLIENT_ID',
    ExternalListProvider.myAnimeList => 'ANIWINGS_MAL_CLIENT_ID',
  };
}

String _firstNonEmpty(String first, String second, [String third = '']) {
  if (first.trim().isNotEmpty) return first.trim();
  if (second.trim().isNotEmpty) return second.trim();
  return third.trim();
}
