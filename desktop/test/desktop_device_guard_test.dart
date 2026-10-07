import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aniwings/core/services/desktop_device_guard.dart';

void main() {
  test(
    'Android preview can open the desktop UI without enabling other targets',
    () async {
      expect(
        await DesktopDeviceGuard.isSupported(
          platform: TargetPlatform.android,
          web: false,
          allowEmulatorPreview: true,
        ),
        isTrue,
      );
      expect(
        await DesktopDeviceGuard.isSupported(
          platform: TargetPlatform.iOS,
          web: false,
          allowEmulatorPreview: true,
        ),
        isFalse,
      );
    },
  );
  for (final platform in TargetPlatform.values) {
    test('$platform follows desktop-only support', () async {
      expect(
        await DesktopDeviceGuard.isSupported(
          platform: platform,
          web: false,
          allowEmulatorPreview: false,
        ),
        platform == TargetPlatform.windows || platform == TargetPlatform.linux,
      );
    });
  }
  test('web and phone platforms are rejected', () async {
    expect(
      await DesktopDeviceGuard.isSupported(
        platform: TargetPlatform.windows,
        web: true,
      ),
      false,
    );
    expect(
      await DesktopDeviceGuard.isSupported(
        platform: TargetPlatform.android,
        web: false,
        allowEmulatorPreview: false,
      ),
      false,
    );
  });
  testWidgets('unsupported devices never initialize app services or routes', (
    tester,
  ) async {
    var initialized = false;
    await tester.pumpWidget(
      DesktopDeviceGate(
        check: () async => false,
        child: _StartupProbe(onInit: () => initialized = true),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('AniWings Desktop requires Windows or Linux'),
      findsOneWidget,
    );
    expect(initialized, isFalse);
  });
  testWidgets('supported desktop initializes the app', (tester) async {
    var initialized = false;
    await tester.pumpWidget(
      DesktopDeviceGate(
        check: () async => true,
        child: _StartupProbe(onInit: () => initialized = true),
      ),
    );
    await tester.pumpAndSettle();
    expect(initialized, isTrue);
    expect(
      find.text('AniWings Desktop requires Windows or Linux'),
      findsNothing,
    );
  });
}

class _StartupProbe extends StatefulWidget {
  final VoidCallback onInit;
  const _StartupProbe({required this.onInit});
  @override
  State<_StartupProbe> createState() => _StartupProbeState();
}

class _StartupProbeState extends State<_StartupProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Text('Desktop app'));
}
