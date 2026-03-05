import 'dart:async';

import '../../domain/models/board.dart';
import '../../domain/models/board_member.dart';
import '../../domain/models/board_snapshot.dart';
import '../../domain/models/board_workflow_settings.dart';
import '../../domain/models/column.dart';
import '../../domain/models/work_item.dart';
import '../../domain/models/work_item_type.dart';
import '../../domain/policies/workflow_semantics_policy.dart';
import 'local_board_store.dart';

class InMemoryLocalBoardStore implements LocalBoardStore {
  InMemoryLocalBoardStore({required String currentUserId})
      : _currentUserId = currentUserId {
    final initialSnapshot = BoardSnapshot(
      board: Board(
        boardId: 'board-1',
        name: 'My Board',
        ownerId: _currentUserId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        workflowSettings: const BoardWorkflowSettings(
          templateId: BoardWorkflowSettings.legacyTemplateId,
        ),
      ),
      members: [
        BoardMember(
          boardId: 'board-1',
          userId: _currentUserId,
          role: BoardRole.owner,
          joinedAt: DateTime.now(),
        ),
      ],
      columns: WorkflowSemanticsPolicy.legacyDefaultColumns('board-1'),
      items: [
        WorkItem(
          itemId: 'g-1',
          boardId: 'board-1',
          title: 'Ship PlanDone MVP',
          type: WorkItemType.goal,
          columnId: 'c-doing',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'p-1',
          boardId: 'board-1',
          parentId: 'g-1',
          title: 'Core board + hierarchy UX',
          type: WorkItemType.project,
          columnId: 'c-doing',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'p-2',
          boardId: 'board-1',
          parentId: 'g-1',
          title: 'Offline + sync foundation',
          type: WorkItemType.project,
          columnId: 'c-todo',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 't-1',
          boardId: 'board-1',
          parentId: 'p-1',
          title: 'Create board page skeleton and state wiring',
          type: WorkItemType.task,
          columnId: 'c-done',
          completedAt: DateTime.now().subtract(const Duration(days: 1)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 't-2',
          boardId: 'board-1',
          parentId: 'p-1',
          title: 'Implement hierarchy and filtering behavior',
          type: WorkItemType.task,
          columnId: 'c-doing',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 't-3',
          boardId: 'board-1',
          parentId: 'p-2',
          title: 'Implement offline persistence with Drift',
          type: WorkItemType.task,
          columnId: 'c-todo',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 't-4',
          boardId: 'board-1',
          parentId: 'p-2',
          title: 'Build sync engine + outbox processing loop',
          type: WorkItemType.task,
          columnId: 'c-todo',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'w-1',
          boardId: 'board-1',
          parentId: 't-2',
          title:
              'Clarify type semantics in UI labels (Goal/Project/Task/Action)',
          type: WorkItemType.action,
          columnId: 'c-done',
          completedAt: DateTime.now().subtract(const Duration(hours: 8)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'a-2',
          boardId: 'board-1',
          parentId: 't-2',
          title: 'Default visibility filter to Action',
          type: WorkItemType.action,
          columnId: 'c-done',
          completedAt: DateTime.now().subtract(const Duration(hours: 6)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'a-3',
          boardId: 'board-1',
          parentId: 't-2',
          title: 'Add parent-child navigation in item cards',
          type: WorkItemType.action,
          columnId: 'c-doing',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'a-4',
          boardId: 'board-1',
          parentId: 't-3',
          title: 'Create Drift schema for boards/columns/items',
          type: WorkItemType.action,
          columnId: 'c-todo',
          dueAt: DateTime.now().add(const Duration(days: 2)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'a-5',
          boardId: 'board-1',
          parentId: 't-3',
          title: 'Write migration tests for local database',
          type: WorkItemType.action,
          columnId: 'c-todo',
          dueAt: DateTime.now().add(const Duration(days: 3)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'a-6',
          boardId: 'board-1',
          parentId: 't-4',
          title: 'Process outbox queue and mark operations processed',
          type: WorkItemType.action,
          columnId: 'c-todo',
          dueAt: DateTime.now().add(const Duration(days: 4)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        WorkItem(
          itemId: 'a-7',
          boardId: 'board-1',
          parentId: 't-4',
          title: 'Handle conflict strategy for server timestamp merges',
          type: WorkItemType.action,
          columnId: 'c-todo',
          dueAt: DateTime.now().add(const Duration(days: 5)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
    );

    _snapshots['board-1'] = initialSnapshot;
    _boardOrder.add('board-1');
  }

  final String _currentUserId;
  final Map<String, BoardSnapshot> _snapshots = {};
  final Map<String, StreamController<BoardSnapshot>> _controllers = {};
  final List<String> _boardOrder = [];

  StreamController<BoardSnapshot> _controllerFor(String boardId) {
    return _controllers.putIfAbsent(
        boardId, () => StreamController<BoardSnapshot>.broadcast());
  }

  BoardSnapshot _snapshotFor(String boardId) {
    final snapshot = _snapshots[boardId];
    if (snapshot == null) {
      throw StateError('Board not found: $boardId');
    }
    return snapshot;
  }

  @override
  Future<List<Board>> listBoards() async {
    return [for (final boardId in _boardOrder) _snapshotFor(boardId).board];
  }

  @override
  Future<Board> createBoard(String name) async {
    final now = DateTime.now();
    final boardId = 'board-${now.microsecondsSinceEpoch}';

    final board = Board(
      boardId: boardId,
      name: name,
      ownerId: _currentUserId,
      createdAt: now,
      updatedAt: now,
      workflowSettings: const BoardWorkflowSettings(
        templateId: BoardWorkflowSettings.legacyTemplateId,
      ),
    );

    final snapshot = BoardSnapshot(
      board: board,
      members: [
        BoardMember(
          boardId: boardId,
          userId: _currentUserId,
          role: BoardRole.owner,
          joinedAt: now,
        ),
      ],
      columns: WorkflowSemanticsPolicy.legacyDefaultColumns(boardId),
      items: const [],
    );

    _snapshots[boardId] = snapshot;
    _boardOrder.add(boardId);
    _controllerFor(boardId).add(snapshot);
    return board;
  }

  @override
  Future<void> upsertBoard(Board board) async {
    final existing = _snapshots[board.boardId];
    if (existing != null) {
      final updated = BoardSnapshot(
        board: board,
        members: existing.members,
        columns: existing.columns,
        items: existing.items,
      );
      _snapshots[board.boardId] = updated;
      _controllerFor(board.boardId).add(updated);
      return;
    }

    final snapshot = BoardSnapshot(
      board: board,
      members: [
        BoardMember(
          boardId: board.boardId,
          userId: board.ownerId,
          role: BoardRole.owner,
          joinedAt: board.createdAt,
        ),
      ],
      columns: const [],
      items: const [],
    );
    _snapshots[board.boardId] = snapshot;
    if (!_boardOrder.contains(board.boardId)) {
      _boardOrder.add(board.boardId);
    }
    _controllerFor(board.boardId).add(snapshot);
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    _snapshots.remove(boardId);
    _boardOrder.remove(boardId);
    await _controllers.remove(boardId)?.close();
  }

  @override
  Future<BoardSnapshot> getBoard(String boardId) async => _snapshotFor(boardId);

  @override
  Stream<BoardSnapshot> watchBoard(String boardId) async* {
    yield _snapshotFor(boardId);
    yield* _controllerFor(boardId).stream;
  }

  @override
  Future<void> upsertColumn(BoardColumn column) async {
    final normalizedColumn =
        WorkflowSemanticsPolicy.withLegacyInference(column);
    final snapshot = _snapshotFor(normalizedColumn.boardId);
    final existingIndex = snapshot.columns
        .indexWhere((c) => c.columnId == normalizedColumn.columnId);
    final updatedColumns = [...snapshot.columns];

    if (existingIndex >= 0) {
      updatedColumns[existingIndex] = normalizedColumn;
    } else {
      updatedColumns.add(normalizedColumn);
    }

    final updatedSnapshot = BoardSnapshot(
      board: snapshot.board,
      members: snapshot.members,
      columns: updatedColumns,
      items: snapshot.items,
    );
    _snapshots[normalizedColumn.boardId] = updatedSnapshot;
    _controllerFor(normalizedColumn.boardId).add(updatedSnapshot);
  }

  @override
  Future<void> deleteColumn({
    required String boardId,
    required String columnId,
  }) async {
    final snapshot = _snapshotFor(boardId);
    final remaining =
        snapshot.columns.where((c) => c.columnId != columnId).toList();

    final reindexed = [
      for (var i = 0; i < remaining.length; i++)
        remaining[i].copyWith(orderIndex: i),
    ];

    final updatedSnapshot = BoardSnapshot(
      board: snapshot.board,
      members: snapshot.members,
      columns: reindexed,
      items: snapshot.items,
    );
    _snapshots[boardId] = updatedSnapshot;
    _controllerFor(boardId).add(updatedSnapshot);
  }

  @override
  Future<void> reorderColumns({
    required String boardId,
    required List<String> orderedColumnIds,
  }) async {
    final snapshot = _snapshotFor(boardId);
    final byId = {for (final c in snapshot.columns) c.columnId: c};

    final ordered = <BoardColumn>[];
    for (final id in orderedColumnIds) {
      final column = byId[id];
      if (column != null) ordered.add(column);
    }
    for (final c in snapshot.columns) {
      if (!ordered.any((x) => x.columnId == c.columnId)) {
        ordered.add(c);
      }
    }

    final reindexed = [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(orderIndex: i),
    ];

    final updatedSnapshot = BoardSnapshot(
      board: snapshot.board,
      members: snapshot.members,
      columns: reindexed,
      items: snapshot.items,
    );
    _snapshots[boardId] = updatedSnapshot;
    _controllerFor(boardId).add(updatedSnapshot);
  }

  @override
  Future<void> upsertItem(WorkItem item) async {
    final snapshot = _snapshotFor(item.boardId);
    final existingIndex =
        snapshot.items.indexWhere((it) => it.itemId == item.itemId);
    final updatedItems = [...snapshot.items];

    if (existingIndex >= 0) {
      updatedItems[existingIndex] = item;
    } else {
      updatedItems.add(item);
    }

    final updatedSnapshot = BoardSnapshot(
      board: snapshot.board,
      members: snapshot.members,
      columns: snapshot.columns,
      items: updatedItems,
    );
    _snapshots[item.boardId] = updatedSnapshot;
    _controllerFor(item.boardId).add(updatedSnapshot);
  }

  @override
  Future<void> deleteItem(
      {required String boardId, required String itemId}) async {
    final snapshot = _snapshotFor(boardId);
    final updatedItems =
        snapshot.items.where((it) => it.itemId != itemId).toList();
    final updatedSnapshot = BoardSnapshot(
      board: snapshot.board,
      members: snapshot.members,
      columns: snapshot.columns,
      items: updatedItems,
    );
    _snapshots[boardId] = updatedSnapshot;
    _controllerFor(boardId).add(updatedSnapshot);
  }

  @override
  Future<void> upsertMember(BoardMember member) async {
    final snapshot = _snapshotFor(member.boardId);
    final existingIndex =
        snapshot.members.indexWhere((m) => m.userId == member.userId);
    final updatedMembers = [...snapshot.members];

    if (existingIndex >= 0) {
      updatedMembers[existingIndex] = member;
    } else {
      updatedMembers.add(member);
    }

    final updatedSnapshot = BoardSnapshot(
      board: snapshot.board,
      members: updatedMembers,
      columns: snapshot.columns,
      items: snapshot.items,
    );
    _snapshots[member.boardId] = updatedSnapshot;
    _controllerFor(member.boardId).add(updatedSnapshot);
  }

  @override
  Future<void> deleteMember(
      {required String boardId, required String userId}) async {
    final snapshot = _snapshotFor(boardId);
    final updatedMembers =
        snapshot.members.where((m) => m.userId != userId).toList();
    final updatedSnapshot = BoardSnapshot(
      board: snapshot.board,
      members: updatedMembers,
      columns: snapshot.columns,
      items: snapshot.items,
    );
    _snapshots[boardId] = updatedSnapshot;
    _controllerFor(boardId).add(updatedSnapshot);
  }
}
