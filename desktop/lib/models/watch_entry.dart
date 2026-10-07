enum WatchlistCategory {
  all,
  watching,
  planToWatch,
  completed,
  onHold,
  dropped,
}

extension WatchlistCategoryDetails on WatchlistCategory {
  String get label {
    return switch (this) {
      WatchlistCategory.all => 'All',
      WatchlistCategory.watching => 'Watching',
      WatchlistCategory.planToWatch => 'Plan to Watch',
      WatchlistCategory.completed => 'Completed',
      WatchlistCategory.onHold => 'On-Hold',
      WatchlistCategory.dropped => 'Dropped',
    };
  }
}

class WatchEntry {
  final String id;
  final String userId;
  final String animeId;
  final int lastWatchedEpisode;
  final Duration watchedDuration;
  final DateTime lastWatchedAt;
  final bool isCompleted;
  final bool isExternalSync;
  final String? externalListStatus;

  WatchEntry({
    required this.id,
    required this.userId,
    required this.animeId,
    required this.lastWatchedEpisode,
    required this.watchedDuration,
    required this.lastWatchedAt,
    required this.isCompleted,
    this.isExternalSync = false,
    this.externalListStatus,
  });

  WatchlistCategory get watchlistCategory {
    final status = (externalListStatus ?? '').toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    if (status == 'dropped') return WatchlistCategory.dropped;
    if (status == 'on_hold' || status == 'onhold' || status == 'paused') {
      return WatchlistCategory.onHold;
    }
    if (status == 'planning' ||
        status == 'plan_to_watch' ||
        status == 'plantowatch' ||
        status == 'ptw') {
      return WatchlistCategory.planToWatch;
    }
    if (status == 'completed' || status == 'complete' || status == 'finished') {
      return WatchlistCategory.completed;
    }
    if (status == 'watching' || status == 'current') {
      return WatchlistCategory.watching;
    }
    if (isCompleted) return WatchlistCategory.completed;
    if (lastWatchedEpisode > 0) return WatchlistCategory.watching;
    return WatchlistCategory.planToWatch;
  }

  String get formattedWatchedDuration {
    final m = watchedDuration.inMinutes;
    final s = watchedDuration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$m:$s';
  }

  double get progressPercentage {
    if (isCompleted) return 1.0;
    const standardDurationSeconds = 1440;
    final progress = watchedDuration.inSeconds / standardDurationSeconds;
    return progress.clamp(0.05, 1.0);
  }

  factory WatchEntry.fromJson(Map<String, dynamic> json) {
    return WatchEntry(
      id: json['id'] as String,
      userId: json['userId'] as String,
      animeId: json['animeId'] as String,
      lastWatchedEpisode: json['lastWatchedEpisode'] as int,
      watchedDuration: Duration(seconds: json['watchedDurationSeconds'] as int),
      lastWatchedAt: DateTime.parse(json['lastWatchedAt'] as String),
      isCompleted: json['isCompleted'] as bool,
      isExternalSync: json['isExternalSync'] == true,
      externalListStatus: json['externalListStatus']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'animeId': animeId,
      'lastWatchedEpisode': lastWatchedEpisode,
      'watchedDurationSeconds': watchedDuration.inSeconds,
      'lastWatchedAt': lastWatchedAt.toIso8601String(),
      'isCompleted': isCompleted,
      'isExternalSync': isExternalSync,
      'externalListStatus': externalListStatus,
    };
  }
}
