import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aniwings/models/user.dart';
import 'package:aniwings/services/manual_login_storage_service.dart';

void main() {
  final user = User(
    id: 'alice',
    username: 'Anime Fan',
    email: 'fan@example.com',
    createdAt: DateTime(2026),
    totalHoursWatched: 0,
    favoriteGenre: 'Action',
  );
  test(
    'only metadata is sent with an ID token and success clears pending storage',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = ManualLoginStorageService(
        prefs,
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/v2/desktop/manual-users/me');
          expect(request.headers['Authorization'], 'Bearer firebase-id-token');
          expect(jsonDecode(request.body), {'username': 'Anime Fan'});
          return http.Response('{"success":true,"uid":"alice"}', 200);
        }),
      );
      expect(await storage.sync(user, () async => 'firebase-id-token'), isTrue);
      expect(storage.hasManualLogin('alice'), isTrue);
      expect(storage.isPending('alice'), isFalse);
      expect(
        prefs.getKeys().any(
          (key) => key.contains('token') || key.contains('password'),
        ),
        isFalse,
      );
    },
  );
  test(
    'an outage survives service recreation and the next sync recovers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final broken = ManualLoginStorageService(
        prefs,
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      expect(await broken.sync(user, () async => 'token'), isFalse);
      final restored = ManualLoginStorageService(
        prefs,
        client: MockClient(
          (_) async => http.Response('{"success":true,"uid":"alice"}', 200),
        ),
      );
      expect(restored.isPending('alice'), isTrue);
      expect(await restored.sync(user, () async => 'token'), isTrue);
      expect(restored.isPending('alice'), isFalse);
    },
  );
  test(
    'a missing token or mismatched response cannot mark metadata saved',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var sent = false;
      final storage = ManualLoginStorageService(
        prefs,
        client: MockClient((_) async {
          sent = true;
          return http.Response('{"success":true,"uid":"bob"}', 200);
        }),
      );
      expect(await storage.sync(user, () async => null), isFalse);
      expect(sent, isFalse);
      expect(await storage.sync(user, () async => 'token'), isFalse);
      expect(storage.isPending('alice'), isTrue);
    },
  );
}
