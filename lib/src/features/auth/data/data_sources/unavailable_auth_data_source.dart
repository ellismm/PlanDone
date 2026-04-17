import '../../domain/models/auth_failure.dart';
import '../../domain/models/auth_user.dart';
import 'auth_data_source.dart';

class UnavailableAuthDataSource implements AuthDataSource {
  const UnavailableAuthDataSource(this._message);

  final String _message;

  Never _throwUnavailable() {
    throw AuthFailure(
      code: AuthFailureCode.firebaseNotConfigured,
      message: _message,
    );
  }

  @override
  Stream<AuthSession?> authStateChanges() => Stream<AuthSession?>.value(null);

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _throwUnavailable();
  }

  @override
  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _throwUnavailable();
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    _throwUnavailable();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
  }) async {
    _throwUnavailable();
  }

  @override
  Future<void> deleteAccount() async {
    _throwUnavailable();
  }

  @override
  Future<void> signOut() async {}
}
