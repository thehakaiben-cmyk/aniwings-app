import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aniwings/core/theme/app_theme.dart';
import 'package:aniwings/features/auth/manual_login_screen.dart';
import 'package:aniwings/services/storage_service.dart';
import 'package:aniwings/widgets/web_safe_image.dart';
import 'package:aniwings/widgets/downloaded_network_image.dart';

void main() {
  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const RepaintBoundary(
            key: ValueKey('preview'),
            child: ManualLoginScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'keyboard navigates manual auth and reveals password at $size',
      (tester) async {
        await mount(tester, size);
        final intro = tester.getRect(find.byKey(const ValueKey('auth-intro')));
        final form = tester.getRect(
          find.byKey(const ValueKey('auth-form-panel')),
        );
        expect(intro.right, lessThan(form.left));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Manual auth email',
        );
        expect(tester.testTextInput.isVisible, isFalse);
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Manual auth password',
        );
        await key(tester, LogicalKeyboardKey.select);
        expect(tester.testTextInput.isVisible, isTrue);
        tester.testTextInput.enterText('secret123');
        await tester.pump();
        await key(tester, LogicalKeyboardKey.escape);
        expect(tester.testTextInput.isVisible, isFalse);
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Manual auth visibility',
        );
        await key(tester, LogicalKeyboardKey.select);
        expect(find.text('Hide password'), findsOneWidget);
        final password = tester.widget<TextField>(find.byType(TextField).at(1));
        expect(password.obscureText, isFalse);
        expect(password.controller?.text, 'secret123');
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Manual auth submit',
        );
        expect(
          tester.getRect(find.text('Sign in')).bottom,
          lessThan(size.height),
        );
        await key(tester, LogicalKeyboardKey.select);
        expect(find.text('Enter a valid email address.'), findsOneWidget);
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Manual auth reset',
        );
        await key(tester, LogicalKeyboardKey.arrowDown);
        await key(tester, LogicalKeyboardKey.select);
        expect(find.byType(TextFormField), findsNWidgets(4));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Manual auth username',
        );
        for (final id in [
          'email',
          'password',
          'confirmation',
          'visibility',
          'submit',
          'mode',
        ]) {
          await key(tester, LogicalKeyboardKey.arrowDown);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Manual auth $id',
          );
        }
        expect(
          tester.getRect(find.text('Already have an account? Sign in')).bottom,
          lessThan(size.height),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'image preloading and display share identical resized cache keys',
    () async {
      final warm = WebSafeImage.provider(
        'https://example.com/poster.jpg',
        cacheWidth: 300,
        cacheHeight: 440,
      );
      final visible = ResizeImage.resizeIfNeeded(
        300,
        440,
        const DownloadedNetworkImage('https://example.com/poster.jpg'),
      );
      expect(
        await warm.obtainKey(ImageConfiguration.empty),
        await visible.obtainKey(ImageConfiguration.empty),
      );
    },
  );
}
