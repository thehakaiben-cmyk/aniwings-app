import 'package:aniwings/core/services/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('incorrect desktop clock is identified from a media response date', () {
    expect(
      playbackClockError(
        'Fri, 02 Oct 2026 12:00:00 GMT',
        DateTime.utc(2026, 9, 26),
      ),
      contains('date/time is incorrect'),
    );
    expect(
      playbackClockError(
        'Fri, 02 Oct 2026 12:00:00 GMT',
        DateTime.utc(2026, 10, 2, 12, 5),
      ),
      isNull,
    );
  });
  test(
    'cached response age and missing dates do not produce false clock errors',
    () {
      expect(
        playbackClockError(
          'Sat, 26 Sep 2026 12:00:00 GMT',
          DateTime.utc(2026, 10, 2, 12),
          responseAge: '518400',
        ),
        isNull,
      );
      expect(playbackClockError(null, DateTime.utc(2026, 9, 26)), isNull);
      expect(playbackClockError('invalid', DateTime.utc(2026, 9, 26)), isNull);
    },
  );
}
