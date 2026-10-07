import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Keeps TLS and response-byte processing off the foreground playback isolate.
class ArtworkDownloadWorker {
  static final shared = ArtworkDownloadWorker();
  final _messages = ReceivePort();
  final _waiting = <int, Completer<Uint8List>>{};
  final _ready = Completer<SendPort>();
  Isolate? _isolate;
  var _nextId = 0;
  bool _started = false;

  Future<Uint8List> load(String url) async {
    if (!_started) {
      _started = true;
      _messages.listen((message) {
        if (message is SendPort) {
          _ready.complete(message);
          return;
        }
        final result = message as List;
        final pending = _waiting.remove(result[0] as int);
        if (pending == null) return;
        if (result[1] is TransferableTypedData) {
          pending.complete(
            (result[1] as TransferableTypedData).materialize().asUint8List(),
          );
        } else {
          pending.completeError(StateError(result[2] as String));
        }
      });
      unawaited(
        Isolate.spawn(_serve, _messages.sendPort).then(
          (isolate) {
            _isolate = isolate;
          },
          onError: (Object error, StackTrace stack) {
            if (!_ready.isCompleted) _ready.completeError(error, stack);
          },
        ),
      );
    }
    final port = await _ready.future;
    final id = _nextId++;
    final result = Completer<Uint8List>();
    _waiting[id] = result;
    port.send([id, url]);
    return result.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _messages.close();
    for (final pending in _waiting.values) {
      pending.completeError(StateError('Artwork worker disposed'));
    }
    _waiting.clear();
  }
}

void _serve(SendPort responses) {
  final requests = ReceivePort();
  final client = http.Client();
  responses.send(requests.sendPort);
  requests.listen((message) async {
    final request = message as List;
    final id = request[0] as int;
    try {
      final response = await client
          .get(Uri.parse(request[1] as String))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw StateError('Artwork request failed: ${response.statusCode}');
      }
      responses.send([
        id,
        TransferableTypedData.fromList([response.bodyBytes]),
        null,
      ]);
    } catch (error) {
      responses.send([id, null, error.toString()]);
    }
  });
}
