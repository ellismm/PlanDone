import '../../../../core/outbox/outbox_operation.dart';
import '../../../../core/outbox/outbox_queue.dart';
import '../../domain/models/board.dart';
import '../../domain/models/board_member.dart';
import '../../domain/models/board_snapshot.dart';
import '../../domain/models/column.dart';
import '../../domain/models/work_item.dart';
import '../../domain/models/work_item_type.dart';
import '../../domain/repositories/board_repository.dart';
import '../local/local_board_store.dart';

class BoardRepositoryImpl implements BoardRepository {
  BoardRepositoryImpl({
    required LocalBoardStore localStore,
    required OutboxQueue outboxQueue,
    this.currentUserId = 'user-1',
  })  : _localStore = localStore,
        _outboxQueue = outboxQueue;

  final LocalBoardStore _localStore;
  final OutboxQueue _outboxQueue;
  final String currentUserId;

  String? _doneColumnId(BoardSnapshot snapshot) {
    return snapshot.columns
        .where((column) => column.name.toLowerCase() == 'done')
        .map((c) => c.columnId)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
  }

  Future<BoardRole?> _myRole(String boardId) async {
    final snapshot = await _localStore.getBoard(boardId);
    final member = snapshot.members.where((m) => m.userId == currentUserId).cast<BoardMember?>().firstWhere(
          (_) => true,
          orElse: () => null,
        );
    return member?.role;
  }

  Future<void> _requireItemEditor(String boardId) async {
    final role = await _myRole(boardId);
    if (role == BoardRole.member || role == BoardRole.admin || role == BoardRole.owner) return;
    throw BoardPermissionDeniedException('Current user cannot modify items in this board.');
  }

  Future<void> _requireBoardManager(String boardId) async {
    final role = await _myRole(boardId);
    if (role == BoardRole.admin || role == BoardRole.owner) return;
    throw BoardPermissionDeniedException('Current user cannot manage board settings/members.');
  }

  @override
  Future<List<Board>> listBoards() => _localStore.listBoards();

  @override
  Future<Board> createBoard(String name) => _localStore.createBoard(name);

  @override
  Stream<BoardSnapshot> watchBoard(String boardId) => _localStore.watchBoard(boardId);

