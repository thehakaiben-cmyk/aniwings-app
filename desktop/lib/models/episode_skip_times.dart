class SkipInterval {
  final Duration start;
  final Duration end;

  const SkipInterval({required this.start, required this.end});

  bool contains(Duration position) => position >= start && position < end;
  bool isValidFor(Duration duration) =>
      start >= Duration.zero && end > start && end <= duration;

  static SkipInterval? fromSeconds(Object? start, Object? end) {
    if (start is! num ||
        end is! num ||
        !start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        end <= start) {
      return null;
    }
    return SkipInterval(
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
    );
  }
}

class EpisodeSkipTimes {
  final SkipInterval? intro;
  final SkipInterval? outro;

  const EpisodeSkipTimes({this.intro, this.outro});

  EpisodeSkipTimes validatedFor(Duration duration) => EpisodeSkipTimes(
    intro: intro?.isValidFor(duration) == true ? intro : null,
    outro: outro?.isValidFor(duration) == true ? outro : null,
  );

  factory EpisodeSkipTimes.fromProvider(Object? value) {
    if (value is! Map) return const EpisodeSkipTimes();
    SkipInterval? read(String name) {
      final interval = value[name];
      return interval is Map
          ? SkipInterval.fromSeconds(interval['start'], interval['end'])
          : null;
    }

    return EpisodeSkipTimes(intro: read('intro'), outro: read('outro'));
  }

  factory EpisodeSkipTimes.fromAniSkip(Object? value, Duration duration) {
    if (value is! Map || value['found'] != true || value['results'] is! List) {
      return const EpisodeSkipTimes();
    }
    SkipInterval? intro;
    SkipInterval? outro;
    var introDistance = double.infinity;
    var outroDistance = double.infinity;
    for (final result in value['results'] as List) {
      if (result is! Map || result['interval'] is! Map) continue;
      final length = result['episodeLength'];
      if (length is! num || !length.isFinite) continue;
      final distance = (length - duration.inMilliseconds / 1000)
          .abs()
          .toDouble();
      // Different edits can move the opening. Do not use another cut's timings.
      if (distance > 5) continue;
      final raw = result['interval'] as Map;
      final interval = SkipInterval.fromSeconds(
        raw['startTime'],
        raw['endTime'],
      );
      if (interval == null || !interval.isValidFor(duration)) continue;
      if (result['skipType'] == 'op' && distance < introDistance) {
        intro = interval;
        introDistance = distance;
      } else if (result['skipType'] == 'ed' && distance < outroDistance) {
        outro = interval;
        outroDistance = distance;
      }
    }
    return EpisodeSkipTimes(intro: intro, outro: outro);
  }
}
