import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/sync/firestore_board_hydrator.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';

Future<void> _waitForHydration() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  test('rediscovers owned cloud boards without importing other owners',
      () async {
    final firestore = FakeFirebaseFirestore();
    final localStore = InMemoryLocalBoardStore(currentUserId: 'owner-1');
    final hydrator =
        FirestoreBoardHydrator(firestore: firestore, localStore: localStore);

    await firestore.collection('boards').doc('board-owned').set(const {
      'boardId': 'board-owned',
      'name': 'SW projects',
      'ownerId': 'owner-1',
      'createdAt': '2026-03-20T02:35:19.768Z',
      'updatedAt': '2026-03-21T14:10:33.654Z',
    });
    await firestore.collection('boards').doc('board-other').set(const {
      'boardId': 'board-other',
      'name': 'Someone else\'s board',
      'ownerId': 'owner-2',
      'createdAt': '2026-03-20T02:35:19.768Z',
      'updatedAt': '2026-03-21T14:10:33.654Z',
    });

    final discovered = await hydrator.discoverOwnedBoards('owner-1');
    final boards = await localStore.listBoards();

    expect(discovered, ['board-owned']);
    expect(
      boards.any(
        (board) =>
            board.boardId == 'board-owned' && board.name == 'SW projects',
      ),
      isTrue,
    );
    expect(boards.any((board) => board.boardId == 'board-other'), isFalse);
  });

  test('hydrates board, member, column, and work item from Firestore',
      () async {
    final firestore = FakeFirebaseFirestore();
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-local');
    final hydrator =
        FirestoreBoardHydrator(firestore: firestore, localStore: localStore);

    await hydrator.startForBoard('board-remote');

    await firestore.collection('boards').doc('board-remote').set(const {
      'boardId': 'board-remote',
      'name': 'Remote Board',
      'ownerId': 'owner-1',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'validationSettings': {
        'requireParentForProjects': true,
        'requireParentForTasks': false,
        'requireParentForActions': true,
        'enforceParentTypeOrder': true,
      },
    });
    await firestore
        .collection('boards')
        .doc('board-remote')
        .collection('members')
        .doc('user-2')
        .set(const {
      'boardId': 'board-remote',
      'userId': 'user-2',
      'role': 'member',
      'joinedAt': '2026-01-01T00:00:00.000Z',
      'joinedAtEpochMillis': 1735689600000,
    });
    await firestore
        .collection('boards')
        .doc('board-remote')
        .collection('columns')
        .doc('c-1')
        .set(const {
      'boardId': 'board-remote',
      'columnId': 'c-1',
      'name': 'Backlog',
      'orderIndex': 0,
    });
    await firestore
        .collection('boards')
        .doc('board-remote')
        .collection('workItems')
        .doc('w-1')
        .set(const {
      'boardId': 'board-remote',
      'itemId': 'w-1',
      'title': 'Remote task',
      'type': 'task',
      'columnId': 'c-1',
      'startAt': '2026-01-02T00:00:00.000Z',
      'targetEndAt': '2026-01-10T00:00:00.000Z',
      'dueAt': '2026-01-08T00:00:00.000Z',
      'estimatedEffortMinutes': 120,
      'actualEffortMinutes': 45,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    });

    await _waitForHydration();

    final snapshot = await localStore.getBoard('board-remote');
    expect(snapshot.board.name, 'Remote Board');
    expect(snapshot.board.validationSettings.requireParentForProjects, isTrue);
    expect(snapshot.board.validationSettings.requireParentForActions, isTrue);
    expect(snapshot.members.any((m) => m.userId == 'user-2'), isTrue);
    expect(
      snapshot.members
          .firstWhere((m) => m.userId == 'user-2')
          .joinedAt
          .millisecondsSinceEpoch,
      1735689600000,
    );
    expect(snapshot.columns.any((c) => c.columnId == 'c-1'), isTrue);
    expect(snapshot.items.any((i) => i.itemId == 'w-1'), isTrue);
    final hydrated = snapshot.items.firstWhere((i) => i.itemId == 'w-1');
    expect(hydrated.startAt?.toUtc().toIso8601String(),
        '2026-01-02T00:00:00.000Z');
    expect(
      hydrated.targetEndAt?.toUtc().toIso8601String(),
      '2026-01-10T00:00:00.000Z',
    );
    expect(hydrated.estimatedEffortMinutes, 120);
    expect(hydrated.actualEffortMinutes, 45);

    await hydrator.stop();
  });

  test('missing remote board does not delete a newly created local board',
      () async {
    final firestore = FakeFirebaseFirestore();
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-local');
    final localBoard = await localStore.createBoard('Local only board');
    final hydrator =
        FirestoreBoardHydrator(firestore: firestore, localStore: localStore);

    await hydrator.startForBoard(localBoard.boardId);
    await _waitForHydration();

    final snapshot = await localStore.getBoard(localBoard.boardId);
    expect(snapshot.board.name, 'Local only board');
    expect(snapshot.columns, isNotEmpty);

    await hydrator.stop();
  });

  test('reflects collaborator-origin updates and deletes', () async {
    final firestore = FakeFirebaseFirestore();
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-local');
    final hydrator =
        FirestoreBoardHydrator(firestore: firestore, localStore: localStore);

    await hydrator.startForBoard('board-collab');

    await firestore.collection('boards').doc('board-collab').set(const {
      'boardId': 'board-collab',
      'name': 'Collab',
      'ownerId': 'owner-1',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    });
    await firestore
        .collection('boards')
        .doc('board-collab')
        .collection('columns')
        .doc('c-1')
        .set(const {
      'boardId': 'board-collab',
      'columnId': 'c-1',
      'name': 'Doing',
      'orderIndex': 0,
    });
    await firestore
        .collection('boards')
        .doc('board-collab')
        .collection('workItems')
        .doc('w-1')
        .set(const {
      'boardId': 'board-collab',
      'itemId': 'w-1',
      'title': 'Before update',
      'type': 'task',
      'columnId': 'c-1',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    });

    await _waitForHydration();

    await firestore
        .collection('boards')
        .doc('board-collab')
        .collection('workItems')
        .doc('w-1')
        .update(const {
      'title': 'Changed by collaborator',
      'updatedAt': '2026-01-01T00:00:10.000Z',
    });

    await _waitForHydration();

    var snapshot = await localStore.getBoard('board-collab');
    expect(
      snapshot.items.firstWhere((i) => i.itemId == 'w-1').title,
      'Changed by collaborator',
    );

    await firestore
        .collection('boards')
        .doc('board-collab')
        .collection('workItems')
        .doc('w-1')
        .delete();

    await _waitForHydration();

    snapshot = await localStore.getBoard('board-collab');
    expect(snapshot.items.any((i) => i.itemId == 'w-1'), isFalse);

    await hydrator.stop();
  });
}
