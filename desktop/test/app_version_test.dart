import 'package:aniwings/core/services/device_service.dart';
import 'package:aniwings/services/app_update_service.dart';
import 'package:aniwings/widgets/desktop_update_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Desktop version names compare correctly with release metadata', () {
    expect(
      AppVersion.parse('1.1.3').isSameOrNewerThan(AppVersion.parse('1.1.3')),
      isTrue,
    );
    expect(
      AppVersion.parse('1.1.3+6').isSameOrNewerThan(AppVersion.parse('1.1.3')),
      isTrue,
    );
  });

  test('update metadata prefers desktop install URLs', () {
    final release = AppReleaseMetadata.fromJson({
      'version': '1.2.0+7',
      'minVersion': '1.1.0+1',
      'url': 'https://example.com/web',
      'apkUrl': 'https://example.com/app.apk',
      'windowsUrl': 'https://example.com/desktop.exe',
      'mandatory': false,
      'releaseNotes': ['Search polish', 'Desktop settings'],
    });

    expect(release.version, '1.2.0+7');
    expect(release.preferredDesktopUrl, 'https://example.com/desktop.exe');
    expect(release.releaseNotes, ['Search polish', 'Desktop settings']);
  });

  test(
    'extractVersionFromUrl extracts semantic version from GitHub release URLs',
    () {
      const windowsUrl =
          'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-windows-v1.2.5.exe';
      const linuxUrl =
          'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-linux-v1.2.5.AppImage';

      expect(AppReleaseMetadata.extractVersionFromUrl(windowsUrl), '1.2.5');
      expect(AppReleaseMetadata.extractVersionFromUrl(linuxUrl), '1.2.5');
      expect(
        AppReleaseMetadata.extractVersionFromUrl(
          'aniwings-desktop-windows-v1.3.0.exe',
        ),
        '1.3.0',
      );
      expect(
        AppReleaseMetadata.extractVersionFromUrl(
          'aniwings-desktop-linux-v1.3.0.AppImage',
        ),
        '1.3.0',
      );
    },
  );

  test(
    'update metadata identifies version from GitHub desktop URLs when version field is omitted',
    () {
      final release = AppReleaseMetadata.fromJson({
        'url':
            'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-windows-v1.2.5.exe',
        'windowsUrl':
            'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-windows-v1.2.5.exe',
        'linuxUrl':
            'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-linux-v1.2.5.AppImage',
      });

      expect(release.version, '1.2.5');
      expect(
        release.windowsUrl,
        contains('aniwings-desktop-windows-v1.2.5.exe'),
      );
      expect(
        release.linuxUrl,
        contains('aniwings-desktop-linux-v1.2.5.AppImage'),
      );
      expect(
        release.preferredDesktopUrl,
        contains('aniwings-desktop-windows-v1.2.5.exe'),
      );
    },
  );

  test('update metadata parses GitHub release API format directly', () {
    final release = AppReleaseMetadata.fromGitHubJson({
      'tag_name': 'v1.2.6',
      'body':
          'AniWings v1.2.6 - Added new torrent providers and desktop update banner.',
      'html_url':
          'https://github.com/thehakaiben-cmyk/aniwings-app/releases/tag/v1.2.6',
      'published_at': '2026-10-06T00:00:00Z',
      'assets': [
        {
          'name': 'aniwings-desktop-windows-v1.2.6.exe',
          'size': 62914560,
          'browser_download_url':
              'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.6/aniwings-desktop-windows-v1.2.6.exe',
        },
        {
          'name': 'aniwings-desktop-linux-v1.2.6.AppImage',
          'size': 73400320,
          'browser_download_url':
              'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.6/aniwings-desktop-linux-v1.2.6.AppImage',
        },
      ],
    });

    expect(release.version, '1.2.6');
    expect(release.windowsUrl, contains('aniwings-desktop-windows-v1.2.6.exe'));
    expect(
      release.linuxUrl,
      contains('aniwings-desktop-linux-v1.2.6.AppImage'),
    );
    expect(
      release.preferredDesktopUrl,
      contains('aniwings-desktop-windows-v1.2.6.exe'),
    );
    expect(release.releaseNotes, isNotEmpty);
  });

  test('update metadata identifies desktop version from nested desktop block', () {
    final release = AppReleaseMetadata.fromJson({
      'version': '1.2.4',
      'url': 'https://example.com/mobile.apk',
      'desktop': {
        'version': '1.2.5',
        'windowsUrl':
            'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-windows-v1.2.5.exe',
        'linuxUrl':
            'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-linux-v1.2.5.AppImage',
      },
    });

    expect(release.version, '1.2.5');
    expect(release.windowsUrl, contains('aniwings-desktop-windows-v1.2.5.exe'));
    expect(
      release.linuxUrl,
      contains('aniwings-desktop-linux-v1.2.5.AppImage'),
    );
  });

  test(
    'DeviceService reports installed desktop version on desktop platforms',
    () async {
      final version = await DeviceService.installedAppVersion();
      expect(version, '1.2.5+12');
    },
  );

  test('update service detects newer mandatory releases', () async {
    final service = AppUpdateService(
      installedVersionProvider: () async => '1.1.3+6',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/update.json')) {
          return http.Response('''
{
  "version": "1.2.0+7",
  "minVersion": "1.2.0+7",
  "windowsUrl": "https://example.com/desktop.exe",
  "mandatory": false
}
''', 200);
        }
        return http.Response('Not Found', 404);
      }),
    );

    final result = await service.check();

    expect(result.hasUpdate, isTrue);
    expect(result.isMandatory, isTrue);
    expect(result.updateUrl, 'https://example.com/desktop.exe');
  });

  test(
    'update service detects desktop update from GitHub release json',
    () async {
      final service = AppUpdateService(
        installedVersionProvider: () async => '1.2.5+12',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/update.json')) {
            return http.Response('''
{
  "windowsUrl": "https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.6/aniwings-desktop-windows-v1.2.6.exe",
  "linuxUrl": "https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.6/aniwings-desktop-linux-v1.2.6.AppImage",
  "mandatory": false
}
''', 200);
          }
          return http.Response('Not Found', 404);
        }),
      );

      final result = await service.check();

      expect(result.hasUpdate, isTrue);
      expect(result.release.version, '1.2.6');
      expect(
        result.desktopUpdateUrl,
        contains('aniwings-desktop-windows-v1.2.6.exe'),
      );
    },
  );

  test(
    'update service falls back to GitHub releases API when update.json does not have newer desktop release',
    () async {
      final service = AppUpdateService(
        installedVersionProvider: () async => '1.2.5+12',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/update.json')) {
            // Pages update.json only has old mobile APK version 1.2.4
            return http.Response('''
{
  "version": "1.2.4",
  "url": "https://example.com/mobile-1.2.4.apk"
}
''', 200);
          }
          if (request.url.path.contains('/releases/latest')) {
            // GitHub releases has new desktop v1.2.6
            return http.Response('''
{
  "tag_name": "v1.2.6",
  "body": "AniWings v1.2.6 Release Notes",
  "html_url": "https://github.com/thehakaiben-cmyk/aniwings-app/releases/tag/v1.2.6",
  "assets": [
    {
      "name": "aniwings-desktop-windows-v1.2.6.exe",
      "size": 60000000,
      "browser_download_url": "https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.6/aniwings-desktop-windows-v1.2.6.exe"
    }
  ]
}
''', 200);
          }
          return http.Response('Not Found', 404);
        }),
      );

      final result = await service.check();

      expect(result.hasUpdate, isTrue);
      expect(result.release.version, '1.2.6');
      expect(
        result.desktopUpdateUrl,
        contains('aniwings-desktop-windows-v1.2.6.exe'),
      );
    },
  );

  testWidgets(
    'DesktopUpdateBanner renders when update is available and dismisses on close',
    (tester) async {
      const update = AppUpdateCheckResult(
        currentVersion: '1.2.5+12',
        release: AppReleaseMetadata(
          version: '1.2.6',
          minVersion: '',
          url: '',
          windowsUrl:
              'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.6/aniwings-desktop-windows-v1.2.6.exe',
          mandatory: false,
          releaseNotes: ['New desktop UI enhancements'],
          releasedAt: '2026-10-06',
        ),
        hasUpdate: true,
        isMandatory: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopUpdateAvailableProvider.overrideWith((ref) {
              final notifier = DesktopUpdateNotifier(ref);
              notifier.state = update;
              return notifier;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: DesktopUpdateBanner())),
        ),
      );

      await tester.pump();

      expect(find.textContaining('AniWings Desktop v1.2.6'), findsOneWidget);
      expect(find.text("What's New"), findsOneWidget);
      expect(find.text('Download v1.2.6'), findsOneWidget);

      // Dismiss the banner
      await tester.tap(find.byTooltip('Dismiss update notice'));
      await tester.pump();

      expect(find.textContaining('AniWings Desktop v1.2.6'), findsNothing);
    },
  );

  test('update service points to cloudflare pages update url by default', () {
    final service = AppUpdateService();
    expect(
      service.updateUri(),
      Uri.parse('https://aniwings-app.pages.dev/update.json'),
    );
  });
}
