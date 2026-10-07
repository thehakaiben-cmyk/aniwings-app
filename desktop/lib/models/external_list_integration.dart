enum ExternalListProvider { myAnimeList, aniList }

extension ExternalListProviderDetails on ExternalListProvider {
  String get key {
    return switch (this) {
      ExternalListProvider.myAnimeList => 'myanimelist',
      ExternalListProvider.aniList => 'anilist',
    };
  }

  String get label {
    return switch (this) {
      ExternalListProvider.myAnimeList => 'MyAnimeList',
      ExternalListProvider.aniList => 'AniList',
    };
  }

  String get logoText {
    return switch (this) {
      ExternalListProvider.myAnimeList => 'MAL',
      ExternalListProvider.aniList => 'AL',
    };
  }

  String get description {
    return switch (this) {
      ExternalListProvider.myAnimeList =>
        'Sync your anime list with MyAnimeList',
      ExternalListProvider.aniList => 'Sync your anime list with AniList',
    };
  }

  static ExternalListProvider? fromKey(String key) {
    final normalized = key.trim().toLowerCase();
    for (final provider in ExternalListProvider.values) {
      if (provider.key == normalized) return provider;
    }
    return null;
  }
}

enum ExternalListAuthResponseMode { code, token }

extension ExternalListAuthResponseModeDetails on ExternalListAuthResponseMode {
  String get key {
    return switch (this) {
      ExternalListAuthResponseMode.code => 'code',
      ExternalListAuthResponseMode.token => 'token',
    };
  }

  static ExternalListAuthResponseMode? fromKey(String key) {
    final normalized = key.trim().toLowerCase();
    for (final mode in ExternalListAuthResponseMode.values) {
      if (mode.key == normalized) return mode;
    }
    return null;
  }
}

class ExternalListConnection {
  final ExternalListProvider provider;
  final String username;
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final DateTime connectedAt;

  const ExternalListConnection({
    required this.provider,
    required this.username,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.connectedAt,
  });

  bool get canRefresh {
    return refreshToken != null && refreshToken!.isNotEmpty;
  }

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(DateTime.now());
  }

  bool get shouldRefresh {
    final expiry = expiresAt;
    if (expiry == null || !canRefresh) return false;
    return expiry.difference(DateTime.now()) < const Duration(minutes: 5);
  }

  String get expiryLabel {
    final expiry = expiresAt;
    if (expiry == null) return 'Connected';

    final date = '${_monthName(expiry.month)} ${expiry.day}, ${expiry.year}';
    return canRefresh ? 'Expires $date (auto-refresh)' : 'Expires $date';
  }

  ExternalListConnection copyWith({
    String? username,
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    DateTime? connectedAt,
  }) {
    return ExternalListConnection(
      provider: provider,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }

  factory ExternalListConnection.fromJson(Map<String, dynamic> json) {
    final provider = ExternalListProviderDetails.fromKey(
      json['provider']?.toString() ?? '',
    );
    if (provider == null) {
      throw FormatException('Unknown list provider: ${json['provider']}');
    }

    return ExternalListConnection(
      provider: provider,
      username: json['username']?.toString() ?? '',
      accessToken: json['accessToken']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString(),
      expiresAt: _dateFromJson(json['expiresAt']),
      connectedAt: _dateFromJson(json['connectedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.key,
      'username': username,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt?.toIso8601String(),
      'connectedAt': connectedAt.toIso8601String(),
    };
  }
}

class ExternalListPendingAuthorization {
  final ExternalListProvider provider;
  final String state;
  final String? codeVerifier;
  final ExternalListAuthResponseMode responseMode;
  final DateTime startedAt;

  const ExternalListPendingAuthorization({
    required this.provider,
    required this.state,
    required this.codeVerifier,
    required this.responseMode,
    required this.startedAt,
  });

  factory ExternalListPendingAuthorization.fromJson(Map<String, dynamic> json) {
    final provider = ExternalListProviderDetails.fromKey(
      json['provider']?.toString() ?? '',
    );
    final mode = ExternalListAuthResponseModeDetails.fromKey(
      json['responseMode']?.toString() ?? '',
    );
    if (provider == null || mode == null) {
      throw const FormatException('Invalid pending authorization.');
    }

    return ExternalListPendingAuthorization(
      provider: provider,
      state: json['state']?.toString() ?? '',
      codeVerifier: json['codeVerifier']?.toString(),
      responseMode: mode,
      startedAt: _dateFromJson(json['startedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.key,
      'state': state,
      'codeVerifier': codeVerifier,
      'responseMode': responseMode.key,
      'startedAt': startedAt.toIso8601String(),
    };
  }
}

DateTime? _dateFromJson(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String _monthName(int month) {
  const names = [
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
  if (month < 1 || month > 12) return '';
  return names[month - 1];
}
