import 'dart:async';
import 'package:aniwings/core/theme/app_theme.dart';
import 'package:aniwings/features/auth/login_screen.dart';
import 'package:aniwings/features/auth/signup_screen.dart';
import 'package:aniwings/models/user.dart';
import 'package:aniwings/services/auth_service.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthService {
  _Auth(super.prefs);
  final user = User(
    id: 'created',
    email: 'test@example.com',
    username: 'Tester',
    createdAt: DateTime(2026),
    totalHoursWatched: 0,
    favoriteGenre: 'Action',
  );
  @override
  Future<AuthResult> register(
    String username,
    String email,
    String password,
  ) async => AuthResult(user: user);
  @override
  Future<AuthResult> login(String email, String password) async =>
      AuthResult(user: user);
}

class _Storage extends StorageService {
  _Storage(super.prefs);
  final sync = Completer<void>();
  @override
  Future<void> syncWatchHistoryForUser(String id) => sync.future;
}

void main() {
  for (final register in [true, false]) {
    testWidgets(
      '${register ? 'registration' : 'login'} completes and shows success while history sync is pending',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final storage = _Storage(prefs);
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            authServiceProvider.overrideWithValue(_Auth(prefs)),
            storageServiceProvider.overrideWithValue(storage),
          ],
        );
        addTearDown(container.dispose);
        final notifier = ValueNotifier<int>(0);
        final subscription = container.listen(
          authStateProvider,
          (_, _) => notifier.value++,
        );
        addTearDown(subscription.close);
        addTearDown(notifier.dispose);
        final router = GoRouter(
          initialLocation: '/login',
          refreshListenable: notifier,
          redirect: (_, state) =>
              container.read(authStateProvider) != null &&
                  state.matchedLocation != '/home'
              ? '/home'
              : null,
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('Signed-in home')),
            ),
            GoRoute(
              path: '/login',
              pageBuilder: (_, state) =>
                  MaterialPage(key: state.pageKey, child: const LoginScreen()),
            ),
            GoRoute(
              path: '/signup',
              pageBuilder: (_, state) =>
                  MaterialPage(key: state.pageKey, child: const SignUpScreen()),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: AppTheme.darkTheme,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (register) {
          await tester.ensureVisible(find.text('Create Account').last);
          await tester.tap(find.text('Create Account').last);
          await tester.pumpAndSettle();
          // The Sign In link must replace registration instead of stacking a duplicate login page.
          await tester.ensureVisible(find.text('Sign In').last);
          await tester.tap(find.text('Sign In').last);
          await tester.pumpAndSettle();
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Create Account').last);
          await tester.tap(find.text('Create Account').last);
          await tester.pumpAndSettle();
        }
        final fields = find.byType(TextFormField);
        final values = register
            ? ['Tester', 'test@example.com', 'password123', 'password123']
            : ['test@example.com', 'password123'];
        for (var index = 0; index < values.length; index++) {
          await tester.enterText(fields.at(index), values[index]);
        }
        await tester.ensureVisible(find.byType(ElevatedButton).last);
        await tester.tap(find.byType(ElevatedButton).last);
        await tester.pumpAndSettle();
        expect(find.text('Signed-in home'), findsOneWidget);
        expect(
          find.text(
            register
                ? 'Account created successfully. You are signed in.'
                : 'Signed in successfully.',
          ),
          findsOneWidget,
        );
        expect(container.read(authStateProvider)?.id, 'created');
        expect(storage.sync.isCompleted, isFalse);
        expect(tester.takeException(), isNull);
        storage.sync.complete();
        await tester.pump();
      },
    );
  }
}
