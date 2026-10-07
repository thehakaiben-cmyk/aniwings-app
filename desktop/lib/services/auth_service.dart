import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cryptography/cryptography.dart';
import '../models/user.dart';
import 'storage_service.dart';
import 'manual_login_storage_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AuthService(prefs);
});

final authStateProvider = StateNotifierProvider<AuthNotifier, User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  final storageService = ref.watch(storageServiceProvider);
  return AuthNotifier(authService, storageService);
});

class AuthNotifier extends StateNotifier<User?> {
  final AuthService _authService;
  final StorageService _storageService;
  StreamSubscription? _subscription;
  bool _registering = false;

  AuthNotifier(this._authService, this._storageService) : super(null) {
    final savedUser = _authService.getCurrentUser();
    if (_authService.useMock || !AuthService.firebaseInitialized) {
      state = savedUser;
    } else {
      final currentUser = _authService.getCurrentFirebaseUser() ?? savedUser;
      state = currentUser;
      if (currentUser != null) {
        unawaited(_refreshWatchHistory(currentUser));
      }
      _subscription = _authService.authStateChanges().listen((user) {
        // Firebase emits a user before registration has saved the display name.
        // Publish the completed profile from register instead.
        if (_registering) return;
        if (user == null) {
          final localUser = _authService.getCurrentUser();
          if (localUser != null) {
            state = localUser;
            return;
          }
          state = null;
        } else {
          state = user;
          unawaited(_authService.retryManualLoginStorage(user));
          unawaited(_refreshWatchHistory(user));
        }
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<String?> login(String email, String password) async {
    final result = await _authService.login(email, password);
    if (result.user != null) {
      state = result.user;
      unawaited(
        _refreshWatchHistory(result.user!).catchError((Object error) {
          debugPrint('Watch history sync postponed: $error');
        }),
      );
      return null; // success
    }
    return result.errorMessage;
  }

  Future<String?> loginWithGoogle([
    String email = '',
    String displayName = '',
  ]) async {
    final result = await _authService.loginWithGoogle(email, displayName);
    if (result.user != null) {
      state = result.user;
      unawaited(
        _refreshWatchHistory(result.user!).catchError((Object error) {
          debugPrint('Watch history sync postponed: $error');
        }),
      );
      return null; // success
    }
    return result.errorMessage;
  }

  Future<String?> register(
    String username,
    String email,
    String password,
  ) async {
    _registering = true;
    try {
      final result = await _authService.register(username, email, password);
      if (result.user != null) {
        state = result.user;
        unawaited(
          _refreshWatchHistory(result.user!).catchError((Object error) {
            debugPrint('Watch history sync postponed: $error');
          }),
        );
        return null;
      }
      return result.errorMessage;
    } finally {
      _registering = false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    state = null;
  }

  Future<void> updateUser(User updatedUser) async {
    await _authService.updateUser(updatedUser);
    state = updatedUser;
  }

  Future<String?> resetPassword(String email) async {
    return await _authService.resetPassword(email);
  }

  Future<void> _refreshWatchHistory(User user) async {
    await _storageService.syncWatchHistoryForUser(user.id);
    if (!mounted || state?.id != user.id) return;
    state = state!.copyWith();
  }
}

class AuthResult {
  final User? user;
  final String? errorMessage;

  AuthResult({this.user, this.errorMessage});
}

class AuthService {
  static bool firebaseInitialized = false;
  final SharedPreferences _prefs;

  AuthService(this._prefs);

  static const String _usersDbKey = 'auth_users_database';
  static const String _currentUserKey = 'auth_current_user_session';

  // A generic, non-enumerating error returned for any authentication failure
  // (wrong password, unknown email, invalid credentials). Returning a single
  // message prevents attackers from probing which emails are registered.
  static const String _genericAuthError = 'Invalid email or password.';

  // Argon2id parameters for the local (mock/offline) credential database.
  // Argon2id is a memory-hard password hashing function (OWASP recommended).
  static const int _argonMemory = 19456; // 19 MiB
  static const int _argonIterations = 2;
  static const int _argonParallelism = 1;
  static const int _argonHashLength = 32;
  static const String _passwordHashPrefix = 'argon2id';

  // Development-only seed accounts. The default password is a constant known
  // ONLY in source code and is never persisted. On the first successful login
  // the chosen password is Argon2id-hashed and stored in place.
  static const String _seedDefaultPassword = 'password123';
  static const Set<String> _seedEmails = {
    'senthil.wings@gmail.com',
    'aniwings.dev@gmail.com',
  };

  // Toggle mock mode automatically in tests or when Firebase is not initialized.
  // IMPORTANT: mock mode (which stores user data locally on-device) is NEVER
  // enabled in a release build, so it can never be reached in production.
  bool get useMock {
    if (kReleaseMode) return false;
    if (!firebaseInitialized) return true;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return true;
    }
    return _prefs.getBool('use_mock_auth') == true;
  }

  // Seeding default mock accounts
  void _seedMockAccounts(Map<String, Map<String, dynamic>> db) {
    final defaultMockAccounts = [
      {
        'name': 'Senthil Kumar',
        'email': 'senthil.wings@gmail.com',
        'avatar': 'assets/images/avatars/naruto_naruto.png',
      },
      {
        'name': 'AniWings TV Dev',
        'email': 'aniwings.dev@gmail.com',
        'avatar': 'assets/images/avatars/jujutsukaisen_gojo.png',
      },
    ];

    bool changed = false;
    for (var acc in defaultMockAccounts) {
      final email = acc['email']!.toLowerCase();
      if (!db.containsKey(email)) {
        // Create the account fresh. No password is persisted here — the seed
        // default is known only in code and hashed on first successful login.
        final user = User(
          id: 'mock_${acc['name']!.replaceAll(' ', '_').toLowerCase()}',
          email: email,
          username: acc['name']!,
          createdAt: DateTime.now(),
          totalHoursWatched: 12,
          favoriteGenre: 'Action',
          avatarUrl: acc['avatar']!,
          authProvider: 'email',
        );
        db[email] = {'profile': user.toJson()};
        changed = true;
      } else {
        // Migrate existing account: fix avatar if it still uses an external URL
        final existing = db[email]!;
        final profile = existing['profile'];
        if (profile is Map<String, dynamic>) {
          final currentAvatar = profile['avatarUrl'] as String? ?? '';
          if (currentAvatar.contains('dicebear.com') ||
              currentAvatar.contains('api.') ||
              (currentAvatar.startsWith('http') &&
                  !currentAvatar.contains('ggpht') &&
                  !currentAvatar.contains('googleusercontent'))) {
            // Replace with local asset avatar, preserving any stored credential
            profile['avatarUrl'] = acc['avatar']!;
            db[email] = {
              if (existing['passwordHash'] is String)
                'passwordHash': existing['passwordHash'],
              if (existing['password'] is String)
                'password': existing['password'],
              'profile': profile,
            };
            changed = true;
          }
        }
      }
    }
    if (changed) {
      _saveUsersDb(db);
    }
  }

  // Helper to load registered users map (email -> JSON string representing user + password)
  Map<String, Map<String, dynamic>> _getUsersDb() {
    final raw = _prefs.getString(_usersDbKey);
    Map<String, Map<String, dynamic>> db = {};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        db = decoded.map(
          (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
        );
      } catch (_) {}
    }
    _seedMockAccounts(db);
    return db;
  }

  Future<void> _saveUsersDb(Map<String, Map<String, dynamic>> db) async {
    await _prefs.setString(_usersDbKey, jsonEncode(db));
  }

  /// Generates a cryptographically-secure random salt.
  List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Hashes a password with Argon2id. Never store plaintext credentials.
  Future<String> _hashPassword(String password) async {
    final algorithm = Argon2id(
      memory: _argonMemory,
      iterations: _argonIterations,
      parallelism: _argonParallelism,
      hashLength: _argonHashLength,
    );
    final salt = _randomBytes(16);
    final secretKey = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final hash = await secretKey.extractBytes();
    return '$_passwordHashPrefix\$${base64Encode(salt)}\$${base64Encode(hash)}';
  }

  /// Verifies a password against a stored Argon2id hash (format
  /// `argon2id$<saltB64>$<hashB64>`). Returns false on any parse/verify error.
  Future<bool> _verifyPassword(String password, String stored) async {
    final parts = stored.split('\$');
    if (parts.length != 3 || parts[0] != _passwordHashPrefix) return false;
    List<int> salt;
    List<int> expected;
    try {
      salt = base64Decode(parts[1]);
      expected = base64Decode(parts[2]);
    } catch (_) {
      return false;
    }
    final algorithm = Argon2id(
      memory: _argonMemory,
      iterations: _argonIterations,
      parallelism: _argonParallelism,
      hashLength: expected.length,
    );
    try {
      final secretKey = await algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      final actual = await secretKey.extractBytes();
      return _constantTimeEqualsBytes(actual, expected);
    } catch (_) {
      return false;
    }
  }

  /// Constant-time comparison for byte lists.
  bool _constantTimeEqualsBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Constant-time string comparison to avoid timing side channels.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Maps Firebase User profile to our custom application User model
  User? _mapFirebaseUser(fb_auth.User? firebaseUser) {
    if (firebaseUser == null) return null;
    final uid = firebaseUser.uid;
    final hours = _prefs.getInt('user_hours_$uid') ?? 0;
    final genre = _prefs.getString('user_genre_$uid') ?? 'Action';
    final savedAvatar = _prefs.getString('user_avatar_$uid');
    final savedName = _prefs.getString('user_name_$uid');

    return User(
      id: uid,
      email: firebaseUser.email ?? '',
      username: savedName ?? firebaseUser.displayName ?? 'User',
      avatarUrl: (savedAvatar != null && savedAvatar.isNotEmpty)
          ? savedAvatar
          : (firebaseUser.photoURL ??
                'assets/images/avatars/jujutsukaisen_gojo.png'),
      createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
      totalHoursWatched: hours,
      favoriteGenre: genre,
      authProvider:
          firebaseUser.providerData.any((p) => p.providerId == 'google.com')
          ? 'google'
          : 'email',
    );
  }

  /// Stream of user auth state changes (Firebase Auth)
  Stream<User?> authStateChanges() {
    if (useMock || !firebaseInitialized) {
      return const Stream.empty();
    }
    return fb_auth.FirebaseAuth.instance.authStateChanges().map(
      (fbUser) => _mapFirebaseUser(fbUser),
    );
  }

  /// Get current Firebase User if logged in
  User? getCurrentFirebaseUser() {
    if (useMock || !firebaseInitialized) return null;
    return _mapFirebaseUser(fb_auth.FirebaseAuth.instance.currentUser);
  }

  User? getCurrentUser() {
    final raw = _prefs.getString(_currentUserKey);
    if (raw == null) return null;
    try {
      final user = User.fromJson(jsonDecode(raw));
      // Migrate any external avatar URL to a local asset
      final avatar = user.avatarUrl ?? '';
      if (avatar.contains('dicebear.com') ||
          avatar.contains('api.dicebear') ||
          (avatar.startsWith('http') && avatar.contains('dicebear'))) {
        final migrated = user.copyWith(
          avatarUrl: 'assets/images/avatars/jujutsukaisen_gojo.png',
        );
        _prefs.setString(_currentUserKey, jsonEncode(migrated.toJson()));
        return migrated;
      }
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<AuthResult> _loginMock(String email, String password) async {
    final db = _getUsersDb();
    final normalizedEmail = email.trim().toLowerCase();

    final userData = db[normalizedEmail];
    if (userData == null) {
      // Generic message: do not reveal whether the account exists.
      return AuthResult(errorMessage: _genericAuthError);
    }

    final storedHash = userData['passwordHash'] as String?;
    var verified = false;

    if (storedHash != null && storedHash.isNotEmpty) {
      verified = await _verifyPassword(password, storedHash);
    } else if (userData['password'] is String) {
      // Legacy plaintext credential from older builds: verify in constant time
      // and migrate to a strong hash on success (never persisted as plaintext).
      verified = _constantTimeEquals(userData['password'] as String, password);
    } else if (_seedEmails.contains(normalizedEmail)) {
      // Seeded development account: default password is a code-only constant.
      verified = _constantTimeEquals(_seedDefaultPassword, password);
    }

    if (!verified) {
      return AuthResult(errorMessage: _genericAuthError);
    }

    // Migrate a legacy/seed credential to a strong Argon2id hash.
    if (storedHash == null || storedHash.isEmpty) {
      userData['passwordHash'] = await _hashPassword(password);
      userData.remove('password');
      await _saveUsersDb(db);
    }

    final user = User.fromJson(userData['profile']);
    await _prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
    return AuthResult(user: user);
  }

  Future<AuthResult> login(String email, String password) async {
    if (useMock) {
      return _loginMock(email, password);
    }
    // Firebase path.
    try {
      final credential = await fb_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email.trim(), password: password);
      final user = _mapFirebaseUser(credential.user);
      if (user != null) {
        await _prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
        unawaited(
          _syncManualLoginStorage(user).catchError((Object error) {
            debugPrint('Profile sync postponed: $error');
          }),
        );
      }
      return AuthResult(user: user);
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('Firebase login error code: ${e.code}');
      return AuthResult(errorMessage: _formatFirebaseAuthException(e));
    } catch (e) {
      debugPrint('Firebase login failed: $e');
      return AuthResult(errorMessage: 'Sign in failed. Please try again.');
    }
  }

  String _formatFirebaseAuthException(
    fb_auth.FirebaseAuthException e, {
    bool isRegister = false,
  }) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return _genericAuthError;
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many unsuccessful attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection and try again.';
      case 'operation-not-allowed':
        return 'Sign-in method is not enabled in Firebase Console.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      default:
        if (isRegister) {
          return e.message != null && e.message!.isNotEmpty
              ? e.message!
              : 'Registration failed. Please check your details and try again.';
        }
        return e.message != null && e.message!.isNotEmpty
            ? e.message!
            : _genericAuthError;
    }
  }

  Future<AuthResult> loginWithGoogle([
    String email = '',
    String displayName = '',
  ]) async {
    if (useMock) {
      final db = _getUsersDb();
      final normalizedEmail = email.trim().toLowerCase();

      User user;
      if (db.containsKey(normalizedEmail)) {
        final userData = db[normalizedEmail]!;
        final existingProfile = User.fromJson(userData['profile']);
        user = User(
          id: existingProfile.id,
          email: existingProfile.email,
          username: existingProfile.username,
          avatarUrl:
              existingProfile.avatarUrl ??
              'assets/images/avatars/jujutsukaisen_gojo.png',
          createdAt: existingProfile.createdAt,
          totalHoursWatched: existingProfile.totalHoursWatched,
          favoriteGenre: existingProfile.favoriteGenre,
          authProvider: 'google',
        );
        db[normalizedEmail] = {
          if (userData['passwordHash'] is String)
            'passwordHash': userData['passwordHash'],
          'profile': user.toJson(),
        };
      } else {
        user = User(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          email: normalizedEmail,
          username: displayName,
          createdAt: DateTime.now(),
          totalHoursWatched: 0,
          favoriteGenre: 'Action',
          avatarUrl: 'assets/images/avatars/jujutsukaisen_gojo.png',
          authProvider: 'google',
        );
        db[normalizedEmail] = {'profile': user.toJson()};
      }

      await _saveUsersDb(db);
      await _prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
      return AuthResult(user: user);
    } else {
      try {
        final userCredential = await fb_auth.FirebaseAuth.instance
            .signInWithProvider(
              fb_auth.GoogleAuthProvider()..addScope('email'),
            );
        final user = _mapFirebaseUser(userCredential.user);
        return AuthResult(user: user);
      } on fb_auth.FirebaseAuthException catch (e) {
        debugPrint('Firebase Google sign-in error code: ${e.code}');
        return AuthResult(errorMessage: _formatFirebaseAuthException(e));
      } catch (e) {
        debugPrint('Google sign-in failed: $e');
        return AuthResult(
          errorMessage: 'Google Sign-in failed. Please try again.',
        );
      }
    }
  }

  Future<AuthResult> _registerMock(
    String username,
    String email,
    String password,
  ) async {
    final db = _getUsersDb();
    final normalizedEmail = email.trim().toLowerCase();

    if (db.containsKey(normalizedEmail)) {
      // Generic message: do not reveal that the email is already registered.
      return AuthResult(errorMessage: _genericAuthError);
    }

    if (username.trim().isEmpty) {
      return AuthResult(errorMessage: 'Username cannot be empty.');
    }

    if (password.length < 8) {
      return AuthResult(
        errorMessage: 'Password must be at least 8 characters.',
      );
    }

    final newUser = User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      email: normalizedEmail,
      username: username.trim(),
      createdAt: DateTime.now(),
      totalHoursWatched: 0,
      favoriteGenre: 'Action',
      avatarUrl:
          'https://api.dicebear.com/7.x/adventurer/png?seed=${username.trim()}',
    );

    db[normalizedEmail] = {
      'passwordHash': await _hashPassword(password),
      'profile': newUser.toJson(),
    };

    await _saveUsersDb(db);
    await _prefs.setString(_currentUserKey, jsonEncode(newUser.toJson()));

    return AuthResult(user: newUser);
  }

  Future<AuthResult> register(
    String username,
    String email,
    String password,
  ) async {
    if (username.trim().isEmpty || username.trim().length > 30) {
      return AuthResult(
        errorMessage: 'Enter a username between 1 and 30 characters.',
      );
    }
    if (password.length < 8) {
      return AuthResult(
        errorMessage: 'Password must be at least 8 characters.',
      );
    }
    if (useMock) {
      return _registerMock(username, email, password);
    }
    try {
      final credential = await fb_auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      if (credential.user != null) {
        final uid = credential.user!.uid;
        await _prefs.setString('user_name_$uid', username.trim());
        // The account already exists. Optional profile/verification requests
        // must not make a successful creation look like a failed registration.
        unawaited(
          credential.user!
              .updateDisplayName(username.trim())
              .timeout(const Duration(seconds: 10))
              .catchError((Object error) {
                debugPrint('Display name sync postponed: $error');
              }),
        );
        unawaited(
          credential.user!
              .sendEmailVerification()
              .timeout(const Duration(seconds: 10))
              .catchError((Object error) {
                debugPrint('Email verification could not be sent: $error');
              }),
        );
      }
      final updatedUser = fb_auth.FirebaseAuth.instance.currentUser;
      final user = _mapFirebaseUser(updatedUser);
      if (user != null) {
        await _prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
        unawaited(
          _syncManualLoginStorage(user).catchError((Object error) {
            debugPrint('Profile sync postponed: $error');
          }),
        );
      }
      return AuthResult(user: user);
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('Firebase registration error code: ${e.code}');
      return AuthResult(
        errorMessage: _formatFirebaseAuthException(e, isRegister: true),
      );
    } catch (e) {
      debugPrint('Firebase registration failed: $e');
      return AuthResult(errorMessage: 'Registration failed. Please try again.');
    }
  }

  Future<void> logout() async {
    await _prefs.remove(_currentUserKey);
    if (!useMock) {
      try {
        await fb_auth.FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
  }

  Future<void> _syncManualLoginStorage(User user) async {
    if (useMock) return;
    final firebaseUser = fb_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || firebaseUser.uid != user.id) return;
    await ManualLoginStorageService(
      _prefs,
    ).sync(user, () => firebaseUser.getIdToken());
  }

  Future<void> retryManualLoginStorage(User user) async {
    if (useMock) return;
    final storage = ManualLoginStorageService(_prefs);
    if (storage.hasManualLogin(user.id)) {
      await _syncManualLoginStorage(user);
    }
  }

  Future<void> updateUser(User user) async {
    if (user.avatarUrl != null) {
      await _prefs.setString('user_avatar_${user.id}', user.avatarUrl!);
    }
    await _prefs.setString('user_name_${user.id}', user.username);

    if (useMock) {
      final db = _getUsersDb();
      final normalizedEmail = user.email.trim().toLowerCase();

      if (db.containsKey(normalizedEmail)) {
        final userData = db[normalizedEmail]!;
        db[normalizedEmail] = {
          if (userData['passwordHash'] is String)
            'passwordHash': userData['passwordHash'],
          'profile': user.toJson(),
        };
        await _saveUsersDb(db);
      }

      await _prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
    } else {
      final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        if (user.username != fbUser.displayName) {
          await fbUser.updateDisplayName(user.username);
        }
        // Only update Firebase photoURL with real http/https URLs
        // (local asset paths like 'assets/...' are not valid for Firebase Auth)
        final avatar = user.avatarUrl ?? '';
        if (avatar.isNotEmpty &&
            (avatar.startsWith('http://') || avatar.startsWith('https://')) &&
            avatar != fbUser.photoURL) {
          await fbUser.updatePhotoURL(avatar);
        }
        await _prefs.setInt('user_hours_${user.id}', user.totalHoursWatched);
        await _prefs.setString('user_genre_${user.id}', user.favoriteGenre);
        // Also cache full user profile so getCurrentUser() works on restart
        await _prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
        if (ManualLoginStorageService(_prefs).hasManualLogin(user.id)) {
          await _syncManualLoginStorage(user);
        }
      }
    }
  }

  Future<String?> resetPassword(String email) async {
    if (useMock) {
      return null;
    }
    try {
      await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.trim(),
      );
    } catch (e) {
      debugPrint('Firebase reset password failed: $e');
    }
    // Always return success to avoid account enumeration, mirroring the
    // behavior of the Firebase client which returns the same response for
    // registered and unregistered email addresses.
    return null;
  }
}
