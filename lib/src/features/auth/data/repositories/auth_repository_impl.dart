import '../../domain/models/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../data_sources/auth_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._dataSource);

  final AuthDataSource _dataSource;

  @override
  Stream<AuthSession?> authStateChanges() => _dataSource.authStateChanges();

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    return _dataSource.signInWithEmailPassword(
        email: email, password: password);
  }

  @override
  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) {
    return _dataSource.signUpWithEmailPassword(
        email: email, password: password);
  }

  @override
  Future<AuthSession> signInWithGoogle() {
    return _dataSource.signInWithGoogle();
  }

  @override
  Future<void> signOut() {
    return _dataSource.signOut();
  }
}
