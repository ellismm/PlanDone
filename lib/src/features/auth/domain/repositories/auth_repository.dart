import '../models/auth_user.dart';

abstract class AuthRepository {
  Stream<AuthSession?> authStateChanges();

  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  });

  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  });

  Future<AuthSession> signInWithGoogle();

  Future<void> sendPasswordResetEmail({
    required String email,
  });

  Future<void> deleteAccount();

  Future<void> signOut();
}
