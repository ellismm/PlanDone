import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/work_item_recurrence.dart';

void main() {
  test('completing recurring item generates next sequence exactly once',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: InMemoryOutboxQueue(),
    );

    await repository.updateItem(
      boardId: 'board-1',
      itemId: 'a-3',
      recurrence: const WorkItemRecurrence(
        cadence: WorkItemRecurrenceCadence.weekly,
        interval: 1,
        completionGated: true,
        rootItemId: 'a-3',
        sequence: 0,
      ),
    );

    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'a-3',
      toColumnId: 'c-done',
    );
    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'a-3',
      toColumnId: 'c-done',
    );

    final snapshot = await localStore.getBoard('board-1');
    final generated = snapshot.items.where((item) {
      final recurrence = item.recurrence;
      return recurrence != null &&
          recurrence.rootItemId == 'a-3' &&
          recurrence.sequence == 1;
    }).toList();

    expect(generated.length, 1);
    expect(generated.single.itemId, 'w-rec-a-3-1');
    expect(generated.single.completedAt, isNull);
    expect(generated.single.columnId, isNot('c-done'));
  });

  test('completing generated recurrence item advances to next sequence',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: InMemoryOutboxQueue(),
    );

    await repository.updateItem(
      boardId: 'board-1',
      itemId: 'a-3',
      recurrence: const WorkItemRecurrence(
        cadence: WorkItemRecurrenceCadence.daily,
        interval: 1,
        completionGated: true,
        rootItemId: 'a-3',
        sequence: 0,
      ),
    );

    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'a-3',
      toColumnId: 'c-done',
    );

    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'w-rec-a-3-1',
      toColumnId: 'c-done',
    );

    final snapshot = await localStore.getBoard('board-1');
    final seq2 = snapshot.items.where((item) {
      final recurrence = item.recurrence;
      return recurrence != null &&
          recurrence.rootItemId == 'a-3' &&
          recurrence.sequence == 2;
    }).toList();

    expect(seq2.length, 1);
    expect(seq2.single.itemId, 'w-rec-a-3-2');
  });

  test('missed windows are advanced beyond completion time', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: InMemoryOutboxQueue(),
    );

    final historicalDue = DateTime.now().subtract(const Duration(days: 21));
    await repository.updateItem(
      boardId: 'board-1',
      itemId: 'a-3',
      dueAt: historicalDue,
      recurrence: const WorkItemRecurrence(
        cadence: WorkItemRecurrenceCadence.weekly,
        interval: 1,
        completionGated: true,
        rootItemId: 'a-3',
        sequence: 0,
      ),
    );

    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'a-3',
      toColumnId: 'c-done',
    );

    final snapshot = await localStore.getBoard('board-1');
    final generated =
        snapshot.items.firstWhere((item) => item.itemId == 'w-rec-a-3-1');
    final original = snapshot.items.firstWhere((item) => item.itemId == 'a-3');

    expect(generated.dueAt, isNotNull);
    expect(generated.dueAt!.isAfter(original.completedAt!), isTrue);
  });
}
