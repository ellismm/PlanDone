import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../../domain/models/board.dart' as domain;
import '../../../domain/models/board_member.dart';
import '../../../domain/models/board_snapshot.dart';
import '../../../domain/models/board_validation_settings.dart';
import '../../../domain/models/board_workflow_settings.dart';
import '../../../domain/models/column.dart' as domain;
import '../../../domain/models/work_item.dart' as domain;
import '../../../domain/models/work_item_recurrence.dart';
import '../../../domain/models/work_item_type.dart';
import '../../../domain/policies/workflow_semantics_policy.dart';
import '../local_board_store.dart';
import 'board_database.dart' hide BoardMember;

class DriftLocalBoardStore implements LocalBoardStore {
  DriftLocalBoardStore({
    BoardDatabase? database,
    required String currentUserId,
  })  : _db = database ?? BoardDatabase(),
        _currentUserId = currentUserId;

  final BoardDatabase _db;
  final String _currentUserId;
  bool _seeded = false;
  Future<void>? _seedInFlight;

  Future<void> _ensureSeeded() async {
    if (_seeded) return;
    final inFlight = _seedInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final seedFuture = _seedDefaults();
    _seedInFlight = seedFuture;
    try {
      await seedFuture;
    } finally {
      _seedInFlight = null;
    }
  }

