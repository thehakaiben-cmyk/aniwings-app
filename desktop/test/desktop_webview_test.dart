import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aniwings/widgets/desktop_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const plugin = MethodChannel('io.jns.webview.win');
  const controllerChannel = MethodChannel('io.jns.webview.win/42');
  const events = MethodChannel('io.jns.webview.win/42/events');

  tearDown(() {
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(controllerChannel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test(
    'Windows embed installs script channels before navigating and disposes the native view',
    () async {
      final initialization = Completer<Map<String, Object>>();
      final calls = <MethodCall>[];
      var disposed = false;
      messenger.setMockMethodCallHandler(plugin, (call) async {
        if (call.method == 'initialize') return initialization.future;
        if (call.method == 'dispose') disposed = true;
        return null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      messenger.setMockMethodCallHandler(controllerChannel, (call) async {
        calls.add(call);
        return call.method == 'addScriptToExecuteOnDocumentCreated'
            ? 'script-id'
            : null;
      });
      final controller = DesktopWebViewController();
      controller.setUserAgent('AniWings Desktop');
      controller.addJavaScriptChannel(
        'VideoExtractor',
        onMessageReceived: (_) {},
      );
      final load = controller.loadRequest(
        Uri.parse('https://example.com/embed'),
      );
      expect(calls, isEmpty);
      initialization.complete({'textureId': 42});
      await load;
      final methods = calls.map((call) => call.method).toList();
      expect(
        methods.indexOf('addScriptToExecuteOnDocumentCreated'),
        lessThan(methods.indexOf('loadUrl')),
      );
      expect(calls.last.arguments, 'https://example.com/embed');
      await controller.dispose();
      expect(disposed, isTrue);
    },
  );

  test(
    'missing Windows WebView reports failure without navigation or an unhandled exception',
    () async {
      messenger.setMockMethodCallHandler(
        plugin,
        (_) async => throw PlatformException(code: 'missing_webview2'),
      );
      final errors = <DesktopWebResourceError>[];
      final controller = DesktopWebViewController();
      controller.setNavigationDelegate(
        DesktopNavigationDelegate(onWebResourceError: errors.add),
      );
      expect(await controller.ready, isFalse);
      await controller.loadRequest(Uri.parse('https://example.com/embed'));
      expect(errors, hasLength(1));
      expect(errors.single.description, contains('Windows WebView2'));
      await controller.dispose();
    },
  );
}
