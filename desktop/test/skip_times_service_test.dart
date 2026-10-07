import 'dart:convert';
import 'package:aniwings/models/episode_skip_times.dart';
import 'package:aniwings/services/skip_times_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> payload({
  double length = 1420,
  double start = 10,
  double end = 100,
}) => {
  'found': true,
  'results': [
    {
      'skipType': 'op',
      'episodeLength': length,
      'interval': {'startTime': start, 'endTime': end},
    },
  ],
};

void main() {
  test('skip boundaries are exact and end is exclusive', () {
    final data = EpisodeSkipTimes.fromAniSkip(
      payload(),
      const Duration(seconds: 1421),
    );
    expect(data.intro!.contains(const Duration(seconds: 9)), false);
    expect(data.intro!.contains(const Duration(seconds: 10)), true);
    expect(data.intro!.contains(const Duration(seconds: 99)), true);
    expect(data.intro!.contains(const Duration(seconds: 100)), false);
    expect(data.outro, isNull);
  });
  test(
    'other cuts, malformed intervals and absent data do not invent timings',
    () {
      const duration = Duration(seconds: 1421);
      expect(
        EpisodeSkipTimes.fromAniSkip(payload(length: 1500), duration).intro,
        isNull,
      );
      expect(
        EpisodeSkipTimes.fromAniSkip(payload(start: -1), duration).intro,
        isNull,
      );
      expect(
        EpisodeSkipTimes.fromAniSkip(
          payload(start: 100, end: 20),
          duration,
        ).intro,
        isNull,
      );
      expect(
        EpisodeSkipTimes.fromAniSkip(payload(end: 1500), duration).intro,
        isNull,
      );
      expect(
        EpisodeSkipTimes.fromAniSkip({'found': false}, duration).intro,
        isNull,
      );
    },
  );
  test(
    'lookup uses MAL, episode and actual player duration and caches that cut',
    () async {
      var calls = 0;
      final service = SkipTimesService(
        MockClient((request) async {
          calls++;
          expect(request.url.path, '/v2/skip-times/60460/2');
          expect(request.url.queryParametersAll['types'], ['op', 'ed']);
          expect(request.url.queryParameters['episodeLength'], '1421.000');
          return http.Response(jsonEncode(payload()), 200);
        }),
      );
      final times = await service.getSkipTimes(
        '60460',
        2,
        const Duration(seconds: 1421),
      );
      expect(times.intro!.end, const Duration(seconds: 100));
      await service.getSkipTimes('60460', 2, const Duration(seconds: 1421));
      expect(calls, 1);
    },
  );
  test('network errors are optional and are not cached as success', () async {
    var calls = 0;
    final service = SkipTimesService(
      MockClient((request) async {
        calls++;
        return http.Response('unavailable', 503);
      }),
    );
    expect(
      (await service.getSkipTimes(
        '60460',
        2,
        const Duration(seconds: 1421),
      )).intro,
      isNull,
    );
    await service.getSkipTimes('60460', 2, const Duration(seconds: 1421));
    expect(calls, 2);
    await service.getSkipTimes('anilist_123', 2, const Duration(seconds: 1421));
    expect(calls, 2);
  });
}
