import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aniwings/widgets/subtitle_delay_control.dart';

void main() {
  test('positive delay shows cues later without changing playback time', () {
    expect(
      subtitlePosition(const Duration(seconds: 10), const Duration(seconds: 2)),
      const Duration(seconds: 8),
    );
    expect(
      subtitlePosition(
        const Duration(seconds: 10),
        const Duration(seconds: -2),
      ),
      const Duration(seconds: 12),
    );
  });
  testWidgets('delay can be adjusted in both directions and reset', (
    tester,
  ) async {
    var value = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubtitleDelayControl(onChanged: (next) => value = next),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Subtitles 100 ms later'));
    await tester.pump();
    expect(value, 100);
    expect(find.text('+0.1 s'), findsOneWidget);
    await tester.tap(find.byTooltip('Subtitles 100 ms earlier'));
    await tester.tap(find.byTooltip('Subtitles 100 ms earlier'));
    await tester.pump();
    expect(value, -100);
    expect(find.text('-0.1 s'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(value, 0);
  });
}
