import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/account/account_data_cleanup_service.dart';

void main() {
  test('account deletion recency policy is conservative', () {
    final now = DateTime.utc(2026, 8, 29, 5);

    expect(
      AccountDeletionRecencyPolicy.isRecent(
        authTime: now.subtract(const Duration(minutes: 1)),
        now: now,
        maximumAge: const Duration(minutes: 2),
      ),
      isTrue,
    );
    expect(
      AccountDeletionRecencyPolicy.isRecent(
        authTime: now.subtract(const Duration(minutes: 3)),
        now: now,
        maximumAge: const Duration(minutes: 2),
      ),
      isFalse,
    );
    expect(
      AccountDeletionRecencyPolicy.isRecent(
        authTime: null,
        now: now,
        maximumAge: const Duration(minutes: 2),
      ),
      isFalse,
    );
    expect(
      AccountDeletionRecencyPolicy.isRecent(
        authTime: now.add(const Duration(seconds: 1)),
        now: now,
        maximumAge: const Duration(minutes: 2),
      ),
      isFalse,
    );
  });

  test('deletes owned boards, shared memberships, devices, and user record',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreAccountDataCleanupService(
      firestore: firestore,
    );

    final ownedBoard = firestore.collection('boards').doc('owned-board');
    await ownedBoard.set({
      'boardId': 'owned-board',
      'name': 'Owned board',
      'ownerId': 'user-1',
    });
    await ownedBoard.collection('members').doc('user-1').set({
      'boardId': 'owned-board',
      'userId': 'user-1',
      'role': 'owner',
      'joinedAtEpochMillis': 1,
    });
    await ownedBoard.collection('members').doc('collaborator').set({
      'boardId': 'owned-board',
      'userId': 'collaborator',
      'role': 'member',
      'joinedAtEpochMillis': 1,
    });
    await ownedBoard.collection('columns').doc('column-1').set({
      'boardId': 'owned-board',
      'columnId': 'column-1',
      'name': 'To Do',
      'orderIndex': 0,
    });
    await ownedBoard.collection('workItems').doc('item-1').set({
      'boardId': 'owned-board',
      'itemId': 'item-1',
      'title': 'Private item',
      'type': 'task',
      'columnId': 'column-1',
    });
    await ownedBoard.collection('_appliedOps').doc('op-1').set({
      'operationId': 'op-1',
      'entity': 'workItem',
      'entityId': 'item-1',
      'type': 'create',
    });

    final sharedBoard = firestore.collection('boards').doc('shared-board');
    await sharedBoard.set({
      'boardId': 'shared-board',
      'name': 'Shared board',
      'ownerId': 'other-owner',
    });
    await sharedBoard.collection('members').doc('other-owner').set({
      'boardId': 'shared-board',
      'userId': 'other-owner',
      'role': 'owner',
      'joinedAtEpochMillis': 1,
    });
    await sharedBoard.collection('members').doc('user-1').set({
      'boardId': 'shared-board',
      'userId': 'user-1',
      'role': 'member',
      'joinedAtEpochMillis': 1,
    });
    await sharedBoard.collection('workItems').doc('shared-item').set({
      'boardId': 'shared-board',
      'itemId': 'shared-item',
      'title': 'Shared content remains',
      'type': 'task',
      'columnId': 'shared-column',
    });

    final user = firestore.collection('users').doc('user-1');
    await user.set({'displayName': 'User One'});
    await user.collection('devices').doc('phone').set({
      'token': 'token-1',
      'platform': 'android',
    });

    await service.deleteCloudData(userId: 'user-1');

    expect((await ownedBoard.get()).exists, isFalse);
    expect((await ownedBoard.collection('members').get()).docs, isEmpty);
    expect((await ownedBoard.collection('columns').get()).docs, isEmpty);
    expect((await ownedBoard.collection('workItems').get()).docs, isEmpty);
    expect((await ownedBoard.collection('_appliedOps').get()).docs, isEmpty);

    expect((await sharedBoard.get()).exists, isTrue);
    expect(
      (await sharedBoard.collection('members').doc('user-1').get()).exists,
      isFalse,
    );
    expect(
      (await sharedBoard.collection('members').doc('other-owner').get()).exists,
      isTrue,
    );
    expect(
      (await sharedBoard.collection('workItems').doc('shared-item').get())
          .exists,
      isTrue,
    );

    expect((await user.get()).exists, isFalse);
    expect((await user.collection('devices').get()).docs, isEmpty);
  });

  test('cleanup is safe to retry after it has completed', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreAccountDataCleanupService(
      firestore: firestore,
    );

    await service.deleteCloudData(userId: 'user-1');
    await service.deleteCloudData(userId: 'user-1');

    expect(
      (await firestore.collection('users').doc('user-1').get()).exists,
      isFalse,
    );
  });

  test('cleanup rejects an empty user id', () async {
    final service = FirestoreAccountDataCleanupService(
      firestore: FakeFirebaseFirestore(),
    );

    await expectLater(
      service.deleteCloudData(userId: '  '),
      throwsArgumentError,
    );
  });
}
