import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/work_item_activity_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/work_item_activity_event.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  test('create/move/archive/reparent emit expected activity events', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final activityRepo = InMemoryWorkItemActivityRepository();
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      activityRepository: activityRepo,
    );

    await repository.createItem(
      boardId: 'board-1',
      title: 'Activity test item',
      type: WorkItemType.action,
      toColumnId: 'c-todo',
      parentId: 't-2',
    );

    final snapshot = await localStore.getBoard('board-1');
    final item =
        snapshot.items.firstWhere((it) => it.title == 'Activity test item');

    await repository.moveItem(
      boardId: 'board-1',
      itemId: item.itemId,
      toColumnId: 'c-done',
    );

    await repository.updateItem(
      boardId: 'board-1',
      itemId: item.itemId,
      archived: true,
    );

    await repository.reparentItem(
      boardId: 'board-1',
      itemId: item.itemId,
      parentId: 'p-1',
    );

    final events = await activityRepo.listForItem(
      boardId: 'board-1',
      itemId: item.itemId,
      limit: 20,
    );

    expect(events.any((e) => e.type == WorkItemActivityType.created), isTrue);
    expect(events.any((e) => e.type == WorkItemActivityType.moved), isTrue);
    expect(events.any((e) => e.type == WorkItemActivityType.completed), isTrue);
    expect(events.any((e) => e.type == WorkItemActivityType.archived), isTrue);
    expect(
        events.any((e) => e.type == WorkItemActivityType.reparented), isTrue);
  });

  test('activity list returns latest event first', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final activityRepo = InMemoryWorkItemActivityRepository();
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      activityRepository: activityRepo,
    );

    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'a-3',
      toColumnId: 'c-done',
    );
    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'a-3',
      toColumnId: 'c-doing',
    );

    final events = await activityRepo.listForItem(
      boardId: 'board-1',
      itemId: 'a-3',
      limit: 10,
    );

    expect(events.length, greaterThanOrEqualTo(2));
    expect(
        events.first.createdAt.isAfter(events.last.createdAt) ||
            events.first.createdAt.isAtSameMomentAs(events.last.createdAt),
        isTrue);
    expect(
      events.any((entry) => entry.type == WorkItemActivityType.reopened),
      isTrue,
    );
  });
}
