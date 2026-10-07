import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/episode.dart';
import '../models/watch_entry.dart';
import '../models/anime.dart';
import '../models/collection.dart';
import '../models/external_list_integration.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

final storageServiceProvider = Provider<StorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return StorageService(prefs);
});

final storageRevisionProvider = StateProvider<int>((ref) => 0);

final maintenanceModeProvider =
    StateNotifierProvider<MaintenanceModeNotifier, bool>((ref) {
      final storage = ref.watch(storageServiceProvider);
      return MaintenanceModeNotifier(storage);
    });

class MaintenanceModeNotifier extends StateNotifier<bool> {
  final StorageService _storage;

  MaintenanceModeNotifier(this._storage) : super(_storage.getMaintenanceMode());

  Future<void> setEnabled(bool enabled) async {
    await _storage.setMaintenanceMode(enabled);
    state = enabled;
  }
}

class StorageService {
  String getDefaultDownloadQuality() =>
      _prefs.getString('settings_default_download_quality') ?? '1080P';
  Future<void> setDefaultDownloadQuality(String value) async =>
      _prefs.setString('settings_default_download_quality', value);
  String getDefaultDownloadAudio() =>
      _prefs.getString('settings_default_download_audio') ?? 'SUB';
  Future<void> setDefaultDownloadAudio(String value) async =>
      _prefs.setString('settings_default_download_audio', value);
  String? getCustomDownloadDirectory() =>
      _prefs.getString('settings_custom_download_directory');
  Future<void> setCustomDownloadDirectory(String? value) async {
    if (value == null) {
      await _prefs.remove('settings_custom_download_directory');
    } else {
      await _prefs.setString('settings_custom_download_directory', value);
    }
  }

  static const String guestWatchHistoryUserId = 'default_user';

  final SharedPreferences _prefs;
  Map<String, Anime>? _animeCacheById;
  Future<void> _animeCacheWriteQueue = Future<void>.value();
  List<WatchEntry>? _cachedWatchHistory;
  final Map<String, DateTime> _lastCloudWatchEntrySaves = {};

  StorageService(this._prefs);

  static const String _watchlistKey = 'watchlist_ids';
  static const String _watchlistAnimeKey = 'watchlist_anime_objects';
  static const String _watchHistoryKey = 'watch_history_entries';
  static const String _settingsQualityKey = 'settings_video_quality';
  static const String _settingsVideoDisplayModeKey =
      'settings_video_display_mode';
  static const String _settingsSubtitlesKey = 'settings_subtitles_lang';
  static const String _settingsSubsSizeKey = 'settings_subtitles_size';
  static const String _settingsPlaybackSpeedKey = 'settings_playback_speed';
  static const String _settingsNotificationsKey =
      'settings_notifications_enabled';
  static const String _defaultAudioKey = 'settings_default_audio';
  static const String _defaultServerKey = 'settings_default_server';
  static const String _subtitleTextStyleKey = 'settings_subtitle_text_style';
  static const String _subtitleTextColorKey = 'settings_subtitle_text_color';
  static const String _subtitleBackgroundColorKey =
      'settings_subtitle_background_color';
  static const String _subtitleBottomPositionKey =
      'settings_subtitle_bottom_position';
  static const String _subtitleTextShadowKey = 'settings_subtitle_text_shadow';
  static const String _subtitleBackgroundOpacityKey =
      'settings_subtitle_background_opacity';
  static const String _maintenanceModeKey = 'admin_maintenance_mode_enabled';
  static const String _dismissedUpdateVersionKey = 'dismissed_update_version';
  static const String _activeExternalListProviderKey =
      'active_external_list_provider';
  static const String _externalListConnectionPrefix =
      'external_list_connection_';
  static const String _externalListPendingAuthPrefix =
      'external_list_pending_auth_';

  // --- Watchlist ---
  List<String> getWatchlist() {
    return _prefs.getStringList(_watchlistKey) ?? [];
  }

  List<Anime> getWatchlistAnime() {
    final rawData = _prefs.getStringList(_watchlistAnimeKey);
    if (rawData == null) {
      // Migrate old string list using cached anime details if available
      final ids = getWatchlist();
      final List<Anime> migrated = [];
      for (final id in ids) {
        final cached = getCachedAnimeById(id);
        if (cached != null) {
          migrated.add(cached);
        }
      }
      if (migrated.isNotEmpty) {
        final encoded = migrated.map((e) => jsonEncode(e.toJson())).toList();
        _prefs.setStringList(_watchlistAnimeKey, encoded);
        return migrated;
      }
      return [];
    }
    return rawData.map((item) {
      final decoded = jsonDecode(item) as Map<String, dynamic>;
      return Anime.fromJson(decoded);
    }).toList();
  }

  Future<void> saveWatchlistAnime(List<Anime> list) async {
    final ids = list.map((a) => a.id).toList();
    final encoded = list.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(_watchlistKey, ids);
    await _prefs.setStringList(_watchlistAnimeKey, encoded);
  }

