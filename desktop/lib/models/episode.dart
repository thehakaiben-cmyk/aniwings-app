class Episode {
  final String id;
  final String animeId;
  final int episodeNumber;
  final String title;
  final String? thumbnailUrl;
  final DateTime airDate;
  final Duration duration;
  final List<String>
  videoUrls; // quality configurations: e.g. [1080p, 720p, 480p]

  Episode({
    required this.id,
    required this.animeId,
    required this.episodeNumber,
    required this.title,
    this.thumbnailUrl,
    required this.airDate,
    required this.duration,
    required this.videoUrls,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id'] as String,
      animeId: json['animeId'] as String,
      episodeNumber: json['episodeNumber'] as int,
      title: json['title'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      airDate: DateTime.parse(json['airDate'] as String),
      duration: Duration(minutes: json['durationMinutes'] as int),
      videoUrls: List<String>.from(json['videoUrls'] as List),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'animeId': animeId,
      'episodeNumber': episodeNumber,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'airDate': airDate.toIso8601String(),
      'durationMinutes': duration.inMinutes,
      'videoUrls': videoUrls,
    };
  }
}
