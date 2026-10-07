import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aniwings/services/image_download_cache.dart';

void main() {
  test(
    'prefetched bytes are reused and simultaneous consumers share one download',
    () async {
      var requests = 0;
      final response = Completer<http.Response>();
      final cache = ImageDownloadCache(
        client: MockClient((_) {
          requests++;
          return response.future;
        }),
      );
      addTearDown(cache.dispose);
      final warmup = cache.prefetch(['https://example.com/art.jpg']);
      final visible = cache.load('https://example.com/art.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      response.complete(http.Response.bytes([1, 2, 3], 200));
      await warmup;
      expect(await visible, [1, 2, 3]);
      expect(await cache.load('https://example.com/art.jpg'), [1, 2, 3]);
      expect(requests, 1);
    },
  );

  test('failed warmups allow the visible image to retry', () async {
    var requests = 0;
    final cache = ImageDownloadCache(
      client: MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('', 503)
            : http.Response.bytes([1], 200);
      }),
    );
    addTearDown(cache.dispose);
    await cache.prefetch(['https://example.com/art.jpg']);
    expect(await cache.load('https://example.com/art.jpg'), [1]);
    expect(requests, 2);
  });

  test('visible artwork moves ahead of queued background downloads', () async {
    final requests = <String>[];
    final gates = <Completer<http.Response>>[];
    final cache = ImageDownloadCache(
      concurrentDownloads: 1,
      client: MockClient((request) {
        requests.add(request.url.path);
        final gate = Completer<http.Response>();
        gates.add(gate);
        return gate.future;
      }),
    );
    addTearDown(cache.dispose);
    final warming = cache.prefetch([
      'https://example.com/active',
      'https://example.com/background',
      'https://example.com/visible',
    ]);
    await Future<void>.delayed(Duration.zero);
    final visible = cache.load('https://example.com/visible', prioritize: true);
    gates[0].complete(http.Response.bytes([1], 200));
    await Future<void>.delayed(Duration.zero);
    expect(requests, ['/active', '/visible']);
    gates[1].complete(http.Response.bytes([2], 200));
    expect(await visible, [2]);
    await Future<void>.delayed(Duration.zero);
    gates[2].complete(http.Response.bytes([3], 200));
    await warming;
    expect(requests, ['/active', '/visible', '/background']);
  });

  test(
    'memory budget evicts older artwork and retains recently used bytes',
    () async {
      final requests = <String>[];
      final cache = ImageDownloadCache(
        maximumBytes: 4,
        client: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response.bytes([1, 2], 200);
        }),
      );
      addTearDown(cache.dispose);
      await cache.load('https://example.com/a');
      await cache.load('https://example.com/b');
      await cache.load('https://example.com/a');
      await cache.load('https://example.com/c');
      await cache.load('https://example.com/a');
      expect(requests, ['/a', '/b', '/c']);
      await cache.load('https://example.com/b');
      expect(requests, ['/a', '/b', '/c', '/b']);
    },
  );

  test('artwork downloads are limited to three concurrent requests', () async {
    var active = 0;
    var maximum = 0;
    final gates = <Completer<http.Response>>[];
    final cache = ImageDownloadCache(
      client: MockClient((_) async {
        active++;
        if (active > maximum) maximum = active;
        final gate = Completer<http.Response>();
        gates.add(gate);
        final response = await gate.future;
        active--;
        return response;
      }),
    );
    addTearDown(cache.dispose);
    final warmup = cache.prefetch(
      List.generate(7, (i) => 'https://example.com/$i'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(gates.length, 3);
    for (var i = 0; i < 7; i++) {
      gates[i].complete(http.Response.bytes([1], 200));
      await Future<void>.delayed(Duration.zero);
    }
    await warmup;
    expect(maximum, 3);
  });
}
