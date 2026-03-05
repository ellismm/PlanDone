import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  test('bulk update remains responsive on large board fixture', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: InMemoryOutboxQueue(),
    );

    final baseline = await localStore.getBoard('board-1');
    final columns = baseline.columns;
    final sourceColumnId = columns.first.columnId;
    final targetColumnId = columns.last.columnId;

    final now = DateTime.now();
    final generatedIds = <String>[];
    for (var i = 0; i < 700; i++) {
      final id = 'perf-item-$i';
      generatedIds.add(id);
      await localStore.upsertItem(
        WorkItem(
          itemId: id,
          boardId: 'board-1',
          title: 'Perf Item $i',
          type: i.isEven ? WorkItemType.task : WorkItemType.action,
          columnId: sourceColumnId,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final stopwatch = Stopwatch()..start();
    await repository.bulkUpdateItems(
      boardId: 'board-1',
      itemIds: generatedIds,
      toColumnId: targetColumnId,
      archived: true,
      addTags: const ['perf'],
    );
    stopwatch.stop();
    // Keep a concrete measurement in test output for phase reporting.
    // ignore: avoid_print
    print('perf: bulkUpdateItems(700)=${stopwatch.elapsedMilliseconds}ms');

    expect(stopwatch.elapsedMilliseconds, lessThan(5000));

    final updated = await localStore.getBoard('board-1');
    final sample = updated.items
        .where((item) => generatedIds.take(20).contains(item.itemId))
        .toList();
    expect(sample, isNotEmpty);
    expect(sample.every((item) => item.columnId == targetColumnId), isTrue);
    expect(sample.every((item) => item.archived), isTrue);
    expect(sample.every((item) => item.tags.contains('perf')), isTrue);
  });

  test('deep-hierarchy re-parent operation stays within practical bounds',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: InMemoryOutboxQueue(),
    );

    final baseline = await localStore.getBoard('board-1');
    final columnId = baseline.columns.first.columnId;
    final now = DateTime.now();

    String? parentId;
    for (var i = 0; i < 350; i++) {
      final id = 'chain-$i';
      await localStore.upsertItem(
        WorkItem(
          itemId: id,
          boardId: 'board-1',
          title: 'Chain Item $i',
          type: WorkItemType.action,
          columnId: columnId,
          parentId: parentId,
          createdAt: now,
          updatedAt: now,
        ),
      );
      parentId = id;
    }

    final stopwatch = Stopwatch()..start();
    await repository.reparentItem(
      boardId: 'board-1',
      itemId: 'chain-349',
      parentId: null,
      clearParent: true,
    );
    stopwatch.stop();
    // ignore: avoid_print
    print('perf: reparent(chain-depth-350)=${stopwatch.elapsedMilliseconds}ms');

    expect(stopwatch.elapsedMilliseconds, lessThan(2000));

    final updated = await localStore.getBoard('board-1');
    final root = updated.items.firstWhere((item) => item.itemId == 'chain-349');
    expect(root.parentId, isNull);
  });
}