  Future<void> addToWatchlist(Anime anime) async {
    final list = getWatchlistAnime();
    if (!list.any((a) => a.id == anime.id)) {
      list.add(anime);
      await saveWatchlistAnime(list);
    }
  }

  Future<void> removeWatchlist(String animeId) async {
    final list = getWatchlistAnime();
    list.removeWhere((a) => a.id == animeId);
    await saveWatchlistAnime(list);
  }

  Future<void> toggleWatchlist(Anime anime) async {
    final list = getWatchlistAnime();
    if (list.any((a) => a.id == anime.id)) {
      list.removeWhere((a) => a.id == anime.id);
    } else {
      list.add(anime);
    }
    await saveWatchlistAnime(list);
  }

  bool isInWatchlist(String animeId) {
    return getWatchlist().contains(animeId);
  }

  static const String _watchlistStatusKey = 'settings_watchlist_status_map';

  String getWatchlistStatus(String animeId) {
    try {
      final raw = _prefs.getString(_watchlistStatusKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final status = map[animeId] as String?;
        if (status != null && status.isNotEmpty) return status;
      }
    } catch (_) {}
    return 'Currently Watching';
  }

  Future<void> setWatchlistStatus(String animeId, String status) async {
    try {
      final raw = _prefs.getString(_watchlistStatusKey);
      final Map<String, dynamic> map = (raw != null && raw.isNotEmpty)
          ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
          : <String, dynamic>{};
      map[animeId] = status;
      await _prefs.setString(_watchlistStatusKey, jsonEncode(map));
    } catch (_) {}
  }

  // --- Watch History ---
  List<WatchEntry> _getAllWatchHistory() {
    if (_cachedWatchHistory != null) {
      return List<WatchEntry>.from(_cachedWatchHistory!);
    }
    final rawData = _prefs.getStringList(_watchHistoryKey) ?? [];
    final history = <WatchEntry>[];

    for (final item in rawData) {
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        history.add(WatchEntry.fromJson(decoded));
      } catch (_) {}
    }

