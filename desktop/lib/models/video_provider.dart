import 'episode_skip_times.dart';

class SubtitleTrack {
  final String label;
  final String language;
  final String url;

  const SubtitleTrack({
    required this.label,
    required this.language,
    required this.url,
  });
}

class VideoProviderSource {
  final String name;
  final String description;
  final String languageType; // 'SUB' or 'DUB'
  final List<String> videoUrls;
  final String speedStatus; // 'Ultra-Fast', 'Stable', 'Fast', 'Backup'
  final bool isEmbed;
  final Map<String, String>? headers;
  final String? subtitleUrl;
  final List<SubtitleTrack>? subtitleTracks;
  final EpisodeSkipTimes skipTimes;

  final String? streamFormat;
  final String? sourcePlayerUrl;

  bool get hasEmbeddedAudioControls =>
      const {'levi', 'eren', 'mikasa'}.contains(name.toLowerCase().trim());

  bool get usesTorrentPlayer =>
      name.toLowerCase() == 'levi' ||
      name.toLowerCase() == 'eren' ||
      name.toLowerCase() == 'mikasa' ||
      streamFormat == 'torrent';

  VideoProviderSource({
    required this.name,
    required this.description,
    required this.languageType,
    required this.videoUrls,
    required this.speedStatus,
    this.isEmbed = false,
    this.streamFormat,
    this.sourcePlayerUrl,
    this.headers,
    this.subtitleUrl,
    this.subtitleTracks,
    this.skipTimes = const EpisodeSkipTimes(),
  });
}
