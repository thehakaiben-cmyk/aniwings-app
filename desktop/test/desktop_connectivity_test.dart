import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aniwings/services/connectivity_service.dart';

void main() {
  test(
    'a blocked probe does not report offline when another server responds',
    () async {
      final client = MockClient((request) async {
        if (request.url.host == 'www.cloudflare.com') {
          throw Exception('blocked');
        }
        return http.Response('', 403);
      });
      expect(await ConnectivityService(client).isOnline(), isTrue);
      client.close();
    },
  );
  test('a stalled first probe does not delay a working endpoint', () async {
    final stalled = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.host == 'www.cloudflare.com') return stalled.future;
      return http.Response('', 200);
    });
    expect(
      await ConnectivityService(
        client,
      ).isOnline().timeout(const Duration(milliseconds: 100)),
      isTrue,
    );
    stalled.complete(http.Response('', 200));
    client.close();
  });
  test('offline requires every independent probe to fail', () async {
    final client = MockClient((_) async => throw Exception('network down'));
    expect(await ConnectivityService(client).isOnline(), isFalse);
    client.close();
  });
}
