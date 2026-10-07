import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DesktopDeviceGuard {
  static const emulatorPreviewEnabled = bool.fromEnvironment(
    'DESKTOP_EMULATOR_PREVIEW',
    defaultValue: kDebugMode,
  );

  static bool isSupportedNow({
    TargetPlatform? platform,
    bool? web,
    bool allowEmulatorPreview = emulatorPreviewEnabled,
  }) {
    if (web ?? kIsWeb) return false;
    if ((platform ?? defaultTargetPlatform) == TargetPlatform.android) {
      return allowEmulatorPreview;
    }
    return {
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(platform ?? defaultTargetPlatform);
  }

  static Future<bool> isSupported({
    TargetPlatform? platform,
    bool? web,
    bool allowEmulatorPreview = emulatorPreviewEnabled,
  }) async => isSupportedNow(
    platform: platform,
    web: web,
    allowEmulatorPreview: allowEmulatorPreview,
  );
}

class DesktopDeviceGate extends StatefulWidget {
  final Widget child;
  final Future<bool> Function()? check;
  const DesktopDeviceGate({super.key, required this.child, this.check});
  @override
  State<DesktopDeviceGate> createState() => _DesktopDeviceGateState();
}

class _DesktopDeviceGateState extends State<DesktopDeviceGate> {
  late final _supported =
      widget.check?.call() ?? DesktopDeviceGuard.isSupported();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _supported,
    builder: (_, snapshot) {
      if (widget.check == null && DesktopDeviceGuard.isSupportedNow()) {
        return widget.child;
      }
      if (snapshot.data == true) return widget.child;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF090A0F),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.desktop_windows_rounded,
                    size: 64,
                    color: Color(0xFFFF1744),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    snapshot.connectionState == ConnectionState.done
                        ? 'AniWings Desktop requires Windows or Linux'
                        : 'Starting AniWings Desktop…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ── Backwards Compatibility Aliases ──────────────────────────────────────────
