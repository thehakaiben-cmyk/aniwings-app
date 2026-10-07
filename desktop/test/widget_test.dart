import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aniwings/main.dart';
import 'package:aniwings/core/navigation/router.dart' as app_router;
import 'package:aniwings/services/storage_service.dart';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/app_update_service.dart';
import 'package:aniwings/widgets/desktop_side_nav.dart';

void main() {
  testWidgets(
    'desktop shell renders and navigates without a network dependency',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final previousSplash = app_router.splashShownThisSession;
      app_router.splashShownThisSession = true;
      addTearDown(() => app_router.splashShownThisSession = previousSplash);
      final catalogClient = MockClient(
        (_) async => http.Response(
          '{"data":{"Page":{"media":[]}},"pagination":{"has_next_page":false}}',
          200,
        ),
      );
      final updateClient = MockClient(
        (_) async => http.Response(
          '{"version":"1.2.5+12","windowsUrl":"https://example.com/desktop.exe"}',
          200,
        ),
      );
      addTearDown(catalogClient.close);
      addTearDown(updateClient.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            animeServiceProvider.overrideWithValue(
              AnimeService(client: catalogClient),
            ),
            appUpdateServiceProvider.overrideWithValue(
              AppUpdateService(
                client: updateClient,
                installedVersionProvider: () async => '1.2.5+12',
              ),
            ),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DesktopSideNav), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.settings_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('Settings & Customization'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
