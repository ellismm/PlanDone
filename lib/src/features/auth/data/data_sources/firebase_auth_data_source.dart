import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/models/auth_user.dart';
import 'auth_data_source.dart';

class FirebaseAuthDataSource implements AuthDataSource {
  FirebaseAuthDataSource({
    required FirebaseAuth firebaseAuth,
    required GoogleSignIn googleSignIn,
  })  : _firebaseAuth = firebaseAuth,
        _googleSignIn = googleSignIn;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<AuthSession?> authStateChanges() {
    return _firebaseAuth.authStateChanges().map(_toSession);
  }

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _requireSession(credential.user);
  }

  @override
  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _requireSession(credential.user);
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    if (kIsWeb) {
      final credential =
          await _firebaseAuth.signInWithPopup(GoogleAuthProvider());
      return _requireSession(credential.user);
    }

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw StateError('Google sign in canceled.');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    return _requireSession(userCredential.user);
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
    await _firebaseAuth.signOut();
  }

  AuthSession _requireSession(User? user) {
    final session = _toSession(user);
    if (session == null) {
      throw StateError('Authentication returned no active user session.');
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
