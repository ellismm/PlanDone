import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../domain/models/auth_user.dart';

abstract class BiometricQuickUnlockService {
  Future<bool> isSupported();

  Future<bool> canOffer(AuthSession session);

  Future<bool> requiresUnlock(AuthSession session);

  Future<void> markTrusted(AuthSession session);

  Future<void> enableForSession(AuthSession session);

  Future<bool> unlock(AuthSession session);

  Future<void> clear();
}

class AndroidBiometricQuickUnlockService
    implements BiometricQuickUnlockService {
  AndroidBiometricQuickUnlockService({
    LocalAuthentication? localAuthentication,
    FlutterSecureStorage? secureStorage,
  })  : _localAuthentication = localAuthentication ?? LocalAuthentication(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _enabledUserKey = 'auth.biometric.enabled_user_id';
  final LocalAuthentication _localAuthentication;
  final FlutterSecureStorage _secureStorage;

  String? _trustedUserId;

  @override
  Future<bool> isSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final canCheckBiometrics = await _localAuthentication.canCheckBiometrics;
    final isDeviceSupported = await _localAuthentication.isDeviceSupported();
    return canCheckBiometrics && isDeviceSupported;
  }

  @override
  Future<bool> canOffer(AuthSession session) async {
    if (!await isSupported()) return false;
    final enabledUserId = await _secureStorage.read(key: _enabledUserKey);
    return enabledUserId != session.user.uid;
  }

  @override
  Future<bool> requiresUnlock(AuthSession session) async {
    if (!await isSupported()) return false;
    final enabledUserId = await _secureStorage.read(key: _enabledUserKey);
    return enabledUserId == session.user.uid &&
        _trustedUserId != session.user.uid;
  }

  @override
  Future<void> markTrusted(AuthSession session) async {
    _trustedUserId = session.user.uid;
  }

  @override
  Future<void> enableForSession(AuthSession session) async {
    await _secureStorage.write(
      key: _enabledUserKey,
      value: session.user.uid,
    );
    _trustedUserId = session.user.uid;
  }

  @override
  Future<bool> unlock(AuthSession session) async {
    if (!await requiresUnlock(session)) {
      return true;
    }
    final authenticated = await _localAuthentication.authenticate(
      localizedReason: 'Unlock PlanDone',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: false,
        sensitiveTransaction: true,
      ),
    );
    if (authenticated) {
      _trustedUserId = session.user.uid;
    }
    return authenticated;
  }

  @override
  Future<void> clear() async {
    _trustedUserId = null;
    await _secureStorage.delete(key: _enabledUserKey);
  }
}

class UnsupportedBiometricQuickUnlockService
    implements BiometricQuickUnlockService {
  const UnsupportedBiometricQuickUnlockService();

  @override
  Future<bool> canOffer(AuthSession session) async => false;

  @override
  Future<void> clear() async {}

  @override
  Future<void> enableForSession(AuthSession session) async {}

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<void> markTrusted(AuthSession session) async {}

  @override
  Future<bool> requiresUnlock(AuthSession session) async => false;

  @override
  Future<bool> unlock(AuthSession session) async => true;
}
