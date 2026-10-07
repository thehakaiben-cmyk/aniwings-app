class Anime {
  final String id;
  final String title;
  final String description;
  final String posterUrl;
  final String backdropUrl;
  final double rating;
  final String status; // Ongoing, Completed
  final List<String> genres;
  final int totalEpisodes;
  final String year;
  final int episodeDurationMinutes;
  final String? nextEpisodeDate;
  final String? broadcastDay;
  final String? type;
  final String? broadcastTime;
  final String? countryOfOrigin;
  // Source identifiers and aliases are kept with the metadata so video
  // availability can be resolved without replacing any MAL/AniList fields.
  final String? malId;
  final String? aniListId;
  final List<String> alternativeTitles;

  Anime({
    required this.id,
    required this.title,
    required String description,
    required this.posterUrl,
    required this.backdropUrl,
    required this.rating,
    required this.status,
    required this.genres,
    required this.totalEpisodes,
    required this.year,
    this.episodeDurationMinutes = 24,
    this.nextEpisodeDate,
    this.broadcastDay,
    this.type = 'TV',
    this.broadcastTime,
    this.countryOfOrigin,
    this.malId,
    this.aniListId,
    this.alternativeTitles = const [],
  }) : description = _cleanHtml(description);

  static String _cleanHtml(String htmlString) {
    var cleaned = htmlString.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]*>'), '');
    cleaned = cleaned.replaceAll('&quot;', '"');
    cleaned = cleaned.replaceAll('&amp;', '&');
    cleaned = cleaned.replaceAll('&lt;', '<');
    cleaned = cleaned.replaceAll('&gt;', '>');
    cleaned = cleaned.replaceAll('&nbsp;', ' ');
    return cleaned.trim();
  }

  String getFormattedLocalBroadcastTime() {
    if (broadcastTime == null || broadcastTime!.isEmpty) {
      final idVal = int.tryParse(id) ?? title.hashCode;
      final hour = 8 + (idVal.abs() % 14);
      final minute = (idVal.abs() % 4) * 15;
      final isPm = hour >= 12;
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      final minuteStr = minute == 0 ? '00' : '$minute';
      final period = isPm ? 'PM' : 'AM';
      return '$displayHour:$minuteStr $period';
    }

    final trimmed = broadcastTime!.trim();
    if (trimmed.toUpperCase().contains('AM') ||
        trimmed.toUpperCase().contains('PM')) {
      return trimmed;
    }

    try {
      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1].split(' ')[0]);

        final now = DateTime.now();
        final tokyoDateTime = DateTime.utc(
          now.year,
          now.month,
          now.day,
          hours,
          minutes,
        );
        final utcDateTime = tokyoDateTime.subtract(const Duration(hours: 9));

        final localDateTime = utcDateTime.toLocal();
        final localHours = localDateTime.hour;
        final localMinutes = localDateTime.minute;

        final isPm = localHours >= 12;
        final displayHour = localHours == 0
            ? 12
            : (localHours > 12 ? localHours - 12 : localHours);
        final minuteStr = localMinutes < 10
            ? '0$localMinutes'
            : '$localMinutes';
        final period = isPm ? 'PM' : 'AM';
        return '$displayHour:$minuteStr $period';
      }
    } catch (_) {}

    final idVal = int.tryParse(id) ?? title.hashCode;
    final hour = 8 + (idVal.abs() % 14);
    final minute = (idVal.abs() % 4) * 15;
    final isPm = hour >= 12;
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final minuteStr = minute == 0 ? '00' : '$minute';
    final period = isPm ? 'PM' : 'AM';
    return '$displayHour:$minuteStr $period';
  }

  factory Anime.fromJson(Map<String, dynamic> json) {
    return Anime(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      posterUrl: json['posterUrl'] as String,
      backdropUrl: json['backdropUrl'] as String,
      rating: (json['rating'] as num).toDouble(),
      status: json['status'] as String,
      genres: List<String>.from(json['genres'] as List),
      totalEpisodes: json['totalEpisodes'] as int,
      year: json['year'] as String,
      episodeDurationMinutes: json['episodeDurationMinutes'] as int? ?? 24,
      nextEpisodeDate: json['nextEpisodeDate'] as String?,
      broadcastDay: json['broadcastDay'] as String?,
      type: json['type'] as String? ?? 'TV',
      broadcastTime: json['broadcastTime'] as String?,
      malId: json['malId'] as String?,
      aniListId: json['aniListId'] as String?,
      alternativeTitles: List<String>.from(
        json['alternativeTitles'] as List? ?? const [],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'rating': rating,
      'status': status,
      'genres': genres,
      'totalEpisodes': totalEpisodes,
      'year': year,
      'episodeDurationMinutes': episodeDurationMinutes,
      'nextEpisodeDate': nextEpisodeDate,
      'broadcastDay': broadcastDay,
      'type': type,
      'broadcastTime': broadcastTime,
      'malId': malId,
      'aniListId': aniListId,
      'alternativeTitles': alternativeTitles,
    };
  }

  Anime copyWith({
    String? id,
    String? title,
    String? description,
    String? posterUrl,
    String? backdropUrl,
    double? rating,
    String? status,
    List<String>? genres,
    int? totalEpisodes,
    String? year,
    int? episodeDurationMinutes,
    String? nextEpisodeDate,
    String? broadcastDay,
    String? type,
    String? broadcastTime,
    String? malId,
    String? aniListId,
    List<String>? alternativeTitles,
  }) {
    return Anime(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      rating: rating ?? this.rating,
      status: status ?? this.status,
      genres: genres ?? this.genres,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      year: year ?? this.year,
      episodeDurationMinutes:
          episodeDurationMinutes ?? this.episodeDurationMinutes,
      nextEpisodeDate: nextEpisodeDate ?? this.nextEpisodeDate,
      broadcastDay: broadcastDay ?? this.broadcastDay,
      type: type ?? this.type,
      broadcastTime: broadcastTime ?? this.broadcastTime,
      malId: malId ?? this.malId,
      aniListId: aniListId ?? this.aniListId,
      alternativeTitles: alternativeTitles ?? this.alternativeTitles,
    );
  }
}
