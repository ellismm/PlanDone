import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/work_item_activity_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/work_item_recurrence.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  Future<(BoardRepositoryImpl, InMemoryLocalBoardStore)>
      createRepository() async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: InMemoryOutboxQueue(),
      activityRepository: InMemoryWorkItemActivityRepository(),
      currentUserId: 'user-1',
    );
    return (repository, localStore);
  }

  test('next eligible recurrence advances into the future when completed late',
      () async {
    final (repository, localStore) = await createRepository();
    final created = await repository.createItem(
      boardId: 'board-1',
      title: 'Weekly review',
      type: WorkItemType.task,
      toColumnId: 'c-doing',
    );
    final lateDueAt = DateTime.now().subtract(const Duration(days: 21));
    await repository.updateItem(
      boardId: 'board-1',
      itemId: created.itemId,
      dueAt: lateDueAt,
      recurrence: WorkItemRecurrence(
        cadence: WorkItemRecurrenceCadence.weekly,
        interval: 1,
        missedWindowPolicy: WorkItemRecurrenceMissedWindowPolicy.nextEligible,
        rootItemId: created.itemId,
      ),
    );

    final completionMoment = DateTime.now();
    await repository.moveItem(
      boardId: 'board-1',
      itemId: created.itemId,
      toColumnId: 'c-done',
    );

    final snapshot = await localStore.getBoard('board-1');
    final generated = snapshot.items.firstWhere(
      (item) =>
          item.recurrence?.rootItemId == created.itemId &&
          item.recurrence?.sequence == 1,
    );

    expect(generated.dueAt, isNotNull);
    expect(generated.dueAt!.isAfter(completionMoment), isTrue);
  });

  test('single-step recurrence preserves the immediate next cycle even if late',
      () async {
    final (repository, localStore) = await createRepository();
    final created = await repository.createItem(
      boardId: 'board-1',
      title: 'Weekly review',
      type: WorkItemType.task,
      toColumnId: 'c-doing',
    );
    final lateDueAt = DateTime.now().subtract(const Duration(days: 21));
    await repository.updateItem(
      boardId: 'board-1',
      itemId: created.itemId,
      dueAt: lateDueAt,
      recurrence: WorkItemRecurrence(
        cadence: WorkItemRecurrenceCadence.weekly,
        interval: 1,
        missedWindowPolicy: WorkItemRecurrenceMissedWindowPolicy.singleStep,
        rootItemId: created.itemId,
      ),
    );

    await repository.moveItem(
      boardId: 'board-1',
      itemId: created.itemId,
      toColumnId: 'c-done',
    );

    final snapshot = await localStore.getBoard('board-1');
    final generated = snapshot.items.firstWhere(
      (item) =>
          item.recurrence?.rootItemId == created.itemId &&
          item.recurrence?.sequence == 1,
    );

    expect(generated.dueAt, lateDueAt.add(const Duration(days: 7)));
  });

  test('manual catch-up skips auto-generation when the next cycle was missed',
      () async {
    final (repository, localStore) = await createRepository();
    final created = await repository.createItem(
      boardId: 'board-1',
      title: 'Weekly review',
      type: WorkItemType.task,
      toColumnId: 'c-doing',
    );
    await repository.updateItem(
      boardId: 'board-1',
      itemId: created.itemId,
      dueAt: DateTime.now().subtract(const Duration(days: 21)),
      recurrence: WorkItemRecurrence(
        cadence: WorkItemRecurrenceCadence.weekly,
        interval: 1,
        missedWindowPolicy: WorkItemRecurrenceMissedWindowPolicy.manualCatchUp,
        rootItemId: created.itemId,
      ),
    );

    await repository.moveItem(
      boardId: 'board-1',
      itemId: created.itemId,
      toColumnId: 'c-done',
    );

    final snapshot = await localStore.getBoard('board-1');
    final generated = snapshot.items.where(
      (item) =>
          item.recurrence?.rootItemId == created.itemId &&
          item.recurrence?.sequence == 1,
    );

    expect(generated, isEmpty);
  });
}
