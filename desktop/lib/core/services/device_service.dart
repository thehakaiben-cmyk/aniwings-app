import 'dart:io';
import 'package:flutter/services.dart';

/// Native Windows window and display lifecycle helpers.
class DeviceService {
  DeviceService._();
  static const _channel = MethodChannel('com.aniwings/device');
  static const currentDesktopAppVersion = '1.2.5+12';

  static Future<void> setScreenAwake(bool enabled) async {
    if (!Platform.isWindows) return;
    await _invoke('setScreenAwake', {'enabled': enabled});
  }

  static Future<void> setDesktopFullscreen(bool enabled) async {
    if (!Platform.isWindows) return;
    await _invoke('setFullscreen', enabled);
  }

  static Future<void> _invoke(String method, Object arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // Keep playback usable if a native window operation fails.
    } on MissingPluginException {
      // Widget tests have no native runner.
    }
  }

  static Future<String?> installedAppVersion() async =>
      currentDesktopAppVersion;
  static Future<void> exitApp() => SystemNavigator.pop();
}
