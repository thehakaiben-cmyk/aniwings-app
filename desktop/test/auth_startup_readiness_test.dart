import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aniwings/services/auth_service.dart';
import 'package:aniwings/services/storage_service.dart';

// Exercise the production path without the debug/test mock fallback.
class PendingFirebaseAuthService extends AuthService {
  PendingFirebaseAuthService(super.preferences);
  @override
  bool get useMock => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'production auth can mount while Firebase initialization is pending',
    () async {
      final previous = AuthService.firebaseInitialized;
      AuthService.firebaseInitialized = false;
      addTearDown(() => AuthService.firebaseInitialized = previous);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = PendingFirebaseAuthService(prefs);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      expect(service.getCurrentFirebaseUser(), isNull);
      expect(await service.authStateChanges().toList(), isEmpty);
      expect(container.read(authStateProvider), isNull);
    },
  );
}
