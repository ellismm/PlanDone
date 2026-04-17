import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_backup_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/board_validation_settings.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_recurrence.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  test('export/import round-trip preserves hierarchy and recurrence metadata',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('plandone_backup_test');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final snapshot = await localStore.getBoard('board-1');
    await localStore.upsertBoard(
      snapshot.board.copyWith(
        validationSettings: const BoardValidationSettings(
          requireParentForTasks: true,
        ),
      ),
    );
    await localStore.upsertItem(
      WorkItem(
        itemId: 'recurring-task',
        boardId: 'board-1',
        title: 'Weekly review',
        type: WorkItemType.task,
        parentId: 'p-1',
        columnId: 'c-doing',
        dueAt: DateTime(2026, 3, 20),
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
        recurrence: const WorkItemRecurrence(
          cadence: WorkItemRecurrenceCadence.weekly,
          interval: 1,
          missedWindowPolicy: WorkItemRecurrenceMissedWindowPolicy.singleStep,
          rootItemId: 'recurring-task',
        ),
      ),
    );

    final repository = BoardBackupRepositoryImpl(
      localStore: localStore,
      outboxQueue: InMemoryOutboxQueue(),
      currentUserId: 'user-1',
      directoryProvider: () async => tempDir,
      clock: () => DateTime(2026, 3, 18, 10, 30),
    );

    final backup = await repository.exportBoard(boardId: 'board-1');
    final backups = await repository.listBackups();
    expect(backups, hasLength(1));
    expect(File(backup.path).existsSync(), isTrue);

    final importedBoard =
        await repository.importBackup(backupPath: backup.path);
    final importedSnapshot = await localStore.getBoard(importedBoard.boardId);
    final importedRecurring = importedSnapshot.items.firstWhere(
      (item) => item.title == 'Weekly review',
    );
    final importedParent = importedSnapshot.items.firstWhere(
      (item) => item.itemId == importedRecurring.parentId,
    );

    expect(importedSnapshot.board.name, 'My Board');
    expect(
      importedSnapshot.board.validationSettings.requireParentForTasks,
      isTrue,
    );
    expect(importedParent.title, 'Core board + hierarchy UX');
    expect(
      importedRecurring.recurrence?.missedWindowPolicy,
      WorkItemRecurrenceMissedWindowPolicy.singleStep,
    );
    expect(
      importedRecurring.recurrence?.rootItemId,
      importedRecurring.itemId,
    );
  });

  test('import throws format exception for malformed backup files', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('plandone_backup_test_bad');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final malformed = File('${tempDir.path}/broken.json')
      ..writeAsStringSync('[]');
    final repository = BoardBackupRepositoryImpl(
      localStore: InMemoryLocalBoardStore(currentUserId: 'user-1'),
      outboxQueue: InMemoryOutboxQueue(),
      currentUserId: 'user-1',
      directoryProvider: () async => tempDir,
    );

    expect(
      repository.importBackup(backupPath: malformed.path),
      throwsFormatException,
    );
  });
}
