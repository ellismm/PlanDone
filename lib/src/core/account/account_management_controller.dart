import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_flags.dart';
import '../theme/theme_controller.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/board/data/platform/storage_platform.dart'
    as storage_platform;
import '../../features/board/data/platform/user_scoped_board_database.dart';
import '../../features/board/presentation/board_controller.dart';

enum BiometricQuickUnlockStatus {
  unsupported,
  disabled,
  enabled,
}

final biometricQuickUnlockStatusProvider =
    FutureProvider<BiometricQuickUnlockStatus?>((ref) async {
  final session = ref.watch(authSessionProvider).valueOrNull;
  if (session == null) {
    return null;
  }
  final service = ref.watch(biometricQuickUnlockServiceProvider);
  if (!await service.isSupported()) {
    return BiometricQuickUnlockStatus.unsupported;
  }
  final canOffer = await service.canOffer(session);
  return canOffer
      ? BiometricQuickUnlockStatus.disabled
      : BiometricQuickUnlockStatus.enabled;
});

final accountManagementControllerProvider =
    Provider<AccountManagementController>((ref) {
  return AccountManagementController(ref);
});

class AccountManagementController {
  AccountManagementController(this._ref);

  final Ref _ref;

  Future<void> signOut() {
    return _ref.read(authControllerProvider).signOut();
  }

  Future<void> enableBiometricQuickUnlock() async {
    final session = _ref.read(authSessionProvider).valueOrNull;
    if (session == null) return;
    await _ref.read(authControllerProvider).enableBiometricQuickUnlock(session);
    _ref.invalidate(biometricQuickUnlockStatusProvider);
  }

  Future<void> disableBiometricQuickUnlock() async {
    await _ref.read(authControllerProvider).disableBiometricQuickUnlock();
    _ref.invalidate(biometricQuickUnlockStatusProvider);
  }

  Future<void> deleteCurrentAccount() async {
    final session = _ref.read(authSessionProvider).valueOrNull;
    if (session == null) return;

    final userId = session.user.uid;
    final databaseName = boardDatabaseNameForUser(userId);
    final boardDatabase = _ref.read(boardDatabaseProvider);
    await _ref.read(authControllerProvider).deleteAccount();
    try {
      await boardDatabase.close();
      await storage_platform.deleteBoardDatabase(
        databaseName: databaseName,
        useInMemoryLocalStore: useInMemoryLocalStore,
      );
    } catch (_) {
      // The account has already been deleted at this point. Local cache cleanup
      // is best-effort and should not block the user from leaving the session.
    }

    _ref.invalidate(boardDatabaseProvider);
    _ref.invalidate(themeControllerProvider);
    _ref.invalidate(biometricQuickUnlockStatusProvider);
  }
}
