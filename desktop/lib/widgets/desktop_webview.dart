import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

enum DesktopNavigationDecision { navigate, prevent }

class DesktopNavigationRequest {
  final String url;
  final bool isMainFrame;
  const DesktopNavigationRequest(this.url, {this.isMainFrame = true});
}

class DesktopJavaScriptMessage {
  final String message;
  const DesktopJavaScriptMessage(this.message);
}

class DesktopWebResourceError {
  final String description;
  final bool isForMainFrame;
  const DesktopWebResourceError(this.description, {this.isForMainFrame = true});
}

class DesktopNavigationDelegate {
  final DesktopNavigationDecision Function(DesktopNavigationRequest)?
  onNavigationRequest;
  final ValueChanged<int>? onProgress;
  final ValueChanged<String>? onPageStarted;
  final ValueChanged<String>? onPageFinished;
  final ValueChanged<DesktopWebResourceError>? onWebResourceError;
  const DesktopNavigationDelegate({
    this.onNavigationRequest,
    this.onProgress,
    this.onPageStarted,
    this.onPageFinished,
    this.onWebResourceError,
  });
}

/// Windows WebView2 bridge used by the existing embedded-player controls.
/// Initialization and script-channel setup finish before the first navigation.
class DesktopWebViewController {
  mobile.WebViewController? android;
  final native = windows.WebviewController();
  late final Future<bool> ready = _initialize();
  DesktopNavigationDelegate? _delegate;
  final _channels = <String, ValueChanged<DesktopJavaScriptMessage>>{};
  final _configuration = <Future<void>>[];
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _disposed = false;
  String _url = '';

  DesktopWebViewController() {
    unawaited(ready);
  }

  Future<bool> _initialize() async {
    try {
      if (Platform.isAndroid) {
        android = mobile.WebViewController();
        await android!.setJavaScriptMode(mobile.JavaScriptMode.unrestricted);
        await android!.setNavigationDelegate(
          mobile.NavigationDelegate(
            onNavigationRequest: (request) =>
                _delegate?.onNavigationRequest?.call(
                      DesktopNavigationRequest(
                        request.url,
                        isMainFrame: request.isMainFrame,
                      ),
                    ) ==
                    DesktopNavigationDecision.prevent
                ? mobile.NavigationDecision.prevent
                : mobile.NavigationDecision.navigate,
            onProgress: (value) => _delegate?.onProgress?.call(value),
            onPageStarted: (url) => _delegate?.onPageStarted?.call(url),
            onPageFinished: (url) => _delegate?.onPageFinished?.call(url),
            onWebResourceError: (error) => _delegate?.onWebResourceError?.call(
              DesktopWebResourceError(
                error.description,
                isForMainFrame: error.isForMainFrame ?? false,
              ),
            ),
          ),
        );
        return !_disposed;
      }
      await native.initialize();
      if (_disposed) return false;
      await native.setPopupWindowPolicy(windows.WebviewPopupWindowPolicy.deny);
      _subscriptions.add(
        native.url.listen((url) {
          if (_disposed) return;
          _url = url;
          final decision = _delegate?.onNavigationRequest?.call(
            DesktopNavigationRequest(url),
          );
          if (decision == DesktopNavigationDecision.prevent) {
            unawaited(native.stop());
          }
        }),
      );
      _subscriptions.add(
        native.loadingState.listen((state) {
          if (_disposed) return;
          if (state == windows.LoadingState.loading) {
            _delegate?.onPageStarted?.call(_url);
            _delegate?.onProgress?.call(10);
          } else if (state == windows.LoadingState.navigationCompleted) {
            _delegate?.onProgress?.call(100);
            _delegate?.onPageFinished?.call(_url);
          }
        }),
      );
      _subscriptions.add(
        native.onLoadError.listen((error) {
          if (!_disposed) {
            _delegate?.onWebResourceError?.call(
              DesktopWebResourceError(error.toString()),
            );
          }
        }),
      );
      _subscriptions.add(
        native.webMessage.listen((event) {
          if (_disposed || event is! Map) return;
          _channels[event['channel']]?.call(
            DesktopJavaScriptMessage('${event['message'] ?? ''}'),
          );
        }),
      );
      return true;
    } catch (error) {
      if (!_disposed) {
        _delegate?.onWebResourceError?.call(
          DesktopWebResourceError(
            'Windows WebView2 could not initialize: $error',
          ),
        );
      }
      return false;
    }
  }

  void setNavigationDelegate(DesktopNavigationDelegate delegate) =>
      _delegate = delegate;

  void setUserAgent(String value) {
    _configuration.add(
      _configure(
        () => android != null
            ? android!.setUserAgent(value)
            : native.setUserAgent(value),
      ),
    );
  }

  void setBackgroundColor(Color color) {
    _configuration.add(
      _configure(
        () => android != null
            ? android!.setBackgroundColor(color)
            : native.setBackgroundColor(color),
      ),
    );
  }

  Future<void> _configure(Future<void> Function() operation) async {
    if (await ready && !_disposed) await operation();
  }

  void addJavaScriptChannel(
    String name, {
    required ValueChanged<DesktopJavaScriptMessage> onMessageReceived,
  }) {
    _channels[name] = onMessageReceived;
    final key = jsonEncode(name);
    final script =
        '''window[$key] = {postMessage: function(message) {
      window.chrome.webview.postMessage({channel: $key, message: String(message)});
    }};''';
    _configuration.add(
      _configure(() async {
        if (android != null) {
          await android!.addJavaScriptChannel(
            name,
            onMessageReceived: (message) =>
                onMessageReceived(DesktopJavaScriptMessage(message.message)),
          );
        } else {
          await native.addScriptToExecuteOnDocumentCreated(script);
        }
      }),
    );
  }

  Future<void> loadRequest(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    if (!(await ready) || _disposed) return;
    try {
      await Future.wait(_configuration);
      if (_disposed) return;
      // Provider media headers are applied by the native player after extraction.
      // WebView2 owns the embedded document's HTTP requests.
      _url = uri.toString();
      if (android != null) {
        await android!.loadRequest(uri, headers: headers);
      } else {
        await native.loadUrl(_url);
      }
    } catch (error) {
      if (!_disposed) {
        _delegate?.onWebResourceError?.call(
          DesktopWebResourceError(error.toString()),
        );
      }
    }
  }

  Future<void> runJavaScript(String script) async {
    if (await ready && !_disposed) {
      if (android != null) {
        await android!.runJavaScript(script);
      } else {
        await native.executeScript(script);
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await ready;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      if (android != null) {
        await android!.loadRequest(Uri.parse('about:blank'));
      } else {
        await native.dispose();
      }
    } catch (_) {
      // Failed initialization has no native resource to release.
    }
  }
}

class DesktopWebView extends StatelessWidget {
  final DesktopWebViewController controller;
  const DesktopWebView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: controller.ready,
    builder: (context, snapshot) => snapshot.data == true
        ? controller.android != null
              ? mobile.WebViewWidget(controller: controller.android!)
              : windows.Webview(
                  controller.native,
                  permissionRequested: (_, _, _) async =>
                      windows.WebviewPermissionDecision.deny,
                )
        : const SizedBox.expand(),
  );
}
