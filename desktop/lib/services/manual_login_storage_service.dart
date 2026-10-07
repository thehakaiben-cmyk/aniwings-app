import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Stores account metadata only. Firebase owns credentials and authentication.
class ManualLoginStorageService {
  static const enabled = bool.fromEnvironment(
    'CLOUDFLARE_MANUAL_LOGIN_STORAGE',
    defaultValue: true,
  );
  static const defaultApiUrl = String.fromEnvironment(
    'CLOUDFLARE_API_URL',
    defaultValue: 'https://aniwings-mobile-api.wingsofficial750.workers.dev',
  );
  final SharedPreferences prefs;
  final http.Client? client;
  final String apiUrl;

  ManualLoginStorageService(
    this.prefs, {
    this.client,
    this.apiUrl = defaultApiUrl,
  });

  bool hasManualLogin(String uid) =>
      prefs.getBool('manual_login_user_$uid') == true;
  bool isPending(String uid) =>
      prefs.getBool('manual_login_pending_$uid') == true;

  Future<bool> sync(User user, Future<String?> Function() getIdToken) async {
    if (!enabled) return true;
    await prefs.setBool('manual_login_user_${user.id}', true);
    await prefs.setBool('manual_login_pending_${user.id}', true);
    final connection = client ?? http.Client();
    try {
      final token = await getIdToken().timeout(const Duration(seconds: 8));
      if (token == null || token.isEmpty) return false;
      final response = await connection
          .put(
            Uri.parse('$apiUrl/api/v2/desktop/manual-users/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'username': user.username}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      if (data is! Map || data['success'] != true || data['uid'] != user.id) {
        return false;
      }
      await prefs.remove('manual_login_pending_${user.id}');
      return true;
    } catch (_) {
      return false;
    } finally {
      if (client == null) connection.close();
    }
  }
}
