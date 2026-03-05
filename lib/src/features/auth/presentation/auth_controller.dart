import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/runtime/runtime_flags.dart';
import '../data/data_sources/auth_data_source.dart';
import '../data/data_sources/firebase_auth_data_source.dart';
import '../data/data_sources/in_memory_auth_data_source.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../domain/models/auth_user.dart';
import '../domain/repositories/auth_repository.dart';

final authDataSourceProvider = Provider<AuthDataSource>((ref) {
  if (useFirebaseAuth) {
    return FirebaseAuthDataSource(
      firebaseAuth: FirebaseAuth.instance,
      googleSignIn: GoogleSignIn(),
    );
  }
  return InMemoryAuthDataSource();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authDataSourceProvider));
});

final authSessionProvider = StreamProvider<AuthSession?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final activeUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authSessionProvider).valueOrNull?.user.uid;
});

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});

class AuthController {
  AuthController(this._repository);

  final AuthRepository _repository;

  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    return _repository.signInWithEmailPassword(
        email: email, password: password);
  }

  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
  }) {
    return _repository.signUpWithEmailPassword(
        email: email, password: password);
  }

  Future<AuthSession> signInWithGoogle() {
    return _repository.signInWithGoogle();
  }

  Future<void> signOut() {
    return _repository.signOut();
  }
}