  @override
  Future<void> addMember({
    required String boardId,
    required String userId,
    required BoardRole role,
  }) async {
    await _requireBoardManager(boardId);
    final now = DateTime.now();
    await _localStore.upsertMember(
      BoardMember(boardId: boardId, userId: userId, role: role, joinedAt: now),
    );
    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${now.microsecondsSinceEpoch}',
        type: OutboxOperationType.create,
        entity: 'boardMember',
        entityId: '$boardId:$userId',
        payload: {
          'boardId': boardId,
          'userId': userId,
          'role': role.name,
          'joinedAt': now.toIso8601String(),
        },
        createdAt: now,
      ),
    );
  }

  @override
  Future<void> updateMemberRole({
    required String boardId,
    required String userId,
    required BoardRole role,
  }) async {
    await _requireBoardManager(boardId);
    final snapshot = await _localStore.getBoard(boardId);
    final existing = snapshot.members.firstWhere((m) => m.userId == userId);
    final updated = BoardMember(
      boardId: existing.boardId,
      userId: existing.userId,
      role: role,
      joinedAt: existing.joinedAt,
    );
    await _localStore.upsertMember(updated);
    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: OutboxOperationType.update,
        entity: 'boardMember',
        entityId: '$boardId:$userId',
        payload: {
          'boardId': boardId,
          'userId': userId,
          'role': role.name,
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> removeMember({
    required String boardId,
    required String userId,
  }) async {
    await _requireBoardManager(boardId);
    await _localStore.deleteMember(boardId: boardId, userId: userId);
    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: OutboxOperationType.delete,
        entity: 'boardMember',
        entityId: '$boardId:$userId',
        payload: {
          'boardId': boardId,
          'userId': userId,
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> createColumn({
    required String boardId,
    required String name,
  }) async {
    await _requireBoardManager(boardId);
    final snapshot = await _localStore.getBoard(boardId);
    final nextOrder = snapshot.columns.isEmpty
        ? 0
        : snapshot.columns.map((c) => c.orderIndex).reduce((a, b) => a > b ? a : b) + 1;
    final now = DateTime.now();
    final columnId = 'c-${now.microsecondsSinceEpoch}';

    final column = BoardColumn(
      columnId: columnId,
      boardId: boardId,
      name: name,
      orderIndex: nextOrder,
    );

    await _localStore.upsertColumn(column);

    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${now.microsecondsSinceEpoch}',
        type: OutboxOperationType.create,
        entity: 'column',
        entityId: columnId,
        payload: {
          'boardId': boardId,
          'columnId': columnId,
          'name': name,
          'orderIndex': nextOrder,
        },
        createdAt: now,
      ),
    );
  }

  @override
  Future<void> renameColumn({
    required String boardId,
    required String columnId,
    required String name,
  }) async {
    await _requireBoardManager(boardId);
    final snapshot = await _localStore.getBoard(boardId);
    final existing = snapshot.columns.firstWhere((c) => c.columnId == columnId);
    final updated = BoardColumn(
      columnId: existing.columnId,
      boardId: existing.boardId,
      name: name,
      orderIndex: existing.orderIndex,
    );

    await _localStore.upsertColumn(updated);

    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: OutboxOperationType.update,
        entity: 'column',
        entityId: columnId,
        payload: {
          'boardId': boardId,
          'columnId': columnId,
          'name': name,
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> deleteColumn({
    required String boardId,
    required String columnId,
  }) async {
    await _requireBoardManager(boardId);
    final snapshot = await _localStore.getBoard(boardId);
    if (snapshot.columns.length <= 1) return;

    final fallbackColumn = snapshot.columns.firstWhere((c) => c.columnId != columnId);
    final itemsToMove = snapshot.items.where((item) => item.columnId == columnId).toList();

    final doneColumnId = _doneColumnId(snapshot);

    for (final item in itemsToMove) {
      final updated = item.copyWith(columnId: fallbackColumn.columnId, updatedAt: DateTime.now());
      final shouldBeCompleted = fallbackColumn.columnId == doneColumnId;
      final updatedWithCompletion = updated.copyWith(
        completedAt: shouldBeCompleted ? DateTime.now() : null,
      );
      await _localStore.upsertItem(updatedWithCompletion);
      await _outboxQueue.enqueue(
        OutboxOperation(
          id: 'op-${DateTime.now().microsecondsSinceEpoch}',
          type: OutboxOperationType.move,
          entity: 'workItem',
          entityId: item.itemId,
          payload: {
            'boardId': boardId,
            'itemId': item.itemId,
            'toColumnId': fallbackColumn.columnId,
            'updatedAt': updatedWithCompletion.updatedAt.toIso8601String(),
            'completedAt': updatedWithCompletion.completedAt?.toIso8601String(),
          },
          createdAt: DateTime.now(),
        ),
      );
    }

    await _localStore.deleteColumn(boardId: boardId, columnId: columnId);
    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: OutboxOperationType.delete,
        entity: 'column',
        entityId: columnId,
        payload: {
          'boardId': boardId,
          'columnId': columnId,
          'fallbackColumnId': fallbackColumn.columnId,
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> reorderColumns({
    required String boardId,
    required List<String> orderedColumnIds,
  }) async {
    await _requireBoardManager(boardId);
    await _localStore.reorderColumns(boardId: boardId, orderedColumnIds: orderedColumnIds);
    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: OutboxOperationType.reorder,
        entity: 'column',
        entityId: boardId,
        payload: {
          'boardId': boardId,
          'orderedColumnIds': orderedColumnIds,
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> createItem({
    required String boardId,
    required String title,
    required WorkItemType type,
    required String toColumnId,
    String? parentId,
  }) async {
    await _requireItemEditor(boardId);
    final now = DateTime.now();
    final itemId = 'w-${now.microsecondsSinceEpoch}';

    final item = WorkItem(
      itemId: itemId,
      boardId: boardId,
      title: title,
      type: type,
      parentId: parentId,
      columnId: toColumnId,
      createdAt: now,
      updatedAt: now,
    );

    await _localStore.upsertItem(item);

    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${now.microsecondsSinceEpoch}',
        type: OutboxOperationType.create,
        entity: 'workItem',
        entityId: itemId,
        payload: {
          'boardId': boardId,
          'itemId': itemId,
          'title': title,
          'type': item.type.name,
          'parentId': parentId,
          'toColumnId': toColumnId,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
        createdAt: now,
      ),
    );
  }

  @override
  Future<void> createTask({
    required String boardId,
    required String title,
    required String toColumnId,
  }) async {
    await createItem(
      boardId: boardId,
      title: title,
      type: WorkItemType.task,
      toColumnId: toColumnId,
    );
  }

  @override
  Future<void> moveItem({
    required String boardId,
    required String itemId,
    required String toColumnId,
  }) async {
    await _requireItemEditor(boardId);
    final snapshot = await _localStore.getBoard(boardId);
    final existing = snapshot.items.firstWhere((item) => item.itemId == itemId);
    final doneColumn = _doneColumnId(snapshot);

    final updated = existing.copyWith(
      columnId: toColumnId,
      completedAt: doneColumn == toColumnId ? DateTime.now() : null,
      updatedAt: DateTime.now(),
    );

    await _localStore.upsertItem(updated);

    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: OutboxOperationType.move,
        entity: 'workItem',
        entityId: itemId,
        payload: {
          'boardId': boardId,
          'itemId': itemId,
          'toColumnId': toColumnId,
          'updatedAt': updated.updatedAt.toIso8601String(),
          'completedAt': updated.completedAt?.toIso8601String(),
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> moveItemToBoard({
    required String fromBoardId,
    required String itemId,
    required String toBoardId,
    required String toColumnId,
  }) async {
    if (fromBoardId == toBoardId) {
      await moveItem(boardId: fromBoardId, itemId: itemId, toColumnId: toColumnId);
      return;
    }

    await _requireItemEditor(fromBoardId);
    await _requireItemEditor(toBoardId);

    final sourceSnapshot = await _localStore.getBoard(fromBoardId);
    final targetSnapshot = await _localStore.getBoard(toBoardId);
    final item = sourceSnapshot.items.firstWhere((it) => it.itemId == itemId);
    final now = DateTime.now();
    final targetDoneColumnId = _doneColumnId(targetSnapshot);

    final moved = WorkItem(
      itemId: item.itemId,
      boardId: toBoardId,
      title: item.title,
      type: item.type,
      parentId: item.parentId,
      columnId: toColumnId,
      description: item.description,
      assigneeIds: item.assigneeIds,
      startAt: item.startAt,
      dueAt: item.dueAt,
      completedAt: toColumnId == targetDoneColumnId ? now : null,
      tags: item.tags,
      archived: item.archived,
      createdAt: item.createdAt,
      updatedAt: now,
    );

    await _localStore.upsertItem(moved);
    await _localStore.deleteItem(boardId: fromBoardId, itemId: itemId);

    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${now.microsecondsSinceEpoch}',
        type: OutboxOperationType.create,
        entity: 'workItem',
        entityId: itemId,
        payload: {
          'boardId': toBoardId,
          'itemId': itemId,
          'title': moved.title,
          'type': moved.type.name,
          'parentId': moved.parentId,
          'toColumnId': toColumnId,
          'createdAt': moved.createdAt.toIso8601String(),
          'updatedAt': moved.updatedAt.toIso8601String(),
        },
        createdAt: now,
      ),
    );

    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: OutboxOperationType.delete,
        entity: 'workItem',
        entityId: itemId,
        payload: {
          'boardId': fromBoardId,
          'itemId': itemId,
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateItem({
    required String boardId,
    required String itemId,
    String? title,
    String? description,
    String? parentId,
    DateTime? dueAt,
    List<String>? tags,
    bool? archived,
    bool clearParent = false,
    bool clearDescription = false,
    bool clearDueAt = false,
  }) async {
    await _requireItemEditor(boardId);
    final snapshot = await _localStore.getBoard(boardId);
    final existing = snapshot.items.firstWhere((item) => item.itemId == itemId);

    final updated = existing.copyWith(
      title: title,
      description: description,
      parentId: parentId,
      dueAt: dueAt,
      tags: tags,
      archived: archived,
      clearParent: clearParent,
      clearDescription: clearDescription,
      clearDueAt: clearDueAt,
      updatedAt: DateTime.now(),
    );

    await _localStore.upsertItem(updated);

    await _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${DateTime.now().microsecondsSinceEpoch}',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: itemId,
        payload: {
          'boardId': boardId,
          'itemId': itemId,
          'title': updated.title,
          'description': updated.description,
          'parentId': updated.parentId,
          'dueAt': updated.dueAt?.toIso8601String(),
          'tags': updated.tags,
          'archived': updated.archived,
          'updatedAt': updated.updatedAt.toIso8601String(),
        },
        createdAt: DateTime.now(),
      ),
    );
  }
}

class BoardPermissionDeniedException implements Exception {
  BoardPermissionDeniedException(this.message);

  final String message;

  @override
  String toString() => 'BoardPermissionDeniedException: $message';
}
