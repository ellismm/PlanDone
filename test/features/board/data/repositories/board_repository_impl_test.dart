import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/board_member.dart';

void main() {
  test('moveItem sets completedAt when moved into Done column', () async {
    final localStore = InMemoryLocalBoardStore();
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.moveItem(boardId: 'board-1', itemId: 'w-1', toColumnId: 'c-done');

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((item) => item.itemId == 'w-1');
    expect(moved.columnId, 'c-done');
    expect(moved.completedAt, isNotNull);

    final pending = await outboxQueue.listPending();
    final moveOp = pending.last;
    expect(moveOp.entity, 'workItem');
    expect(moveOp.payload['itemId'], 'w-1');
    expect(moveOp.payload['toColumnId'], 'c-done');
    expect(moveOp.payload['completedAt'], isNotNull);
  });

  test('moveItem clears completedAt when moved out of Done column', () async {
    final localStore = InMemoryLocalBoardStore();
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.moveItem(boardId: 'board-1', itemId: 'w-1', toColumnId: 'c-done');
    await repository.moveItem(boardId: 'board-1', itemId: 'w-1', toColumnId: 'c-doing');

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((item) => item.itemId == 'w-1');
    expect(moved.columnId, 'c-doing');
    expect(moved.completedAt, isNull);

    final pending = await outboxQueue.listPending();
    final secondMoveOp = pending.last;
    expect(secondMoveOp.payload['itemId'], 'w-1');
    expect(secondMoveOp.payload['toColumnId'], 'c-doing');
    expect(secondMoveOp.payload['completedAt'], isNull);
  });

  test('updateItem updates editable fields and enqueues update outbox op', () async {
    final localStore = InMemoryLocalBoardStore();
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final dueAt = DateTime.now().add(const Duration(days: 7));

    await repository.updateItem(
      boardId: 'board-1',
      itemId: 'a-3',
      title: 'Add parent-child jump links and detail editing',
      description: 'Polish hierarchy navigation UX.',
      parentId: 'p-1',
      dueAt: dueAt,
      tags: const ['ux', 'hierarchy'],
    );

    final snapshot = await localStore.getBoard('board-1');
    final updated = snapshot.items.firstWhere((item) => item.itemId == 'a-3');
    expect(updated.title, 'Add parent-child jump links and detail editing');
    expect(updated.description, 'Polish hierarchy navigation UX.');
    expect(updated.parentId, 'p-1');
    expect(updated.dueAt?.toIso8601String(), dueAt.toIso8601String());
    expect(updated.tags, ['ux', 'hierarchy']);

    final pending = await outboxQueue.listPending();
    final op = pending.last;
    expect(op.type.name, 'update');
    expect(op.entity, 'workItem');
    expect(op.entityId, 'a-3');
    expect(op.payload['title'], 'Add parent-child jump links and detail editing');
  });

  test('updateItem can clear parent, description, and due date', () async {
    final localStore = InMemoryLocalBoardStore();
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.updateItem(
      boardId: 'board-1',
      itemId: 'a-4',
      clearParent: true,
      clearDescription: true,
      clearDueAt: true,
      tags: const [],
    );

    final snapshot = await localStore.getBoard('board-1');
    final updated = snapshot.items.firstWhere((item) => item.itemId == 'a-4');
    expect(updated.parentId, isNull);
    expect(updated.description, isNull);
    expect(updated.dueAt, isNull);
    expect(updated.tags, isEmpty);
  });

  test('viewer cannot move item but admin can manage members', () async {
    final localStore = InMemoryLocalBoardStore();
    final outboxQueue = InMemoryOutboxQueue();

    final ownerRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'user-1',
    );

    await ownerRepository.addMember(
      boardId: 'board-1',
      userId: 'user-viewer',
      role: BoardRole.viewer,
    );

    final viewerRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'user-viewer',
    );

    expect(
      () => viewerRepository.moveItem(boardId: 'board-1', itemId: 'a-3', toColumnId: 'c-done'),
      throwsA(isA<BoardPermissionDeniedException>()),
    );

    await ownerRepository.updateMemberRole(
      boardId: 'board-1',
      userId: 'user-viewer',
      role: BoardRole.member,
    );

    await viewerRepository.moveItem(boardId: 'board-1', itemId: 'a-3', toColumnId: 'c-done');

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((i) => i.itemId == 'a-3');
    expect(moved.columnId, 'c-done');
  });

  test('moveItemToBoard transfers item and enqueues create+delete outbox ops', () async {
    final localStore = InMemoryLocalBoardStore();
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final targetBoard = await repository.createBoard('Target Board');
    final targetColumnId = '${targetBoard.boardId}-c-todo';

    await repository.moveItemToBoard(
      fromBoardId: 'board-1',
      itemId: 'a-3',
      toBoardId: targetBoard.boardId,
      toColumnId: targetColumnId,
    );

    final sourceSnapshot = await localStore.getBoard('board-1');
    expect(sourceSnapshot.items.where((i) => i.itemId == 'a-3'), isEmpty);

    final targetSnapshot = await localStore.getBoard(targetBoard.boardId);
    final moved = targetSnapshot.items.firstWhere((i) => i.itemId == 'a-3');
    expect(moved.boardId, targetBoard.boardId);
    expect(moved.columnId, targetColumnId);
    expect(moved.completedAt, isNull);

    final pending = await outboxQueue.listPending();
    expect(pending.length, greaterThanOrEqualTo(2));
    expect(pending[pending.length - 2].type.name, 'create');
    expect(pending[pending.length - 1].type.name, 'delete');
  });

  test('moveItemToBoard sets completedAt when moved into target Done column', () async {
    final localStore = InMemoryLocalBoardStore();
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final targetBoard = await repository.createBoard('Target Board');
    final targetDoneColumnId = '${targetBoard.boardId}-c-done';

    await repository.moveItemToBoard(
      fromBoardId: 'board-1',
      itemId: 'a-4',
      toBoardId: targetBoard.boardId,
      toColumnId: targetDoneColumnId,
    );

    final targetSnapshot = await localStore.getBoard(targetBoard.boardId);
    final moved = targetSnapshot.items.firstWhere((i) => i.itemId == 'a-4');
    expect(moved.columnId, targetDoneColumnId);
    expect(moved.completedAt, isNotNull);
  });

  test('deleteColumn keeps completedAt aligned with fallback done status', () async {
    final localStore = InMemoryLocalBoardStore();
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    // Ensure DONE becomes the fallback by removing DOING first.
    await repository.deleteColumn(boardId: 'board-1', columnId: 'c-doing');

    // Move item into TODO so deleting TODO will move it into DONE fallback.
    await repository.moveItem(boardId: 'board-1', itemId: 'a-3', toColumnId: 'c-todo');

    await repository.deleteColumn(boardId: 'board-1', columnId: 'c-todo');

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((i) => i.itemId == 'a-3');
    expect(moved.columnId, 'c-done');
    expect(moved.completedAt, isNotNull);
  });
}