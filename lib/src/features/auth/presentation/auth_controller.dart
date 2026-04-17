import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/runtime/app_bootstrap_state.dart';
import '../../../core/runtime/runtime_flags.dart';
import '../data/data_sources/auth_data_source.dart';
import '../data/data_sources/firebase_auth_data_source.dart';
import '../data/data_sources/in_memory_auth_data_source.dart';
import '../data/data_sources/persistent_local_auth_data_source.dart';
import '../data/data_sources/unavailable_auth_data_source.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/services/biometric_quick_unlock_service.dart';
import '../domain/models/auth_user.dart';
import '../domain/repositories/auth_repository.dart';

final authDataSourceProvider = Provider<AuthDataSource>((ref) {
  final bootstrapState = ref.watch(appBootstrapStateProvider);
  if (useFirebaseAuth && bootstrapState.firebaseReady) {
    return FirebaseAuthDataSource(
      firebaseAuth: FirebaseAuth.instance,
      googleSignIn: GoogleSignIn(),
    );
  }
  if (useFirebaseAuth && !bootstrapState.firebaseReady) {
    return UnavailableAuthDataSource(
      bootstrapState.firebaseErrorMessage ??
          'Firebase Auth is enabled for this build, but Android Firebase setup is incomplete.',
    );
  }
  if (!isFlutterTestRuntime &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android) {
    return PersistentLocalAuthDataSource();
  }
  return InMemoryAuthDataSource();
});

final biometricQuickUnlockServiceProvider =
    Provider<BiometricQuickUnlockService>((ref) {
  if (useFirebaseAuth) {
    return AndroidBiometricQuickUnlockService();
  }
  return const UnsupportedBiometricQuickUnlockService();
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
  return AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(biometricQuickUnlockServiceProvider),
  );
});

class AuthController {
  AuthController(
    this._repository,
    this._biometricQuickUnlockService,
  );

  final AuthRepository _repository;
  final BiometricQuickUnlockService _biometricQuickUnlockService;

  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final session = await _repository.signInWithEmailPassword(
      email: email,
      password: password,
    );
    await _biometricQuickUnlockService.markTrusted(session);
    return session;
  }

  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final session = await _repository.signUpWithEmailPassword(
      email: email,
      password: password,
      displayName: displayName,
    );
    await _biometricQuickUnlockService.markTrusted(session);
    return session;
  }

  Future<AuthSession> signInWithGoogle() async {
    final session = await _repository.signInWithGoogle();
    await _biometricQuickUnlockService.markTrusted(session);
    return session;
  }

  Future<void> sendPasswordResetEmail({
    required String email,
  }) {
    return _repository.sendPasswordResetEmail(email: email);
  }

  Future<bool> canOfferBiometricQuickUnlock(AuthSession session) {
    return _biometricQuickUnlockService.canOffer(session);
  }

  Future<void> enableBiometricQuickUnlock(AuthSession session) {
    return _biometricQuickUnlockService.enableForSession(session);
  }

  Future<void> disableBiometricQuickUnlock() {
    return _biometricQuickUnlockService.clear();
  }

  Future<bool> requiresBiometricQuickUnlock(AuthSession session) {
    return _biometricQuickUnlockService.requiresUnlock(session);
  }

  Future<bool> unlockWithBiometrics(AuthSession session) {
    return _biometricQuickUnlockService.unlock(session);
  }

  Future<void> signOut() async {
    await _repository.signOut();
    await _biometricQuickUnlockService.clear();
  }

  Future<void> deleteAccount() async {
    await _repository.deleteAccount();
    await _biometricQuickUnlockService.clear();
  }
}
