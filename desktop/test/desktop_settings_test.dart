import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aniwings/core/theme/app_theme.dart';
import 'package:aniwings/features/settings/desktop_settings_screen.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:aniwings/services/desktop_preferences.dart';

void main() {
  testWidgets('desktop settings align, save controls and update card density', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    await tester.runAsync(() async {
      final icons = File(
        'C:/Users/senth/develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(await icons.readAsBytes())),
            ))
            .load();
      }
      if (font.existsSync()) {
        await (FontLoader('Segoe UI')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const DesktopSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('🛠️ Crafted by Cosmic Garou'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(DesktopSettingsScreen),
      matchesGoldenFile('goldens/desktop-settings.png'),
    );
    await tester.tap(find.text('DUB'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(storageServiceProvider)
          .getDefaultAudioPreference()
          .toLowerCase(),
      'dub',
    );
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('compact'));
    await tester.pumpAndSettle();
    expect(container.read(desktopDensityProvider), 'compact');
    expect(tester.takeException(), isNull);
  });
}
