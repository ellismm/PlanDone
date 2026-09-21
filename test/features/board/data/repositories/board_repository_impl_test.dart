import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/core/outbox/outbox_operation.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/data/repositories/board_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/board_failures.dart';
import 'package:plandone/src/features/board/domain/models/board_member.dart';
import 'package:plandone/src/features/board/domain/models/board_validation_settings.dart';
import 'package:plandone/src/features/board/domain/models/board_workflow_settings.dart';
import 'package:plandone/src/features/board/domain/models/column.dart';
import 'package:plandone/src/features/board/domain/models/work_item_recurrence.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  test(
      'createBoard writes local board first and enqueues deterministic sync op',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final board = await repository.createBoard('My Remote Board');

    final localBoards = await localStore.listBoards();
    expect(localBoards.any((b) => b.boardId == board.boardId), isTrue);

    final pending = await outboxQueue.listPending();
    final op = pending.last;
    expect(op.entity, 'board');
    expect(op.entityId, board.boardId);
    expect(op.payload['version'], OutboxOperation.currentPayloadVersion);
    expect(op.payload['boardId'], board.boardId);
    expect(op.payload['name'], 'My Remote Board');
  });

  test('cloud recovery queues board snapshots in dependency order', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'user-1',
    );

    final boardCount = await repository.enqueueOwnedBoardSnapshotsForSync();
    final pending = await outboxQueue.listPending();

    expect(boardCount, 1);
    expect(pending.first.entity, 'board');
    expect(pending.first.entityId, 'board-1');
    expect(pending.any((op) => op.entity == 'boardMember'), isTrue);
    expect(pending.any((op) => op.entity == 'column'), isTrue);
    expect(pending.any((op) => op.entity == 'workItem'), isTrue);
    for (var index = 1; index < pending.length; index++) {
      expect(
        pending[index].createdAt.isAfter(pending[index - 1].createdAt),
        isTrue,
      );
    }
  });

  test('createInboxCapture creates inbox item and enqueues create op',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.createInboxCapture(
      boardId: 'board-1',
      title: 'Capture this quickly',
      tags: const ['quick', 'triage'],
    );

    final snapshot = await localStore.getBoard('board-1');
    final captured = snapshot.items
        .where((item) => item.title == 'Capture this quickly')
        .single;
    expect(captured.isInbox, isTrue);
    expect(captured.tags, contains('quick'));

    final pending = await outboxQueue.listPending();
    final op = pending.last;
    expect(op.type, OutboxOperationType.create);
    expect(op.entity, 'workItem');
    expect(op.payload['isInbox'], isTrue);
  });

  test('triageInboxItem updates type/column/parent and clears inbox state',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.createInboxCapture(
      boardId: 'board-1',
      title: 'Inbox item to triage',
    );
    final before = await localStore.getBoard('board-1');
    final item =
        before.items.firstWhere((i) => i.title == 'Inbox item to triage');

    await repository.triageInboxItem(
      fromBoardId: 'board-1',
      itemId: item.itemId,
      toBoardId: 'board-1',
      toColumnId: 'c-doing',
      type: WorkItemType.action,
      parentId: 't-2',
    );

    final after = await localStore.getBoard('board-1');
    final triaged = after.items.firstWhere((i) => i.itemId == item.itemId);
    expect(triaged.isInbox, isFalse);
    expect(triaged.type, WorkItemType.action);
    expect(triaged.columnId, 'c-doing');
    expect(triaged.parentId, 't-2');

    final pending = await outboxQueue.listPending();
    final op = pending.last;
    expect(op.type, OutboxOperationType.update);
    expect(op.payload['isInbox'], isFalse);
    expect(op.payload['type'], WorkItemType.action.name);
  });

  test('owner can delete board when at least one board remains', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final board = await repository.createBoard('Delete Me');
    await repository.deleteBoard(boardId: board.boardId);

    final boards = await localStore.listBoards();
    expect(boards.any((entry) => entry.boardId == board.boardId), isFalse);

    final pending = await outboxQueue.listPending();
    final deleteOp = pending.last;
    expect(deleteOp.type, OutboxOperationType.delete);
    expect(deleteOp.entity, 'board');
    expect(deleteOp.entityId, board.boardId);
  });

  test('cannot delete the last remaining board', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    expect(
      () => repository.deleteBoard(boardId: 'board-1'),
      throwsA(isA<BoardValidationException>()),
    );
  });

  test('non-owner cannot delete board', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'owner-1');
    final outboxQueue = InMemoryOutboxQueue();
    final ownerRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'owner-1',
    );
    final board = await ownerRepository.createBoard('Shared');
    await ownerRepository.addMember(
      boardId: board.boardId,
      userId: 'member-1',
      role: BoardRole.member,
    );

    final memberRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'member-1',
    );

    expect(
      () => memberRepository.deleteBoard(boardId: board.boardId),
      throwsA(isA<BoardPermissionDeniedException>()),
    );
  });

  test('moveItem sets completedAt when moved into Done column', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.moveItem(
        boardId: 'board-1', itemId: 'w-1', toColumnId: 'c-done');

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((item) => item.itemId == 'w-1');
    expect(moved.columnId, 'c-done');
    expect(moved.completedAt, isNotNull);

    final pending = await outboxQueue.listPending();
    final moveOp = pending.last;
    expect(moveOp.entity, 'workItem');
    expect(moveOp.payload['version'], OutboxOperation.currentPayloadVersion);
    expect(moveOp.payload['boardId'], 'board-1');
    expect(moveOp.payload['itemId'], 'w-1');
    expect(moveOp.payload['toColumnId'], 'c-done');
    expect(moveOp.payload['columnId'], 'c-done');
    expect(moveOp.payload['completedAt'], isNotNull);
  });

  test('createItem persists extended metadata from create flow', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final created = await repository.createItem(
      boardId: 'board-1',
      title: 'Plan recurring work',
      type: WorkItemType.action,
      toColumnId: 'c-doing',
      parentId: 't-2',
      description: 'Capture richer create-time metadata.',
      targetEndAt: DateTime(2026, 4, 1),
      dueAt: DateTime(2026, 4, 2),
      tags: const ['create', 'metadata'],
      estimatedEffortMinutes: 30,
      actualEffortMinutes: 10,
      recurrence: const WorkItemRecurrence(
        rootItemId: '',
        cadence: WorkItemRecurrenceCadence.weekly,
        interval: 2,
        missedWindowPolicy: WorkItemRecurrenceMissedWindowPolicy.singleStep,
      ),
    );

    expect(created.description, 'Capture richer create-time metadata.');
    expect(created.startAt, isNotNull);
    expect(created.targetEndAt, DateTime(2026, 4, 1));
    expect(created.dueAt, DateTime(2026, 4, 2));
    expect(created.estimatedEffortMinutes, 30);
    expect(created.actualEffortMinutes, 10);
    expect(created.recurrence, isNotNull);
    expect(created.recurrence!.rootItemId, created.itemId);
    expect(created.tags, containsAll(const ['create', 'metadata']));

    final pending = await outboxQueue.listPending();
    final op = pending.last;
    expect(op.payload['description'], 'Capture richer create-time metadata.');
    expect(op.payload['actualEffortMinutes'], 10);
    expect(op.payload['recurrence'], isNotNull);
  });

  test('renaming done column does not break completion semantics', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.renameColumn(
      boardId: 'board-1',
      columnId: 'c-done',
      name: 'Finished',
    );

    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'a-3',
      toColumnId: 'c-done',
    );

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((item) => item.itemId == 'a-3');
    expect(moved.completedAt, isNotNull);
  });

  test('apply designated workflow template creates semantic columns', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.applyWorkflowTemplate(
      boardId: 'board-1',
      templateId: BoardWorkflowSettings.designatedTemplateId,
    );

    final snapshot = await localStore.getBoard('board-1');
    expect(snapshot.columns.any((c) => c.kind == BoardColumnKind.planning),
        isTrue);
    expect(snapshot.columns.any((c) => c.kind == BoardColumnKind.done), isTrue);
    expect(
      snapshot.board.workflowSettings.templateId,
      BoardWorkflowSettings.designatedTemplateId,
    );
  });

  test('createColumn blocked when workflow disallows custom columns', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final snapshot = await localStore.getBoard('board-1');
    await localStore.upsertBoard(
      snapshot.board.copyWith(
        workflowSettings:
            snapshot.board.workflowSettings.copyWith(allowCustomColumns: false),
      ),
    );

    expect(
      () => repository.createColumn(boardId: 'board-1', name: 'Custom'),
      throwsA(isA<BoardValidationException>()),
    );
  });

  test('updateColumnSemantics controls completion behavior', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.moveItem(
      boardId: 'board-1',
      itemId: 'a-3',
      toColumnId: 'c-doing',
    );

    await repository.updateColumnSemantics(
      boardId: 'board-1',
      columnId: 'c-doing',
      isDoneState: true,
    );

    var snapshot = await localStore.getBoard('board-1');
    expect(
      snapshot.items.firstWhere((item) => item.itemId == 'a-3').completedAt,
      isNotNull,
    );

    await repository.updateColumnSemantics(
      boardId: 'board-1',
      columnId: 'c-doing',
      isDoneState: false,
    );

    snapshot = await localStore.getBoard('board-1');
    expect(
      snapshot.items.firstWhere((item) => item.itemId == 'a-3').completedAt,
      isNull,
    );
  });

  test('moveItem clears completedAt when moved out of Done column', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.moveItem(
        boardId: 'board-1', itemId: 'w-1', toColumnId: 'c-done');
    await repository.moveItem(
        boardId: 'board-1', itemId: 'w-1', toColumnId: 'c-doing');

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

  test(
      'reorderItem can reposition and re-parent an item while persisting sort order',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.reorderItem(
      boardId: 'board-1',
      itemId: 'a-3',
      parentId: 't-3',
      beforeItemId: null,
      afterItemId: 'a-4',
    );

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((item) => item.itemId == 'a-3');
    final anchor = snapshot.items.firstWhere((item) => item.itemId == 'a-4');
    expect(moved.parentId, 't-3');
    expect(moved.sortOrder, lessThan(anchor.sortOrder));

    final pending = await outboxQueue.listPending();
    final reorderOp = pending.lastWhere((op) => op.entityId == 'a-3');
    expect(reorderOp.entity, 'workItem');
    expect(reorderOp.payload['sortOrder'], isA<num>());
    expect(reorderOp.payload['parentId'], 't-3');
  });

  test('updateItem updates editable fields and enqueues update outbox op',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

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
    expect(
        op.payload['title'], 'Add parent-child jump links and detail editing');
  });

  test('updateItem can clear parent, description, and due date', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

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
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
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
      () => viewerRepository.moveItem(
          boardId: 'board-1', itemId: 'a-3', toColumnId: 'c-done'),
      throwsA(isA<BoardPermissionDeniedException>()),
    );

    await ownerRepository.updateMemberRole(
      boardId: 'board-1',
      userId: 'user-viewer',
      role: BoardRole.member,
    );

    await viewerRepository.moveItem(
        boardId: 'board-1', itemId: 'a-3', toColumnId: 'c-done');

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((i) => i.itemId == 'a-3');
    expect(moved.columnId, 'c-done');
  });

  test('moveItemToBoard transfers item and enqueues create+delete outbox ops',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

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

  test('moveItemToBoard sets completedAt when moved into target Done column',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

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

  test('deleteColumn keeps completedAt aligned with fallback done status',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    // Ensure DONE becomes the fallback by removing DOING first.
    await repository.deleteColumn(boardId: 'board-1', columnId: 'c-doing');

    // Move item into TODO so deleting TODO will move it into DONE fallback.
    await repository.moveItem(
        boardId: 'board-1', itemId: 'a-3', toColumnId: 'c-todo');

    await repository.deleteColumn(boardId: 'board-1', columnId: 'c-todo');

    final snapshot = await localStore.getBoard('board-1');
    final moved = snapshot.items.firstWhere((i) => i.itemId == 'a-3');
    expect(moved.columnId, 'c-done');
    expect(moved.completedAt, isNotNull);
  });

  test('invite + accept flow transitions member from pending to active',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'owner-1');
    final outboxQueue = InMemoryOutboxQueue();
    final ownerRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'owner-1',
    );

    await ownerRepository.inviteMember(
      boardId: 'board-1',
      userId: 'user-invite',
      role: BoardRole.member,
    );

    var snapshot = await localStore.getBoard('board-1');
    final pending =
        snapshot.members.firstWhere((m) => m.userId == 'user-invite');
    expect(
      pending.joinedAt.millisecondsSinceEpoch,
      0,
      reason: 'Invite should be pending until accepted.',
    );

    final invitedRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'user-invite',
    );
    await invitedRepository.acceptInvite(boardId: 'board-1');

    snapshot = await localStore.getBoard('board-1');
    final active =
        snapshot.members.firstWhere((m) => m.userId == 'user-invite');
    expect(active.joinedAt.millisecondsSinceEpoch, greaterThan(0));
  });

  test('member cannot manage other members', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'owner-1');
    final outboxQueue = InMemoryOutboxQueue();
    final ownerRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'owner-1',
    );

    await ownerRepository.addMember(
      boardId: 'board-1',
      userId: 'user-member',
      role: BoardRole.member,
    );

    final memberRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'user-member',
    );

    expect(
      () => memberRepository.inviteMember(
        boardId: 'board-1',
        userId: 'user-third',
        role: BoardRole.viewer,
      ),
      throwsA(isA<BoardPermissionDeniedException>()),
    );
  });

  test('reparentItem updates parent linkage without mutating other fields',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final before = await localStore.getBoard('board-1');
    final original = before.items.firstWhere((item) => item.itemId == 'a-3');

    await repository.reparentItem(
      boardId: 'board-1',
      itemId: 'a-3',
      parentId: 't-2',
    );

    final after = await localStore.getBoard('board-1');
    final updated = after.items.firstWhere((item) => item.itemId == 'a-3');
    expect(updated.parentId, 't-2');
    expect(updated.title, original.title);
    expect(updated.columnId, original.columnId);
  });

  test('bulkUpdateItems moves, archives, and edits tags consistently',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.bulkUpdateItems(
      boardId: 'board-1',
      itemIds: const ['a-3', 'a-4'],
      toColumnId: 'c-done',
      archived: true,
      addTags: const ['phase6', 'bulk'],
      removeTags: const ['api'],
    );

    final snapshot = await localStore.getBoard('board-1');
    final a3 = snapshot.items.firstWhere((item) => item.itemId == 'a-3');
    final a4 = snapshot.items.firstWhere((item) => item.itemId == 'a-4');

    expect(a3.columnId, 'c-done');
    expect(a4.columnId, 'c-done');
    expect(a3.archived, isTrue);
    expect(a4.archived, isTrue);
    expect(a3.completedAt, isNotNull);
    expect(a4.completedAt, isNotNull);
    expect(a3.tags.contains('phase6'), isTrue);
    expect(a4.tags.contains('phase6'), isTrue);
    expect(a3.tags.contains('api'), isFalse);

    final pending = await outboxQueue.listPending();
    final bulkOps =
        pending.where((op) => op.entityId == 'a-3' || op.entityId == 'a-4');
    expect(bulkOps.length, greaterThanOrEqualTo(2));
  });

  test('board validation settings are configurable and enforced', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'owner-1');
    final outboxQueue = InMemoryOutboxQueue();
    final ownerRepository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'owner-1',
    );

    await ownerRepository.updateBoardValidationSettings(
      boardId: 'board-1',
      settings: const BoardValidationSettings(
        requireParentForActions: true,
      ),
    );

    expect(
      () => ownerRepository.createItem(
        boardId: 'board-1',
        title: 'Must fail without parent',
        type: WorkItemType.action,
        toColumnId: 'c-todo',
      ),
      throwsA(isA<BoardValidationException>()),
    );

    await ownerRepository.createItem(
      boardId: 'board-1',
      title: 'Child action',
      type: WorkItemType.action,
      parentId: 't-2',
      toColumnId: 'c-todo',
    );

    final snapshot = await localStore.getBoard('board-1');
    expect(snapshot.items.any((i) => i.title == 'Child action'), isTrue);
  });

  test('metadata required settings are enforced on update', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'owner-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository = BoardRepositoryImpl(
      localStore: localStore,
      outboxQueue: outboxQueue,
      currentUserId: 'owner-1',
    );

    await repository.updateBoardValidationSettings(
      boardId: 'board-1',
      settings: const BoardValidationSettings(
        requireEstimatedEffort: true,
      ),
    );

    expect(
      () => repository.updateItem(
        boardId: 'board-1',
        itemId: 'a-3',
        clearEstimatedEffort: true,
      ),
      throwsA(isA<BoardValidationException>()),
    );
  });

  test('updateItem persists extended metadata fields', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final startAt = DateTime(2026, 2, 20);
    final targetEndAt = DateTime(2026, 3, 5);
    final dueAt = DateTime(2026, 3, 2);
    await repository.updateItem(
      boardId: 'board-1',
      itemId: 'a-3',
      startAt: startAt,
      targetEndAt: targetEndAt,
      dueAt: dueAt,
      estimatedEffortMinutes: 180,
      actualEffortMinutes: 90,
    );

    final snapshot = await localStore.getBoard('board-1');
    final updated = snapshot.items.firstWhere((item) => item.itemId == 'a-3');
    expect(updated.startAt, startAt);
    expect(updated.targetEndAt, targetEndAt);
    expect(updated.dueAt, dueAt);
    expect(updated.estimatedEffortMinutes, 180);
    expect(updated.actualEffortMinutes, 90);
  });

  test('deleteItem removes item and enqueues delete operation', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    await repository.deleteItem(boardId: 'board-1', itemId: 'a-3');

    final snapshot = await localStore.getBoard('board-1');
    expect(snapshot.items.any((item) => item.itemId == 'a-3'), isFalse);

    final pending = await outboxQueue.listPending();
    final op = pending.last;
    expect(op.type, OutboxOperationType.delete);
    expect(op.entity, 'workItem');
    expect(op.entityId, 'a-3');
  });

  test('deleteItem rejects deleting an item with children', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    expect(
      () => repository.deleteItem(boardId: 'board-1', itemId: 't-2'),
      throwsA(isA<BoardValidationException>()),
    );
  });

  test('restoreItem recreates deleted item and enqueues create operation',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final outboxQueue = InMemoryOutboxQueue();
    final repository =
        BoardRepositoryImpl(localStore: localStore, outboxQueue: outboxQueue);

    final beforeDelete = await localStore.getBoard('board-1');
    final deleted =
        beforeDelete.items.firstWhere((item) => item.itemId == 'a-3');
    await repository.deleteItem(boardId: 'board-1', itemId: deleted.itemId);

    await repository.restoreItem(boardId: 'board-1', item: deleted);

    final snapshot = await localStore.getBoard('board-1');
    final restored = snapshot.items.firstWhere((item) => item.itemId == 'a-3');
    expect(restored.title, deleted.title);
    expect(restored.parentId, deleted.parentId);
    expect(restored.columnId, deleted.columnId);

    final pending = await outboxQueue.listPending();
    final createOp = pending.last;
    expect(createOp.type, OutboxOperationType.create);
    expect(createOp.entity, 'workItem');
    expect(createOp.entityId, 'a-3');
  });
}
