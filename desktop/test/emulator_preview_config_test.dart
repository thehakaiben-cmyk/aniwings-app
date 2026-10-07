import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android preview does not build the desktop torrent native plugin', () {
    final registry =
        jsonDecode(File('.flutter-plugins-dependencies').readAsStringSync())
            as Map;
    final android = (registry['plugins']['android'] as List).cast<Map>();
    expect(
      android.any((plugin) => plugin['name'] == 'libtorrent_flutter'),
      isFalse,
    );
    expect(
      android.any((plugin) => plugin['name'] == 'video_player_android'),
      isTrue,
    );
  });
  test(
    'preview uses the normal launcher and has no TV launcher or pairing define',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android.intent.category.LAUNCHER'));
      expect(manifest, isNot(contains('LEANBACK_LAUNCHER')));
      final runConfig = File(
        '.idea/runConfigurations/emulator_preview.xml',
      ).readAsStringSync();
      expect(runConfig, contains('DESKTOP_EMULATOR_PREVIEW=true'));
      expect(runConfig, isNot(contains('cloudflare-tv-pairing.json')));
    },
  );
}