  Future<void> _seedDefaults() async {
    final existing = await (_db.select(_db.boards)..limit(1)).getSingleOrNull();
    if (existing != null) {
      _seeded = true;
      return;
    }

    final now = DateTime.now();
    final board = domain.Board(
      boardId: 'board-1',
      name: 'My Board',
      ownerId: _currentUserId,
      createdAt: now,
      updatedAt: now,
      workflowSettings: const BoardWorkflowSettings(
        templateId: BoardWorkflowSettings.legacyTemplateId,
      ),
    );

    await _db.into(_db.boards).insertOnConflictUpdate(
          BoardsCompanion.insert(
            boardId: board.boardId,
            name: board.name,
            ownerId: board.ownerId,
            createdAt: board.createdAt.millisecondsSinceEpoch,
            updatedAt: board.updatedAt.millisecondsSinceEpoch,
            validationSettingsJson:
                drift.Value(jsonEncode(board.validationSettings.toMap())),
            workflowSettingsJson:
                drift.Value(jsonEncode(board.workflowSettings.toMap())),
          ),
        );

    await _db.into(_db.boardMembers).insertOnConflictUpdate(
          BoardMembersCompanion.insert(
            boardId: board.boardId,
            userId: board.ownerId,
            role: BoardRole.owner.name,
            joinedAt: board.createdAt.millisecondsSinceEpoch,
            joinedAtEpochMillis:
                drift.Value(board.createdAt.millisecondsSinceEpoch),
          ),
        );

    final columns = WorkflowSemanticsPolicy.legacyDefaultColumns('board-1');
    for (final column in columns) {
      await _db.into(_db.boardColumns).insertOnConflictUpdate(
            BoardColumnsCompanion.insert(
              columnId: column.columnId,
              boardId: column.boardId,
              name: column.name,
              orderIndex: column.orderIndex,
              kind: drift.Value(column.kind.name),
              isDoneState: drift.Value(column.isDoneState),
              isBlockedState: drift.Value(column.isBlockedState),
              isCancelledState: drift.Value(column.isCancelledState),
              isDesignated: drift.Value(column.isDesignated),
              isEnabled: drift.Value(column.isEnabled),
            ),
          );
    }

    final items = [
      domain.WorkItem(
        itemId: 'g-1',
        boardId: 'board-1',
        title: 'Ship PlanDone MVP',
        type: WorkItemType.goal,
        columnId: 'c-doing',
        createdAt: now,
        updatedAt: now,
      ),
      domain.WorkItem(
        itemId: 'p-1',
        boardId: 'board-1',
        parentId: 'g-1',
        title: 'Core board + hierarchy UX',
        type: WorkItemType.project,
        columnId: 'c-doing',
        createdAt: now,
        updatedAt: now,
      ),
      domain.WorkItem(
        itemId: 'p-2',
        boardId: 'board-1',
        parentId: 'g-1',
        title: 'Offline + sync foundation',
        type: WorkItemType.project,
        columnId: 'c-todo',
        createdAt: now,
        updatedAt: now,
      ),
      domain.WorkItem(
        itemId: 't-2',
        boardId: 'board-1',
        parentId: 'p-1',
        title: 'Implement hierarchy and filtering behavior',
        type: WorkItemType.task,
        columnId: 'c-doing',
        createdAt: now,
        updatedAt: now,
      ),
      domain.WorkItem(
        itemId: 'a-3',
        boardId: 'board-1',
        parentId: 't-2',
        title: 'Add parent-child navigation in item cards',
        type: WorkItemType.action,
        columnId: 'c-doing',
        createdAt: now,
        updatedAt: now,
      ),
      domain.WorkItem(
        itemId: 'a-4',
        boardId: 'board-1',
        parentId: 'p-2',
        title: 'Create Drift schema for boards/columns/items',
        type: WorkItemType.action,
        columnId: 'c-todo',
        dueAt: now.add(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
      ),
    ];

    for (final item in items) {
      await _upsertItemInternal(item);
    }

    _seeded = true;
  }

  @override
  Future<List<domain.Board>> listBoards() async {
    await _ensureSeeded();
    final rows = await _db.select(_db.boards).get();
    return rows.map(_toBoard).toList();
  }

  @override
  Future<domain.Board> createBoard(String name) async {
    await _ensureSeeded();
    final now = DateTime.now();
    final boardId = 'board-${now.microsecondsSinceEpoch}';
    final board = domain.Board(
      boardId: boardId,
      name: name,
      ownerId: _currentUserId,
      createdAt: now,
      updatedAt: now,
      workflowSettings: const BoardWorkflowSettings(
        templateId: BoardWorkflowSettings.legacyTemplateId,
      ),
    );

    await _db.into(_db.boards).insert(
          BoardsCompanion.insert(
            boardId: board.boardId,
            name: board.name,
            ownerId: board.ownerId,
            createdAt: board.createdAt.millisecondsSinceEpoch,
            updatedAt: board.updatedAt.millisecondsSinceEpoch,
            validationSettingsJson:
                drift.Value(jsonEncode(board.validationSettings.toMap())),
            workflowSettingsJson:
                drift.Value(jsonEncode(board.workflowSettings.toMap())),
          ),
        );

    await _db.into(_db.boardMembers).insert(
          BoardMembersCompanion.insert(
            boardId: board.boardId,
            userId: board.ownerId,
            role: BoardRole.owner.name,
            joinedAt: board.createdAt.millisecondsSinceEpoch,
            joinedAtEpochMillis:
                drift.Value(board.createdAt.millisecondsSinceEpoch),
          ),
        );

    final defaults = WorkflowSemanticsPolicy.legacyDefaultColumns(boardId);
    for (final column in defaults) {
      await upsertColumn(column);
    }

    return board;
  }

  @override
  Future<void> upsertBoard(domain.Board board) async {
    await _ensureSeeded();
    await _db.into(_db.boards).insertOnConflictUpdate(
          BoardsCompanion.insert(
            boardId: board.boardId,
            name: board.name,
            ownerId: board.ownerId,
            createdAt: board.createdAt.millisecondsSinceEpoch,
            updatedAt: board.updatedAt.millisecondsSinceEpoch,
            validationSettingsJson:
                drift.Value(jsonEncode(board.validationSettings.toMap())),
            workflowSettingsJson:
                drift.Value(jsonEncode(board.workflowSettings.toMap())),
          ),
        );
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    await _ensureSeeded();
    await _db.customStatement(
      'DELETE FROM work_items WHERE board_id = ?',
      [boardId],
    );
    await _db.customStatement(
      'DELETE FROM board_columns WHERE board_id = ?',
      [boardId],
    );
    await _db.customStatement(
      'DELETE FROM board_members WHERE board_id = ?',
      [boardId],
    );
    await _db.customStatement(
      'DELETE FROM boards WHERE board_id = ?',
      [boardId],
    );
  }

  @override
  Stream<BoardSnapshot> watchBoard(String boardId) async* {
    await _ensureSeeded();
    yield await getBoard(boardId);

    final trigger = _db.customSelect(
      'SELECT board_id FROM boards WHERE board_id = ?',
      variables: [drift.Variable.withString(boardId)],
      readsFrom: {
        _db.boards,
        _db.boardColumns,
        _db.boardMembers,
        _db.workItems
      },
    );

    yield* trigger.watch().asyncMap((_) => getBoard(boardId));
  }

  @override
  Future<BoardSnapshot> getBoard(String boardId) async {
    await _ensureSeeded();
    final boardRow = await (_db.select(_db.boards)
          ..where((t) => t.boardId.equals(boardId)))
        .getSingle();
    final columnRows = await (_db.select(_db.boardColumns)
          ..where((t) => t.boardId.equals(boardId)))
        .get();
    final memberRows = await (_db.select(_db.boardMembers)
          ..where((t) => t.boardId.equals(boardId)))
        .get();
    final itemRows = await (_db.select(_db.workItems)
          ..where((t) => t.boardId.equals(boardId)))
        .get();

    return BoardSnapshot(
      board: _toBoard(boardRow),
      members: memberRows.map(_toBoardMember).toList(),
      columns: columnRows.map(_toColumn).toList(),
      items: itemRows.map(_toWorkItem).toList(),
    );
  }

  @override
  Future<void> upsertColumn(domain.BoardColumn column) async {
    await _ensureSeeded();
    final normalizedColumn =
        WorkflowSemanticsPolicy.withLegacyInference(column);
    await _db.into(_db.boardColumns).insertOnConflictUpdate(
          BoardColumnsCompanion.insert(
            columnId: normalizedColumn.columnId,
            boardId: normalizedColumn.boardId,
            name: normalizedColumn.name,
            orderIndex: normalizedColumn.orderIndex,
            kind: drift.Value(normalizedColumn.kind.name),
            isDoneState: drift.Value(normalizedColumn.isDoneState),
            isBlockedState: drift.Value(normalizedColumn.isBlockedState),
            isCancelledState: drift.Value(normalizedColumn.isCancelledState),
            isDesignated: drift.Value(normalizedColumn.isDesignated),
            isEnabled: drift.Value(normalizedColumn.isEnabled),
          ),
        );
  }

  @override
  Future<void> deleteColumn(
      {required String boardId, required String columnId}) async {
    await _ensureSeeded();
    await _db.customStatement(
      'DELETE FROM board_columns WHERE board_id = ? AND column_id = ?',
      [boardId, columnId],
    );
  }

  @override
  Future<void> reorderColumns(
      {required String boardId, required List<String> orderedColumnIds}) async {
    await _ensureSeeded();
    for (var index = 0; index < orderedColumnIds.length; index++) {
      final id = orderedColumnIds[index];
      await (_db.update(_db.boardColumns)
            ..where((t) => t.boardId.equals(boardId))
            ..where((t) => t.columnId.equals(id)))
          .write(
        BoardColumnsCompanion(orderIndex: drift.Value(index)),
      );
    }
  }

  @override
  Future<void> upsertMember(BoardMember member) async {
    await _ensureSeeded();
    await _db.into(_db.boardMembers).insertOnConflictUpdate(
          BoardMembersCompanion.insert(
            boardId: member.boardId,
            userId: member.userId,
            role: member.role.name,
            joinedAt: member.joinedAt.millisecondsSinceEpoch,
            joinedAtEpochMillis:
                drift.Value(member.joinedAt.millisecondsSinceEpoch),
          ),
        );
  }

  @override
  Future<void> deleteMember(
      {required String boardId, required String userId}) async {
    await _ensureSeeded();
    await (_db.delete(_db.boardMembers)
          ..where((t) => t.boardId.equals(boardId))
          ..where((t) => t.userId.equals(userId)))
        .go();
  }

  @override
  Future<void> upsertItem(domain.WorkItem item) async {
    await _ensureSeeded();
    await _upsertItemInternal(item);
  }

  @override
  Future<void> deleteItem(
      {required String boardId, required String itemId}) async {
    await _ensureSeeded();
    await (_db.delete(_db.workItems)
          ..where((t) => t.boardId.equals(boardId))
          ..where((t) => t.itemId.equals(itemId)))
        .go();
  }

  Future<void> _upsertItemInternal(domain.WorkItem item) async {
    final assigneePayload = <String, Object?>{
      'assigneeIds': item.assigneeIds,
      'recurrence': item.recurrence?.toMap(),
    };
    await _db.into(_db.workItems).insertOnConflictUpdate(
          WorkItemsCompanion.insert(
            itemId: item.itemId,
            boardId: item.boardId,
            title: item.title,
            type: item.type.name,
            sortOrder: drift.Value(item.sortOrder),
            columnId: item.columnId,
            createdAt: item.createdAt.millisecondsSinceEpoch,
            updatedAt: item.updatedAt.millisecondsSinceEpoch,
            parentId: drift.Value(item.parentId),
            description: drift.Value(item.description),
            assigneeIdsJson: drift.Value(jsonEncode(assigneePayload)),
            startAt: drift.Value(item.startAt?.millisecondsSinceEpoch),
            targetEndAt: drift.Value(item.targetEndAt?.millisecondsSinceEpoch),
            dueAt: drift.Value(item.dueAt?.millisecondsSinceEpoch),
            completedAt: drift.Value(item.completedAt?.millisecondsSinceEpoch),
            estimatedEffortMinutes: drift.Value(item.estimatedEffortMinutes),
            actualEffortMinutes: drift.Value(item.actualEffortMinutes),
            tagsJson: drift.Value(jsonEncode(item.tags)),
            archived: drift.Value(item.archived),
            isInbox: drift.Value(item.isInbox),
          ),
        );
  }

  domain.Board _toBoard(dynamic row) => domain.Board(
        boardId: row.boardId,
        name: row.name,
        ownerId: row.ownerId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
        validationSettings: BoardValidationSettings.fromMap(
          (jsonDecode(row.validationSettingsJson as String)
                  as Map<String, dynamic>)
              .cast<String, Object?>(),
        ),
        workflowSettings: BoardWorkflowSettings.fromMap(
          (jsonDecode(row.workflowSettingsJson as String)
                  as Map<String, dynamic>)
              .cast<String, Object?>(),
        ),
      );

  domain.BoardColumn _toColumn(dynamic row) => domain.BoardColumn(
        columnId: row.columnId,
        boardId: row.boardId,
        name: row.name,
        orderIndex: row.orderIndex,
        kind: domain.boardColumnKindFromName(row.kind as String?),
        isDoneState: row.isDoneState == true,
        isBlockedState: row.isBlockedState == true,
        isCancelledState: row.isCancelledState == true,
        isDesignated: row.isDesignated == true,
        isEnabled: row.isEnabled != false,
      );

  BoardMember _toBoardMember(dynamic row) => BoardMember(
        boardId: row.boardId,
        userId: row.userId,
        role: BoardRole.values.firstWhere(
          (r) => r.name == row.role,
          orElse: () => BoardRole.member,
        ),
        joinedAt: DateTime.fromMillisecondsSinceEpoch(
          (row.joinedAtEpochMillis as int?) != null &&
                  (row.joinedAtEpochMillis as int) > 0
              ? row.joinedAtEpochMillis as int
              : row.joinedAt as int,
        ),
      );

  domain.WorkItem _toWorkItem(dynamic row) => domain.WorkItem(
        itemId: row.itemId,
        boardId: row.boardId,
        title: row.title,
        type: WorkItemType.values.firstWhere(
          (t) => t.name == row.type,
          orElse: () => WorkItemType.task,
        ),
        sortOrder: (row.sortOrder as num?)?.toDouble() ?? 0,
        parentId: row.parentId,
        columnId: row.columnId,
        description: row.description,
        assigneeIds: switch (jsonDecode(row.assigneeIdsJson)) {
          final Map payload => ((payload['assigneeIds'] as List?) ?? const [])
              .whereType<String>()
              .toList(),
          final List values => values.whereType<String>().toList(),
          _ => const <String>[],
        },
        startAt: row.startAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.startAt!),
        targetEndAt: row.targetEndAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.targetEndAt!),
        dueAt: row.dueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.dueAt!),
        completedAt: row.completedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.completedAt!),
        estimatedEffortMinutes: row.estimatedEffortMinutes as int?,
        actualEffortMinutes: row.actualEffortMinutes as int?,
        recurrence: switch (jsonDecode(row.assigneeIdsJson)) {
          final Map payload => WorkItemRecurrence.fromMap(
              (payload['recurrence'] as Map?)?.cast<String, Object?>(),
            ),
          _ => null,
        },
        tags: (jsonDecode(row.tagsJson) as List).cast<String>(),
        archived: row.archived,
        isInbox: row.isInbox,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      );
}
