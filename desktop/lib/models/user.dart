class User {
  final String id;
  final String email;
  final String username;
  final String? avatarUrl;
  final DateTime createdAt;
  final int totalHoursWatched;
  final String favoriteGenre;
  final String authProvider;

  User({
    required this.id,
    required this.email,
    required this.username,
    this.avatarUrl,
    required this.createdAt,
    required this.totalHoursWatched,
    required this.favoriteGenre,
    this.authProvider = 'email',
  });

  bool get isAdmin =>
      id == 'ZRz5NfhoaFee5jkSHPiHCFXucgC3' || id == 'mock_senthil_kumar';

  factory User.fromJson(Map<String, dynamic> json) {
    DateTime parsedCreatedAt;
    final rawCreatedAt = json['createdAt'];
    if (rawCreatedAt is String) {
      parsedCreatedAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else if (rawCreatedAt is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    } else if (rawCreatedAt != null) {
      try {
        parsedCreatedAt = (rawCreatedAt as dynamic).toDate() as DateTime;
      } catch (_) {
        parsedCreatedAt = DateTime.now();
      }
    } else {
      parsedCreatedAt = DateTime.now();
    }

    return User(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      username: (json['username'] ?? 'AniWings Fan').toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      createdAt: parsedCreatedAt,
      totalHoursWatched: (json['totalHoursWatched'] as num?)?.toInt() ?? 0,
      favoriteGenre: (json['favoriteGenre'] as String?) ?? 'Action',
      authProvider: (json['authProvider'] as String?) ?? 'email',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'avatarUrl': avatarUrl,
      'createdAt': createdAt.toIso8601String(),
      'totalHoursWatched': totalHoursWatched,
      'favoriteGenre': favoriteGenre,
      'authProvider': authProvider,
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? username,
    String? avatarUrl,
    DateTime? createdAt,
    int? totalHoursWatched,
    String? favoriteGenre,
    String? authProvider,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      totalHoursWatched: totalHoursWatched ?? this.totalHoursWatched,
      favoriteGenre: favoriteGenre ?? this.favoriteGenre,
      authProvider: authProvider ?? this.authProvider,
    );
  }
}
