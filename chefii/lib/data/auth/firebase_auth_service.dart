import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth, {this.googleServerClientId});

  final fa.FirebaseAuth _auth;

  /// OAuth web client id (Android needs it to mint ID tokens).
  final String? googleServerClientId;
  bool _googleReady = false;

  @override
  Stream<AppUser?> get userChanges => _auth.idTokenChanges().asyncMap(_map);

  @override
  AppUser? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : AppUser(uid: u.uid, email: u.email, displayName: u.displayName);
  }

  Future<AppUser?> _map(fa.User? u) async {
    if (u == null) return null;
    final token = await u.getIdTokenResult();
    return AppUser(
      uid: u.uid,
      email: u.email,
      displayName: u.displayName,
      isProfessional: token.claims?['professional'] == true,
    );
  }

  @override
  Set<AuthMethod> get availableMethods => {
        AuthMethod.google,
        AuthMethod.email,
        if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android))
          AuthMethod.apple,
      };

  Future<AppUser> _result(fa.UserCredential c) async => (await _map(c.user))!;

  AuthException _wrap(Object e) {
    if (e is fa.FirebaseAuthException) {
      final msg = switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'That email and password don\'t match.',
        'email-already-in-use' => 'An account already exists for that email. Try signing in.',
        'weak-password' => 'Please choose a longer password (at least 8 characters).',
        'invalid-email' => 'That email address doesn\'t look right.',
        'network-request-failed' => 'You appear to be offline. Please try again.',
        'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
        'requires-recent-login' => 'For your security, please sign in again to continue.',
        'web-context-canceled' || 'canceled' => 'Sign-in was cancelled.',
        _ => e.message ?? 'Sign-in failed.',
      };
      return AuthException(msg, cancelled: e.code.contains('cancel'));
    }
    if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) {
      return AuthException('Sign-in was cancelled.', cancelled: true);
    }
    return AuthException('Sign-in failed. Please try again.');
  }

  @override
  Future<AppUser> signInWithApple() async {
    try {
      final provider = fa.AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      return await _result(await _auth.signInWithProvider(provider));
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    try {
      if (kIsWeb) return await _result(await _auth.signInWithPopup(fa.GoogleAuthProvider()));
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize(serverClientId: googleServerClientId);
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw AuthException('Google did not return an identity token.');
      return await _result(await _auth.signInWithCredential(fa.GoogleAuthProvider.credential(idToken: idToken)));
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _wrap(e);
    }
  }

  @override
  Future<AppUser> signInWithEmail(String email, String password) async {
    try {
      return await _result(await _auth.signInWithEmailAndPassword(email: email.trim(), password: password));
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<AppUser> createAccountWithEmail(String email, String password, String displayName) async {
    try {
      final c = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      await c.user?.updateDisplayName(displayName.trim());
      await c.user?.sendEmailVerification();
      await c.user?.reload();
      return (await _map(_auth.currentUser))!;
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> reauthenticate({String? password}) async {
    final u = _auth.currentUser;
    if (u == null) throw AuthException('Please sign in again.');
    try {
      final providers = u.providerData.map((p) => p.providerId).toSet();
      if (providers.contains('password')) {
        if (password == null || u.email == null) throw AuthException('Enter your password to continue.');
        await u.reauthenticateWithCredential(fa.EmailAuthProvider.credential(email: u.email!, password: password));
      } else if (providers.contains('apple.com')) {
        await u.reauthenticateWithProvider(fa.AppleAuthProvider());
      } else if (providers.contains('google.com')) {
        if (kIsWeb) {
          await u.reauthenticateWithPopup(fa.GoogleAuthProvider());
        } else {
          final account = await GoogleSignIn.instance.authenticate();
          await u.reauthenticateWithCredential(fa.GoogleAuthProvider.credential(idToken: account.authentication.idToken));
        }
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw _wrap(e);
    }
  }

  @override
  Future<void> signOut() async {
    if (_googleReady) await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
    } catch (e) {
      throw _wrap(e);
    }
  }
}
