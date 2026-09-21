import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/outbox_operation.dart';
import 'package:plandone/src/core/sync/firestore_sync_remote_adapter.dart';
import 'package:plandone/src/core/sync/sync_remote_adapter.dart';

OutboxOperation _op({
  required String id,
  required OutboxOperationType type,
  required String entity,
  required String entityId,
  required Map<String, Object?> payload,
}) {
  return OutboxOperation(
    id: id,
    type: type,
    entity: entity,
    entityId: entityId,
    payload: payload,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  test('board create persists validation settings and auto-owner member',
      () async {
    final firestore = FakeFirebaseFirestore();
    final adapter = FirestoreSyncRemoteAdapter(firestore: firestore);

    await adapter.applyOperation(
      _op(
        id: 'op-board-create',
        type: OutboxOperationType.create,
        entity: 'board',
        entityId: 'board-1',
        payload: const {
          'version': 1,
          'boardId': 'board-1',
          'name': 'Roadmap',
          'ownerId': 'owner-1',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'validationSettings': {
            'requireParentForProjects': true,
            'requireParentForTasks': false,
            'requireParentForActions': true,
            'enforceParentTypeOrder': true,
          },
        },
      ),
    );

    final board = await firestore.collection('boards').doc('board-1').get();
    expect(board.exists, isTrue);
    expect(board.data()?['name'], 'Roadmap');
    expect(
      (board.data()?['validationSettings'] as Map?)?['requireParentForActions'],
      true,
    );

    final ownerMember = await firestore
        .collection('boards')
        .doc('board-1')
        .collection('members')
        .doc('owner-1')
        .get();
    expect(ownerMember.exists, isTrue);
    expect(ownerMember.data()?['role'], 'owner');

    await adapter.applyOperation(
      _op(
        id: 'op-board-create',
        type: OutboxOperationType.create,
        entity: 'board',
        entityId: 'board-1',
        payload: const {
          'version': 1,
          'boardId': 'board-1',
          'name': 'Roadmap',
          'ownerId': 'owner-1',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
      ),
    );
    final replayedBoard =
        await firestore.collection('boards').doc('board-1').get();
    expect(replayedBoard.data()?['name'], 'Roadmap');
  });

  test('member op writes joinedAtEpochMillis', () async {
    final firestore = FakeFirebaseFirestore();
    final adapter = FirestoreSyncRemoteAdapter(firestore: firestore);

    await adapter.applyOperation(
      _op(
        id: 'op-member-create',
        type: OutboxOperationType.create,
        entity: 'boardMember',
        entityId: 'board-1:user-2',
        payload: const {
          'version': 1,
          'boardId': 'board-1',
          'userId': 'user-2',
          'role': 'member',
          'joinedAt': '2026-01-01T00:00:00.000Z',
          'joinedAtEpochMillis': 1735689600000,
        },
      ),
    );

    final member = await firestore
        .collection('boards')
        .doc('board-1')
        .collection('members')
        .doc('user-2')
        .get();
    expect(member.exists, isTrue);
    expect(member.data()?['joinedAtEpochMillis'], 1735689600000);
  });

  test('applies work item create and is idempotent by operation id', () async {
    final firestore = FakeFirebaseFirestore();
    final adapter = FirestoreSyncRemoteAdapter(firestore: firestore);

    final first = _op(
      id: 'op-1',
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: 'w-1',
      payload: const {
        'version': 1,
        'boardId': 'board-1',
        'itemId': 'w-1',
        'title': 'Original',
        'type': 'task',
        'columnId': 'c-todo',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      },
    );

    await adapter.applyOperation(first);

    final duplicateDifferentPayload = _op(
      id: 'op-1',
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: 'w-1',
      payload: const {
        'version': 1,
        'boardId': 'board-1',
        'itemId': 'w-1',
        'title': 'SHOULD_NOT_APPLY',
        'type': 'task',
        'columnId': 'c-done',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:01.000Z',
      },
    );

    await adapter.applyOperation(duplicateDifferentPayload);

    final item = await firestore
        .collection('boards')
        .doc('board-1')
        .collection('workItems')
        .doc('w-1')
        .get();

    expect(item.exists, isTrue);
    expect(item.data()?['title'], 'Original');
    expect(item.data()?['columnId'], 'c-todo');

    final marker = await firestore
        .collection('boards')
        .doc('board-1')
        .collection('_appliedOps')
        .doc('op-1')
        .get();
    expect(marker.exists, isTrue);
  });

  test('LWW keeps newer remote document when incoming op is older', () async {
    final firestore = FakeFirebaseFirestore();
    final adapter = FirestoreSyncRemoteAdapter(firestore: firestore);

    await firestore
        .collection('boards')
        .doc('board-1')
        .collection('workItems')
        .doc('w-1')
        .set(const {
      'boardId': 'board-1',
      'itemId': 'w-1',
      'title': 'Newer title',
      'type': 'task',
      'columnId': 'c-doing',
      'updatedAtMicros': 200,
    });

    await adapter.applyOperation(
      _op(
        id: 'op-old',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {
          'version': 1,
          'boardId': 'board-1',
          'itemId': 'w-1',
          'title': 'Old title',
          'updatedAt': '1970-01-01T00:00:00.000100Z',
        },
      ),
    );

    final item = await firestore
        .collection('boards')
        .doc('board-1')
        .collection('workItems')
        .doc('w-1')
        .get();

    expect(item.data()?['title'], 'Newer title');
    expect(item.data()?['columnId'], 'c-doing');
    expect(item.data()?['updatedAtMicros'], 200);
  });

  test('move operation updates column while preserving existing fields',
      () async {
    final firestore = FakeFirebaseFirestore();
    final adapter = FirestoreSyncRemoteAdapter(firestore: firestore);

    await firestore
        .collection('boards')
        .doc('board-1')
        .collection('workItems')
        .doc('w-1')
        .set(const {
      'boardId': 'board-1',
      'itemId': 'w-1',
      'title': 'Keep me',
      'type': 'action',
      'columnId': 'c-todo',
      'startAt': '2026-01-01T00:00:00.000Z',
      'estimatedEffortMinutes': 30,
      'updatedAtMicros': 10,
    });

    await adapter.applyOperation(
      _op(
        id: 'op-move',
        type: OutboxOperationType.move,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {
          'version': 1,
          'boardId': 'board-1',
          'itemId': 'w-1',
          'columnId': 'c-done',
          'updatedAt': '2026-01-01T00:00:05.000Z',
          'completedAt': '2026-01-01T00:00:05.000Z',
          'actualEffortMinutes': 20,
        },
      ),
    );

    final item = await firestore
        .collection('boards')
        .doc('board-1')
        .collection('workItems')
        .doc('w-1')
        .get();

    expect(item.data()?['title'], 'Keep me');
    expect(item.data()?['type'], 'action');
    expect(item.data()?['columnId'], 'c-done');
    expect(item.data()?['startAt'], '2026-01-01T00:00:00.000Z');
    expect(item.data()?['estimatedEffortMinutes'], 30);
    expect(item.data()?['actualEffortMinutes'], 20);
    expect(item.data()?['completedAt'], '2026-01-01T00:00:05.000Z');
  });

  test('throws for unsupported entity', () async {
    final firestore = FakeFirebaseFirestore();
    final adapter = FirestoreSyncRemoteAdapter(firestore: firestore);

    expect(
      () => adapter.applyOperation(
        _op(
          id: 'op-x',
          type: OutboxOperationType.update,
          entity: 'unknown',
          entityId: 'x',
          payload: const {
            'version': 1,
            'boardId': 'board-1',
          },
        ),
      ),
      throwsA(isA<SyncRemoteException>()),
    );
  });
}