    _cachedWatchHistory = history;
    return List<WatchEntry>.from(history);
  }

  Future<void> _saveAllWatchHistory(List<WatchEntry> history) async {
    history.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    _cachedWatchHistory = List<WatchEntry>.from(history);
    final encoded = history.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(_watchHistoryKey, encoded);
  }

  List<WatchEntry> getWatchHistory({String? userId}) {
    final history = _getAllWatchHistory();
    if (userId == null) return history;

    return history.where((entry) => entry.userId == userId).toList()
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
  }

  Future<void> saveWatchEntry(WatchEntry entry) async {
    final history = _getAllWatchHistory();
    // Remove if there's already an entry for this anime for this account.
    history.removeWhere(
      (e) => e.userId == entry.userId && e.animeId == entry.animeId,
    );
    history.add(entry);

    await _saveAllWatchHistory(history);
    unawaited(_saveWatchEntryToCloud(entry));
  }

  /// Persists an external-list import with one write per local collection.
  /// Importing a large list entry-by-entry repeatedly serializes the entire
  /// watchlist and history, which blocks the UI for a noticeable amount of
  /// time on lower-end devices.
  Future<void> applyExternalListImport({
    required Iterable<Anime> watchlistAdditions,
    required Iterable<Anime> cacheEntries,
    required Iterable<WatchEntry> watchEntryUpdates,
  }) async {
    final additions = watchlistAdditions.toList(growable: false);
    final cacheUpdates = cacheEntries.toList(growable: false);
    final historyUpdates = watchEntryUpdates.toList(growable: false);
    if (additions.isEmpty && cacheUpdates.isEmpty && historyUpdates.isEmpty) {
      return;
    }

    final pendingWrites = <Future<void>>[];

    if (additions.isNotEmpty) {
      final watchlist = getWatchlistAnime();
      final ids = watchlist.map((anime) => anime.id).toSet();
      for (final anime in additions) {
        if (ids.add(anime.id)) {
          watchlist.add(anime);
        }
      }
      pendingWrites.add(saveWatchlistAnime(watchlist));
    }

    if (cacheUpdates.isNotEmpty) {
      final cacheById = _readAnimeCacheById();
      for (final anime in cacheUpdates) {
        cacheById[anime.id] = anime;
      }
      pendingWrites.add(_persistAnimeCache(cacheById));
    }

    if (historyUpdates.isNotEmpty) {
      final history = _getAllWatchHistory();
      final updateKeys = <String>{
        for (final entry in historyUpdates)
          '${entry.userId}\u0000${entry.animeId}',
      };
      history.removeWhere(
        (entry) => updateKeys.contains('${entry.userId}\u0000${entry.animeId}'),
      );
      history.addAll(historyUpdates);
      pendingWrites.add(_saveAllWatchHistory(history));
    }

    await Future.wait(pendingWrites);
    unawaited(_saveWatchEntriesToCloud(historyUpdates));
  }

  WatchEntry? getWatchEntryForAnime(String animeId, {String? userId}) {
    final history = getWatchHistory(userId: userId);
    try {
      return history.firstWhere((e) => e.animeId == animeId);
    } catch (_) {
      return null;
    }
  }

  Future<void> removeWatchEntry(String animeId, {String? userId}) async {
    final history = _getAllWatchHistory();
    final removedEntries = history
        .where(
          (entry) =>
              entry.animeId == animeId &&
              (userId == null || entry.userId == userId),
        )
        .toList();

    history.removeWhere(
      (entry) =>
          entry.animeId == animeId &&
          (userId == null || entry.userId == userId),
    );
    await _saveAllWatchHistory(history);

    for (final entry in removedEntries) {
      unawaited(_deleteCloudWatchEntry(entry.userId, animeId));
    }
  }

  Future<void> clearWatchHistory({String? userId}) async {
    if (userId == null) {
      final removedUserIds = _getAllWatchHistory()
          .map((entry) => entry.userId)
          .where(_canUseCloudWatchHistory)
          .toSet();

      _cachedWatchHistory = [];
      await _prefs.remove(_watchHistoryKey);
      for (final removedUserId in removedUserIds) {
        unawaited(_clearCloudWatchHistory(removedUserId));
      }
      return;
    }

    final history = _getAllWatchHistory()
      ..removeWhere((entry) => entry.userId == userId);
    await _saveAllWatchHistory(history);
    unawaited(_clearCloudWatchHistory(userId));
  }

  bool _canUseCloudWatchHistory(String userId) {
    final firebaseUser = Firebase.apps.isEmpty
        ? null
        : fb_auth.FirebaseAuth.instance.currentUser;
    return userId.isNotEmpty &&
        userId != guestWatchHistoryUserId &&
        firebaseUser != null &&
        firebaseUser.uid == userId;
  }

  CollectionReference<Map<String, dynamic>> _cloudWatchHistoryCollection(
    String userId,
  ) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('watch_history');
  }

  Future<void> _saveWatchEntryToCloud(WatchEntry entry) async {
    if (!_canUseCloudWatchHistory(entry.userId)) return;

    final key = '${entry.userId}:${entry.animeId}';
    final now = DateTime.now();
    final lastSave = _lastCloudWatchEntrySaves[key];
    // Throttle cloud updates during ongoing playback (at most once every 30s)
    // Completed status always writes immediately.
    if (!entry.isCompleted &&
        lastSave != null &&
        now.difference(lastSave).inSeconds < 30) {
      return;
    }
    _lastCloudWatchEntrySaves[key] = now;

    try {
      await _cloudWatchHistoryCollection(entry.userId).doc(entry.animeId).set({
        ...entry.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Cloud watch history save failed: $e');
    }
  }

  Future<void> _saveWatchEntriesToCloud(List<WatchEntry> entries) async {
    final entriesByUser = <String, List<WatchEntry>>{};
    for (final entry in entries) {
      entriesByUser.putIfAbsent(entry.userId, () => []).add(entry);
    }

    for (final userEntries in entriesByUser.values) {
      final userId = userEntries.first.userId;
      if (!_canUseCloudWatchHistory(userId)) continue;

      try {
        WriteBatch? batch;
        var batchSize = 0;
        for (final entry in userEntries) {
          batch ??= FirebaseFirestore.instance.batch();
          batch.set(
            _cloudWatchHistoryCollection(userId).doc(entry.animeId),
            {...entry.toJson(), 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
          batchSize++;

          if (batchSize >= 450) {
            await batch.commit();
            batch = null;
            batchSize = 0;
          }
        }
        if (batch != null && batchSize > 0) {
          await batch.commit();
        }
      } catch (e) {
        debugPrint('Cloud watch history batch save failed: $e');
      }
    }
  }

  Future<void> _deleteCloudWatchEntry(String userId, String animeId) async {
    if (!_canUseCloudWatchHistory(userId)) return;

    try {
      await _cloudWatchHistoryCollection(userId).doc(animeId).delete();
    } catch (e) {
      debugPrint('Cloud watch history delete failed: $e');
    }
  }

  Future<void> _clearCloudWatchHistory(String userId) async {
    if (!_canUseCloudWatchHistory(userId)) return;

    try {
      final snapshot = await _cloudWatchHistoryCollection(userId).get();
      WriteBatch? batch;
      var batchSize = 0;

      for (final doc in snapshot.docs) {
        batch ??= FirebaseFirestore.instance.batch();
        batch.delete(doc.reference);
        batchSize++;

        if (batchSize >= 450) {
          await batch.commit();
          batch = null;
          batchSize = 0;
        }
      }

      if (batch != null && batchSize > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Cloud watch history clear failed: $e');
    }
  }

  WatchEntry? _watchEntryFromCloud(
    String userId,
    String docId,
    Map<String, dynamic> data,
  ) {
    try {
      final animeId = data['animeId']?.toString() ?? docId;
      final watchedSeconds =
          (data['watchedDurationSeconds'] as num?)?.toInt() ?? 0;
      final rawLastWatchedAt = data['lastWatchedAt'];
      final DateTime lastWatchedAt;

      if (rawLastWatchedAt is Timestamp) {
        lastWatchedAt = rawLastWatchedAt.toDate();
      } else if (rawLastWatchedAt is String) {
        lastWatchedAt = DateTime.parse(rawLastWatchedAt);
      } else {
        lastWatchedAt = DateTime.now();
      }

      return WatchEntry(
        id: data['id']?.toString() ?? '${animeId}_history',
        userId: data['userId']?.toString() ?? userId,
        animeId: animeId,
        lastWatchedEpisode: (data['lastWatchedEpisode'] as num?)?.toInt() ?? 1,
        watchedDuration: Duration(seconds: watchedSeconds),
        lastWatchedAt: lastWatchedAt,
        isCompleted: data['isCompleted'] == true,
        isExternalSync: data['isExternalSync'] == true,
        externalListStatus: data['externalListStatus']?.toString(),
      );
    } catch (e) {
      debugPrint('Cloud watch history parse failed: $e');
      return null;
    }
  }

  Future<void> syncWatchHistoryForUser(String userId) async {
    if (!_canUseCloudWatchHistory(userId)) return;

    try {
      final snapshot = await _cloudWatchHistoryCollection(userId).get();
      final cloudEntries = <String, WatchEntry>{};

      for (final doc in snapshot.docs) {
        final entry = _watchEntryFromCloud(userId, doc.id, doc.data());
        if (entry != null) {
          cloudEntries[entry.animeId] = entry;
        }
      }

      final allHistory = _getAllWatchHistory();
      final localEntries = <String, WatchEntry>{
        for (final entry in allHistory.where((entry) => entry.userId == userId))
          entry.animeId: entry,
      };
      final mergedEntries = Map<String, WatchEntry>.from(localEntries);

      for (final cloudEntry in cloudEntries.values) {
        final localEntry = localEntries[cloudEntry.animeId];
        if (localEntry == null ||
            cloudEntry.lastWatchedAt.isAfter(localEntry.lastWatchedAt)) {
          mergedEntries[cloudEntry.animeId] = cloudEntry;
        }
      }

      final unrelatedHistory = allHistory
          .where((entry) => entry.userId != userId)
          .toList(growable: false);
      await _saveAllWatchHistory([
        ...unrelatedHistory,
        ...mergedEntries.values,
      ]);

      for (final localEntry in localEntries.values) {
        final cloudEntry = cloudEntries[localEntry.animeId];
        if (cloudEntry == null ||
            localEntry.lastWatchedAt.isAfter(cloudEntry.lastWatchedAt)) {
          unawaited(_saveWatchEntryToCloud(localEntry));
        }
      }
    } catch (e) {
      debugPrint('Cloud watch history sync failed: $e');
    }
  }

  // --- External list integrations ---
  String _externalListConnectionKey(ExternalListProvider provider) {
    return '$_externalListConnectionPrefix${provider.key}';
  }

  String _externalListPendingAuthKey(ExternalListProvider provider) {
    return '$_externalListPendingAuthPrefix${provider.key}';
  }

  ExternalListConnection? _readExternalListConnection(
    ExternalListProvider provider,
  ) {
    final raw = _prefs.getString(_externalListConnectionKey(provider));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return ExternalListConnection.fromJson(decoded);
    } catch (e) {
      debugPrint('External list connection parse failed: $e');
      return null;
    }
  }

  Map<ExternalListProvider, ExternalListConnection>
  _getStoredExternalListConnections() {
    final connections = <ExternalListProvider, ExternalListConnection>{};

    for (final provider in ExternalListProvider.values) {
      final connection = _readExternalListConnection(provider);
      if (connection != null) {
        connections[provider] = connection;
      }
    }

    return connections;
  }

  ExternalListProvider? getActiveExternalListProvider() {
    final raw = _prefs.getString(_activeExternalListProviderKey);
    if (raw == null || raw.isEmpty) return null;
    return ExternalListProviderDetails.fromKey(raw);
  }

  ExternalListConnection? getActiveExternalListConnection() {
    final connections = _getStoredExternalListConnections();
    if (connections.isEmpty) return null;

    final activeProvider = getActiveExternalListProvider();
    final activeConnection = activeProvider == null
        ? null
        : connections[activeProvider];
    if (activeConnection != null) return activeConnection;

    final sortedConnections = connections.values.toList()
      ..sort((a, b) => b.connectedAt.compareTo(a.connectedAt));
    return sortedConnections.first;
  }

  ExternalListConnection? getExternalListConnection(
    ExternalListProvider provider,
  ) {
    final activeConnection = getActiveExternalListConnection();
    return activeConnection?.provider == provider ? activeConnection : null;
  }

  Map<ExternalListProvider, ExternalListConnection>
  getExternalListConnections() {
    final activeConnection = getActiveExternalListConnection();
    if (activeConnection == null) {
      return <ExternalListProvider, ExternalListConnection>{};
    }
    return <ExternalListProvider, ExternalListConnection>{
      activeConnection.provider: activeConnection,
    };
  }

  Future<void> saveExternalListConnection(
    ExternalListConnection connection,
  ) async {
    for (final provider in ExternalListProvider.values) {
      if (provider == connection.provider) continue;
      await _prefs.remove(_externalListConnectionKey(provider));
      await clearExternalListPendingAuthorization(provider);
    }
    await _prefs.setString(
      _activeExternalListProviderKey,
      connection.provider.key,
    );
    await _prefs.setString(
      _externalListConnectionKey(connection.provider),
      jsonEncode(connection.toJson()),
    );
  }

  Future<void> removeExternalListConnection(
    ExternalListProvider provider,
  ) async {
    await _prefs.remove(_externalListConnectionKey(provider));
    if (getActiveExternalListProvider() == provider) {
      await _prefs.remove(_activeExternalListProviderKey);
    }
    await clearExternalListPendingAuthorization(provider);
  }

  ExternalListPendingAuthorization? getExternalListPendingAuthorization(
    ExternalListProvider provider,
  ) {
    final raw = _prefs.getString(_externalListPendingAuthKey(provider));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return ExternalListPendingAuthorization.fromJson(decoded);
    } catch (e) {
      debugPrint('External list pending authorization parse failed: $e');
      return null;
    }
  }

  Future<void> saveExternalListPendingAuthorization(
    ExternalListPendingAuthorization authorization,
  ) async {
    await _prefs.setString(
      _externalListPendingAuthKey(authorization.provider),
      jsonEncode(authorization.toJson()),
    );
  }

  Future<void> clearExternalListPendingAuthorization(
    ExternalListProvider provider,
  ) async {
    await _prefs.remove(_externalListPendingAuthKey(provider));
  }

  Future<void> markAppLaunched() async {
    await _prefs.setBool('_app_launched', true);
  }

  // --- Settings ---
  String getVideoQualityPreference() {
    return _prefs.getString(_settingsQualityKey) ?? '1080p';
  }

  Future<void> setVideoQualityPreference(String quality) async {
    await _prefs.setString(_settingsQualityKey, quality);
  }

  String getVideoDisplayModePreference() {
    return _prefs.getString(_settingsVideoDisplayModeKey) ?? 'fit_16_9';
  }

  Future<void> setVideoDisplayModePreference(String mode) async {
    await _prefs.setString(_settingsVideoDisplayModeKey, mode);
  }

  String getSubtitlePreference() {
    return _prefs.getString(_settingsSubtitlesKey) ?? 'English';
  }

  Future<void> setSubtitlePreference(String language) async {
    await _prefs.setString(_settingsSubtitlesKey, language);
  }

  double getSubtitleSizePreference() {
    return _prefs.getDouble(_settingsSubsSizeKey) ?? 14.0;
  }

  Future<void> setSubtitleSizePreference(double size) async {
    await _prefs.setDouble(_settingsSubsSizeKey, size);
  }

  double getPlaybackSpeedPreference() {
    return _prefs.getDouble(_settingsPlaybackSpeedKey) ?? 1.0;
  }

  Future<void> setPlaybackSpeedPreference(double speed) async {
    await _prefs.setDouble(_settingsPlaybackSpeedKey, speed);
  }

  bool getNotificationsPreference() {
    return _prefs.getBool(_settingsNotificationsKey) ?? true;
  }

  Future<void> setNotificationsPreference(bool enabled) async {
    await _prefs.setBool(_settingsNotificationsKey, enabled);
  }

  bool getMaintenanceMode() {
    return _prefs.getBool(_maintenanceModeKey) ?? false;
  }

  Future<void> setMaintenanceMode(bool enabled) async {
    await _prefs.setBool(_maintenanceModeKey, enabled);
  }

  String? getDismissedUpdateVersion() {
    return _prefs.getString(_dismissedUpdateVersionKey);
  }

  Future<void> setDismissedUpdateVersion(String version) async {
    await _prefs.setString(_dismissedUpdateVersionKey, version);
  }

  // --- Playback Preferences ---
  static const String _autoPlayNextKey = 'settings_auto_play_next';

  bool getAutoPlayNext() {
    return _prefs.getBool(_autoPlayNextKey) ?? true;
  }

  Future<void> setAutoPlayNext(bool enabled) async {
    await _prefs.setBool(_autoPlayNextKey, enabled);
  }

  static const String _settingsDnsModeKey = 'settings_dns_mode';

  String getDnsModePreference() {
    final value = _prefs.getString(_settingsDnsModeKey) ?? 'Off';
    return value == 'Default' ? 'Off' : value;
  }

  Future<void> setDnsModePreference(String mode) async {
    await _prefs.setString(_settingsDnsModeKey, mode);
  }

  String getDefaultAudioPreference() {
    return _prefs.getString(_defaultAudioKey) ?? 'SUB';
  }

  Future<void> setDefaultAudioPreference(String audio) async {
    await _prefs.setString(_defaultAudioKey, audio);
  }

  String getDefaultServerPreference() {
    final val = _prefs.getString(_defaultServerKey);
    if (val == null || val.isEmpty || val == 'HD-1') return 'Gojo';
    if (val == 'HD-2') return 'Kakashi';
    if (val == 'StreamSB') return 'Luffy';
    return val;
  }

  Future<void> setDefaultServerPreference(String server) async {
    await _prefs.setString(_defaultServerKey, server);
  }

  String getSubtitleTextStylePreference() {
    return _prefs.getString(_subtitleTextStyleKey) ?? 'normal';
  }

  Future<void> setSubtitleTextStylePreference(String style) async {
    await _prefs.setString(_subtitleTextStyleKey, style);
  }

  int getSubtitleTextColorValue() {
    return _prefs.getInt(_subtitleTextColorKey) ?? 0xFFFFFFFF;
  }

  Future<void> setSubtitleTextColorValue(int colorValue) async {
    await _prefs.setInt(_subtitleTextColorKey, colorValue);
  }

  /// A null value means subtitles are rendered without a background panel.
  int? getSubtitleBackgroundColorValue() {
    final value = _prefs.getInt(_subtitleBackgroundColorKey);
    if (value == -1) return null;
    return value ?? 0xFF000000;
  }

  Future<void> setSubtitleBackgroundColorValue(int? colorValue) async {
    await _prefs.setInt(_subtitleBackgroundColorKey, colorValue ?? -1);
  }

  /// Vertical placement from 0 (closest to player controls) to 1 (higher).
  double getSubtitleBottomPosition() {
    return _prefs.getDouble(_subtitleBottomPositionKey) ?? 0.0;
  }

  Future<void> setSubtitleBottomPosition(double position) async {
    await _prefs.setDouble(_subtitleBottomPositionKey, position);
  }

  /// Shadow intensity from 0 to 1.
  double getSubtitleTextShadow() {
    return _prefs.getDouble(_subtitleTextShadowKey) ?? 0.55;
  }

  Future<void> setSubtitleTextShadow(double intensity) async {
    await _prefs.setDouble(_subtitleTextShadowKey, intensity);
  }

  double getSubtitleBackgroundOpacity() {
    return _prefs.getDouble(_subtitleBackgroundOpacityKey) ?? 0.78;
  }

  Future<void> setSubtitleBackgroundOpacity(double opacity) async {
    await _prefs.setDouble(_subtitleBackgroundOpacityKey, opacity);
  }

  Future<void> resetSubtitleAppearancePreferences() async {
    await Future.wait([
      _prefs.remove(_settingsSubtitlesKey),
      _prefs.remove(_settingsSubsSizeKey),
      _prefs.remove(_subtitleTextStyleKey),
      _prefs.remove(_subtitleTextColorKey),
      _prefs.remove(_subtitleBackgroundColorKey),
      _prefs.remove(_subtitleBottomPositionKey),
      _prefs.remove(_subtitleTextShadowKey),
      _prefs.remove(_subtitleBackgroundOpacityKey),
    ]);
  }

  // --- Anime Metadata Cache ---
  Anime? getProviderCachedAnime(String provider, String id) {
    final raw = _prefs.getString(
      'metadata_${provider}_${Uri.encodeComponent(id)}',
    );
    if (raw == null) return null;
    try {
      return Anime.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProviderCachedAnime(String provider, Anime anime) async {
    await _prefs.setString(
      'metadata_${provider}_${Uri.encodeComponent(anime.id)}',
      jsonEncode(anime.toJson()),
    );
  }

  static const String _animeCacheKey = 'cached_anime_details';

  Map<String, Anime> _readAnimeCacheById() {
    final existing = _animeCacheById;
    if (existing != null) return existing;

    final parsed = <String, Anime>{};
    for (final item in _prefs.getStringList(_animeCacheKey) ?? const []) {
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        final anime = Anime.fromJson(decoded);
        parsed[anime.id] = anime;
      } catch (_) {}
    }
    _animeCacheById = parsed;
    return parsed;
  }

  Future<void> _persistAnimeCache(Map<String, Anime> cacheById) {
    final encoded = cacheById.values
        .map((anime) => jsonEncode(anime.toJson()))
        .toList(growable: false);
    final write = _animeCacheWriteQueue.then<void>((_) async {
      await _prefs.setStringList(_animeCacheKey, encoded);
    });
    _animeCacheWriteQueue = write.catchError((_) {});
    return write;
  }

  List<Anime> getCachedAnime() {
    return List<Anime>.unmodifiable(_readAnimeCacheById().values);
  }

  Anime? getCachedAnimeById(String id) {
    final cleanId = id.contains('_') ? id.split('_').first.trim() : id.trim();
    final cacheMap = _readAnimeCacheById();
    if (cacheMap.containsKey(cleanId)) return cacheMap[cleanId];
    if (cacheMap.containsKey(id)) return cacheMap[id];

    for (final anime in cacheMap.values) {
      if (anime.id == cleanId ||
          anime.malId == cleanId ||
          anime.aniListId == cleanId ||
          anime.id == id ||
          anime.malId == id ||
          anime.aniListId == id) {
        return anime;
      }
    }
    return null;
  }

  Future<void> saveAnimeToCache(Anime anime) async {
    final cacheById = _readAnimeCacheById();
    cacheById[anime.id] = anime;
    await _persistAnimeCache(cacheById);
  }

  // --- Episode Cache ---
  static const String _episodeCachePrefix = 'cached_episodes_v1_';
  static const String _episodeCacheTimePrefix = 'cached_episodes_time_v1_';

  String _episodeCacheSuffix(String animeId) => Uri.encodeComponent(animeId);

  List<Episode>? getCachedEpisodes(
    String animeId, {
    Duration maxAge = const Duration(hours: 6),
  }) {
    final suffix = _episodeCacheSuffix(animeId);
    final savedAt = _prefs.getInt('$_episodeCacheTimePrefix$suffix');
    if (savedAt == null ||
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(savedAt),
            ) >
            maxAge) {
      return null;
    }

    final rawData = _prefs.getStringList('$_episodeCachePrefix$suffix');
    if (rawData == null || rawData.isEmpty) return null;
    try {
      return rawData
          .map(
            (item) =>
                Episode.fromJson(jsonDecode(item) as Map<String, dynamic>),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveEpisodesToCache(
    String animeId,
    List<Episode> episodes,
  ) async {
    if (episodes.isEmpty) return;
    final suffix = _episodeCacheSuffix(animeId);
    final encoded = episodes
        .map((episode) => jsonEncode(episode.toJson()))
        .toList(growable: false);
    await Future.wait([
      _prefs.setStringList('$_episodeCachePrefix$suffix', encoded),
      _prefs.setInt(
        '$_episodeCacheTimePrefix$suffix',
        DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
  }

  // --- Category List Cache ---
  // Version the keys so category rows cached while the MegaPlay availability
  // gate was active are not shown instead of the full MAL/AniList response.
  static const String _legacyCategoryCachePrefix = 'cached_category_list_';
  static const String _legacyCategoryCacheTimePrefix = 'cached_category_time_';
  static const String _categoryCachePrefix = 'cached_category_list_v2_';
  static const String _categoryCacheTimePrefix = 'cached_category_time_v2_';

  List<Anime>? getCachedCategoryList(String categoryKey) {
    final rawData = _prefs.getStringList('$_categoryCachePrefix$categoryKey');
    if (rawData == null || rawData.isEmpty) return null;

    try {
      return rawData.map((item) {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        return Anime.fromJson(decoded);
      }).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCategoryListToCache(
    String categoryKey,
    List<Anime> list,
  ) async {
    final encoded = list.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList('$_categoryCachePrefix$categoryKey', encoded);
    await _prefs.setInt(
      '$_categoryCacheTimePrefix$categoryKey',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> clearCachedCategoryLists() async {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_legacyCategoryCachePrefix) ||
          key.startsWith(_legacyCategoryCacheTimePrefix) ||
          key.startsWith(_categoryCachePrefix) ||
          key.startsWith(_categoryCacheTimePrefix)) {
        await _prefs.remove(key);
      }
    }
  }

  bool getUseMockAuth() {
    return _prefs.getBool('use_mock_auth') == true;
  }

  Future<void> setUseMockAuth(bool enabled) async {
    await _prefs.setBool('use_mock_auth', enabled);
  }

  // --- Search History ---
  static const String _searchHistoryKey = 'search_history_queries';

  List<String> getSearchHistory() {
    return _prefs.getStringList(_searchHistoryKey) ?? const [];
  }

  Future<void> addToSearchHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final list = getSearchHistory().toList(); // Make a mutable copy
    list.remove(trimmed);
    list.insert(0, trimmed);
    if (list.length > 10) {
      list.removeLast();
    }
    await _prefs.setStringList(_searchHistoryKey, list);
  }

  Future<void> clearSearchHistory() async {
    await _prefs.remove(_searchHistoryKey);
  }

  // --- Smart Collections ---
  static const String _collectionsKey = 'user_custom_collections_v2';

  List<AnimeCollection> getCollections() {
    final raw = _prefs.getStringList(_collectionsKey);
    if (raw == null || raw.isEmpty) {
      return _buildDefaultThematicCollections();
    }

    try {
      final list = raw.map((item) {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        return AnimeCollection.fromJson(decoded);
      }).toList();

      // If the stored collections are just the old empty status duplicates, upgrade to thematic collections
      final isLegacyStatusOnly = list.every(
        (c) =>
            c.id == 'col_plan_to_watch' ||
            c.id == 'col_watching' ||
            c.id == 'col_completed' ||
            c.id == 'col_favorites',
      );

      if (isLegacyStatusOnly && list.every((c) => c.animeIds.isEmpty)) {
        return _buildDefaultThematicCollections();
      }

      return list;
    } catch (_) {
      return _buildDefaultThematicCollections();
    }
  }

  List<AnimeCollection> _buildDefaultThematicCollections() {
    return [
      AnimeCollection(
        id: 'col_masterpieces',
        name: 'All-Time Masterpieces',
        description: 'Timeless anime essentials and legendary storytelling.',
        animeIds: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      AnimeCollection(
        id: 'col_action',
        name: 'High-Octane Shonen',
        description: 'Intense battles, hype arcs, and heroic power upgrades.',
        animeIds: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      AnimeCollection(
        id: 'col_chill',
        name: 'Cozy & Slice of Life',
        description:
            'Heartwarming adventures, comedy, and relaxing comfort watches.',
        animeIds: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      AnimeCollection(
        id: 'col_thrillers',
        name: 'Mind-Bending Thrillers',
        description: 'Psychological mystery, dark fantasy, and plot twists.',
        animeIds: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }

  Future<void> saveCollections(List<AnimeCollection> collections) async {
    final encoded = collections.map((c) => jsonEncode(c.toJson())).toList();
    await _prefs.setStringList(_collectionsKey, encoded);
  }

  Future<AnimeCollection> createCollection(
    String name, {
    String description = '',
  }) async {
    final list = getCollections();
    final newId = 'col_${DateTime.now().millisecondsSinceEpoch}';
    final collection = AnimeCollection(
      id: newId,
      name: name.trim(),
      description: description.trim(),
      animeIds: const [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    list.add(collection);
    await saveCollections(list);
    return collection;
  }

  Future<void> deleteCollection(String id) async {
    final list = getCollections();
    list.removeWhere((c) => c.id == id);
    await saveCollections(list);
  }

  Future<void> addAnimeToCollection(String collectionId, String animeId) async {
    final list = getCollections();
    final index = list.indexWhere((c) => c.id == collectionId);
    if (index != -1) {
      final col = list[index];
      if (!col.animeIds.contains(animeId)) {
        final updatedIds = List<String>.from(col.animeIds)..add(animeId);
        list[index] = col.copyWith(
          animeIds: updatedIds,
          updatedAt: DateTime.now(),
        );
        await saveCollections(list);
      }
    }
  }

  Future<void> removeAnimeFromCollection(
    String collectionId,
    String animeId,
  ) async {
    final list = getCollections();
    final index = list.indexWhere((c) => c.id == collectionId);
    if (index != -1) {
      final col = list[index];
      if (col.animeIds.contains(animeId)) {
        final updatedIds = List<String>.from(col.animeIds)..remove(animeId);
        list[index] = col.copyWith(
          animeIds: updatedIds,
          updatedAt: DateTime.now(),
        );
        await saveCollections(list);
      }
    }
  }

  bool isAnimeInCollection(String collectionId, String animeId) {
    final list = getCollections();
    for (final c in list) {
      if (c.id == collectionId) {
        return c.animeIds.contains(animeId);
      }
    }
    return false;
  }

  // --- Desktop Visual & Playback Preferences ---
  static const String _cardSizeKey = 'settings_card_size_preference';
  static const String _skipIntroEnabledKey = 'settings_skip_intro_enabled';
  static const String _hideSocialPopupKey = 'hide_social_popup_forever';
  static const String _autoSkipIntroOutroKey = 'settings_auto_skip_intro_outro';

  String getCardSizePreference() {
    return _prefs.getString(_cardSizeKey) ?? 'standard';
  }

  Future<void> setCardSizePreference(String size) async {
    await _prefs.setString(_cardSizeKey, size);
  }

  bool getSkipIntroEnabled() {
    return _prefs.getBool(_skipIntroEnabledKey) ?? true;
  }

  Future<void> setSkipIntroEnabled(bool enabled) async {
    await _prefs.setBool(_skipIntroEnabledKey, enabled);
  }

  bool getAutoSkipIntroOutro() {
    return _prefs.getBool(_autoSkipIntroOutroKey) ?? false;
  }

  Future<void> setAutoSkipIntroOutro(bool enabled) async {
    await _prefs.setBool(_autoSkipIntroOutroKey, enabled);
  }

  bool getHideSocialPopupForever() {
    return _prefs.getBool(_hideSocialPopupKey) ?? false;
  }

  Future<bool> setHideSocialPopupForever(bool hide) async {
    return _prefs.setBool(_hideSocialPopupKey, hide);
  }
}
