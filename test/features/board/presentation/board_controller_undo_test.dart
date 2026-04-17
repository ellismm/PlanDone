import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/auth/presentation/auth_controller.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/notification_preferences_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/work_item_activity_repository_impl.dart';
import 'package:plandone/src/features/board/presentation/board_controller.dart';

ProviderContainer _container() {
  final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
  final queue = InMemoryOutboxQueue();
  return ProviderContainer(
    overrides: [
      activeUserIdProvider.overrideWith((ref) => 'user-1'),
      localBoardStoreProvider.overrideWith((ref) => localStore),
      outboxQueueProvider.overrideWith((ref) => queue),
      workItemActivityRepositoryProvider.overrideWith(
        (ref) => InMemoryWorkItemActivityRepository(),
      ),
      notificationPreferencesRepositoryProvider.overrideWith(
        (ref) => InMemoryNotificationPreferencesRepository(userId: 'user-1'),
      ),
    ],
  );
}

void main() {
  test('undo restores moved item to previous column', () async {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(boardControllerProvider);
    final before =
        await container.read(localBoardStoreProvider).getBoard('board-1');
    final item = before.items.firstWhere((entry) => entry.itemId == 'a-3');

    await controller.moveItem(itemId: item.itemId, toColumnId: 'c-done');
    controller.stageMoveUndo(
      item: item,
      fromBoardId: item.boardId,
      fromColumnId: item.columnId,
      toBoardId: item.boardId,
      toColumnId: 'c-done',
    );

    final undone = await controller.undoPendingOperation();
    expect(undone, isTrue);

    final after =
        await container.read(localBoardStoreProvider).getBoard('board-1');
    final restored = after.items.firstWhere((entry) => entry.itemId == 'a-3');
    expect(restored.columnId, item.columnId);
  });

  test('undo restores archived state', () async {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(boardControllerProvider);
    final before =
        await container.read(localBoardStoreProvider).getBoard('board-1');
    final item = before.items.firstWhere((entry) => entry.itemId == 'a-3');

    await controller.updateItem(itemId: item.itemId, archived: true);
    controller.stageArchiveUndo(
      item: item,
      fromArchived: item.archived,
      toArchived: true,
    );

    final undone = await controller.undoPendingOperation();
    expect(undone, isTrue);

    final after =
        await container.read(localBoardStoreProvider).getBoard('board-1');
    final restored = after.items.firstWhere((entry) => entry.itemId == 'a-3');
    expect(restored.archived, item.archived);
  });

  test('undo restores deleted item', () async {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(boardControllerProvider);
    final before =
        await container.read(localBoardStoreProvider).getBoard('board-1');
    final item = before.items.firstWhere((entry) => entry.itemId == 'a-3');

    await controller.deleteItem(itemId: item.itemId);
    controller.stageDeleteUndo(item: item);

    final undone = await controller.undoPendingOperation();
    expect(undone, isTrue);

    final after =
        await container.read(localBoardStoreProvider).getBoard('board-1');
    final restored = after.items.firstWhere((entry) => entry.itemId == 'a-3');
    expect(restored.title, item.title);
  });

  test('expired undo is rejected and cleared', () async {
    final container = _container();
    addTearDown(container.dispose);

    final expired = BoardUndoOperation(
      operationId: 'undo-expired',
      kind: BoardUndoOperationKind.archiveToggle,
      itemId: 'a-3',
      message: 'Item archived',
      createdAt: DateTime(2020),
      expiresAt: DateTime(2020),
      fromBoardId: 'board-1',
      toBoardId: 'board-1',
      fromArchived: false,
      toArchived: true,
      deletedItem: null,
      fromColumnId: null,
      toColumnId: null,
      fromParentId: null,
      toParentId: null,
    );

    container.read(pendingBoardUndoOperationProvider.notifier).state = expired;

    final undone =
        await container.read(boardControllerProvider).undoPendingOperation();
    expect(undone, isFalse);
    expect(container.read(pendingBoardUndoOperationProvider), isNull);
  });
}
