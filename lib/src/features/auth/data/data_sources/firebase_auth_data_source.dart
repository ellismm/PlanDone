import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/models/auth_failure.dart';
import '../../domain/models/auth_user.dart';
import '../../domain/policies/auth_input_policy.dart';
import 'auth_data_source.dart';
import 'firebase_auth_error_mapper.dart';

class FirebaseAuthDataSource implements AuthDataSource {
  FirebaseAuthDataSource({
    required FirebaseAuth firebaseAuth,
    required GoogleSignIn googleSignIn,
  })  : _firebaseAuth = firebaseAuth,
        _googleSignIn = googleSignIn;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  AuthCredential? _pendingGoogleCredential;
  String? _pendingGoogleEmail;

  @override
  Stream<AuthSession?> authStateChanges() {
    return _firebaseAuth.authStateChanges().map(_toSession);
  }

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = AuthInputPolicy.normalizeEmail(email);
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      await _maybeLinkPendingGoogleCredential(
        user: credential.user,
        normalizedEmail: normalizedEmail,
      );
      return _requireSession(credential.user);
    } on FirebaseAuthException catch (error) {
      final methods = await _signInMethodsForEmail(normalizedEmail);
      throw mapFirebaseAuthException(
        error,
        normalizedEmail: normalizedEmail,
        signInMethods: methods,
      );
    } catch (_) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Authentication failed. Please try again.',
      );
    }
  }

  @override
  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalizedEmail = AuthInputPolicy.normalizeEmail(email);
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      if (credential.user != null) {
        await credential.user!.updateDisplayName(displayName.trim());
        await credential.user!.reload();
      }
      return _requireSession(_firebaseAuth.currentUser ?? credential.user);
    } on FirebaseAuthException catch (error) {
      final methods = await _signInMethodsForEmail(normalizedEmail);
      throw mapFirebaseAuthException(
        error,
        normalizedEmail: normalizedEmail,
        signInMethods: methods,
      );
    } catch (_) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Unable to create your account right now.',
      );
    }
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final credential =
            await _firebaseAuth.signInWithPopup(GoogleAuthProvider());
        return _requireSession(credential.user);
      }

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthFailure(
          code: AuthFailureCode.googleCanceled,
          message: 'Google sign-in was canceled.',
        );
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await _firebaseAuth.signInWithCredential(credential);
      return _requireSession(userCredential.user);
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (error) {
      final email = error.email;
      final methods = email == null
          ? const <String>[]
          : await _signInMethodsForEmail(email);
      if (error.code == 'account-exists-with-different-credential' &&
          error.credential != null) {
        _pendingGoogleCredential = error.credential;
        _pendingGoogleEmail = AuthInputPolicy.normalizeEmail(email ?? '');
      }
      throw mapFirebaseAuthException(
        error,
        normalizedEmail:
            email == null ? null : AuthInputPolicy.normalizeEmail(email),
        signInMethods: methods,
      );
    } catch (_) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Google sign-in failed. Please try again.',
      );
    }
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
  }) async {
    final normalizedEmail = AuthInputPolicy.normalizeEmail(email);
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: normalizedEmail);
    } on FirebaseAuthException catch (error) {
      final methods = await _signInMethodsForEmail(normalizedEmail);
      throw mapFirebaseAuthException(
        error,
        normalizedEmail: normalizedEmail,
        signInMethods: methods,
      );
    } catch (_) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Unable to send a password reset email right now.',
      );
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
      _pendingGoogleCredential = null;
      _pendingGoogleEmail = null;
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (error) {
      final normalizedEmail = user.email == null
          ? null
          : AuthInputPolicy.normalizeEmail(user.email!);
      final methods = normalizedEmail == null
          ? const <String>[]
          : await _signInMethodsForEmail(normalizedEmail);
      throw mapFirebaseAuthException(
        error,
        normalizedEmail: normalizedEmail,
        signInMethods: methods,
      );
    } catch (_) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Unable to delete your account right now.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
    _pendingGoogleCredential = null;
    _pendingGoogleEmail = null;
    await _firebaseAuth.signOut();
  }

  Future<void> _maybeLinkPendingGoogleCredential({
    required User? user,
    required String normalizedEmail,
  }) async {
    if (user == null ||
        _pendingGoogleCredential == null ||
        _pendingGoogleEmail != normalizedEmail) {
      return;
    }
    try {
      await user.linkWithCredential(_pendingGoogleCredential!);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'provider-already-linked' &&
          error.code != 'credential-already-in-use') {
        rethrow;
      }
    } finally {
      _pendingGoogleCredential = null;
      _pendingGoogleEmail = null;
      await user.reload();
    }
  }

  Future<List<String>> _signInMethodsForEmail(String email) async {
    if (email.isEmpty) return const <String>[];
    try {
      // Firebase Auth still requires this lookup for provider-linking recovery.
      // ignore: deprecated_member_use
      return await _firebaseAuth.fetchSignInMethodsForEmail(email);
    } catch (_) {
      return const <String>[];
    }
  }

  AuthSession _requireSession(User? user) {
    final session = _toSession(user ?? _firebaseAuth.currentUser);
    if (session == null) {
      throw const AuthFailure(
        code: AuthFailureCode.unknown,
        message: 'Authentication returned no active user session.',
      );
    }
    return session;
  }

  AuthSession? _toSession(User? user) {
    if (user == null) return null;
    return AuthSession(
      user: AuthUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoURL,
      ),
    );
  }
}
