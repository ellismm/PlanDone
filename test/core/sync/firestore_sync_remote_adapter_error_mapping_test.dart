import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/sync/firestore_sync_remote_adapter.dart';
import 'package:plandone/src/core/sync/sync_remote_adapter.dart';

void main() {
  test('permission-denied FirebaseException maps to permission denied', () {
    final mapped = mapFirestoreExceptionToSyncRemote(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      'op-1',
    );

    expect(mapped, isA<SyncRemotePermissionDeniedException>());
    expect(mapped.toString(), contains('op-1'));
  });

  test('non-permission FirebaseException maps to generic sync remote error',
      () {
    final mapped = mapFirestoreExceptionToSyncRemote(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'network unavailable',
      ),
      'op-2',
    );

    expect(mapped, isA<SyncRemoteException>());
    expect(mapped, isNot(isA<SyncRemotePermissionDeniedException>()));
    expect(mapped.toString(), contains('unavailable'));
  });
}
