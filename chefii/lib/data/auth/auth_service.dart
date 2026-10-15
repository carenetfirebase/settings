import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  const AppUser({required this.uid, this.email, this.displayName, this.isDemo = false, this.isProfessional = false});

  final String uid;
  final String? email;
  final String? displayName;
  final bool isDemo;

  /// From a verified custom claim (`professional: true`), set server-side
  /// only after credential verification.
  final bool isProfessional;
}

class AuthException implements Exception {
  AuthException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

enum AuthMethod { apple, google, email, demo }

abstract class AuthService {
  Stream<AppUser?> get userChanges;
  AppUser? get currentUser;

  Set<AuthMethod> get availableMethods;

  Future<AppUser> signInWithApple();
  Future<AppUser> signInWithGoogle();
  Future<AppUser> signInWithEmail(String email, String password);
  Future<AppUser> createAccountWithEmail(String email, String password, String displayName);
  Future<void> sendPasswordReset(String email);

  /// Required before sensitive actions (deleting the account, exporting
  /// health data). Throws if the user cancels.
  Future<void> reauthenticate({String? password});
  Future<void> signOut();

  /// Deletes the auth account. Data deletion runs server-side
  /// (functions: deleteAccountData) before this is called.
  Future<void> deleteAccount();
}

/// Local-only account for demo mode. No credentials are collected.
class DemoAuthService implements AuthService {
  DemoAuthService(this._prefs) {
    final uid = _prefs.getString(_kUid);
    if (uid != null) _current = AppUser(uid: uid, displayName: _prefs.getString(_kName), email: _prefs.getString(_kEmail), isDemo: true);
  }

  final SharedPreferences _prefs;
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;

  static const _kUid = 'demo_uid', _kName = 'demo_name', _kEmail = 'demo_email';

  @override
  Stream<AppUser?> get userChanges async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _current;

  @override
  Set<AuthMethod> get availableMethods => {AuthMethod.demo, AuthMethod.email};

  Future<AppUser> _signIn(String name, String? email) async {
    final uid = _prefs.getString(_kUid) ?? 'demo-${DateTime.now().microsecondsSinceEpoch}';
    await _prefs.setString(_kUid, uid);
    await _prefs.setString(_kName, name);
    if (email != null) await _prefs.setString(_kEmail, email);
    _current = AppUser(uid: uid, displayName: name, email: email, isDemo: true);
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<AppUser> signInWithApple() => throw AuthException('Apple sign-in needs Firebase configured. Use the demo account.');

  @override
  Future<AppUser> signInWithGoogle() => throw AuthException('Google sign-in needs Firebase configured. Use the demo account.');

  @override
  Future<AppUser> signInWithEmail(String email, String password) => _signIn(_prefs.getString(_kName) ?? email.split('@').first, email);

  @override
  Future<AppUser> createAccountWithEmail(String email, String password, String displayName) => _signIn(displayName, email);

  Future<AppUser> signInDemo(String displayName) => _signIn(displayName, null);

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> reauthenticate({String? password}) async {}

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    await _prefs.remove(_kUid);
    await _prefs.remove(_kName);
    await _prefs.remove(_kEmail);
    await signOut();
  }
}
