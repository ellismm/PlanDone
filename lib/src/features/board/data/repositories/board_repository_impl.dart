import '../../../../core/outbox/outbox_operation.dart';
import '../../../../core/outbox/outbox_queue.dart';
import '../../domain/models/board.dart';
import '../../domain/models/board_failures.dart';
import '../../domain/models/board_member.dart';
import '../../domain/models/board_snapshot.dart';
import '../../domain/models/board_validation_settings.dart';
import '../../domain/models/board_workflow_settings.dart';
import '../../domain/models/column.dart';
import '../../domain/models/work_item.dart';
import '../../domain/models/work_item_recurrence.dart';
import '../../domain/models/work_item_activity_event.dart';
import '../../domain/models/work_item_type.dart';
import '../../domain/policies/board_permissions.dart';
import '../../domain/policies/board_validation_policy.dart';
import '../../domain/policies/workflow_semantics_policy.dart';
import '../../domain/repositories/board_repository.dart';
import '../../domain/repositories/work_item_activity_repository.dart';
import '../local/local_board_store.dart';
import 'in_memory/work_item_activity_repository_in_memory.dart';

class BoardRepositoryImpl implements BoardRepository {
  static const double _itemSortOrderStep = 1024;

  BoardRepositoryImpl({
    required LocalBoardStore localStore,
    required OutboxQueue outboxQueue,
    WorkItemActivityRepository? activityRepository,
    this.currentUserId = 'user-1',
  })  : _localStore = localStore,
        _outboxQueue = outboxQueue,
        _activityRepository =
            activityRepository ?? InMemoryWorkItemActivityRepository();

  final LocalBoardStore _localStore;
  final OutboxQueue _outboxQueue;
  final WorkItemActivityRepository _activityRepository;
  final String currentUserId;

  String _sanitizeForId(String raw) {
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  List<String> _mergeTags({
    required List<String> existing,
    required List<String> add,
    required List<String> remove,
  }) {
    final normalized = <String>[];
    for (final tag in existing) {
      final next = tag.trim();
      if (next.isEmpty || normalized.contains(next)) continue;
      normalized.add(next);
    }
    for (final tag in add) {
      final next = tag.trim();
      if (next.isEmpty || normalized.contains(next)) continue;
      normalized.add(next);
    }
    if (remove.isEmpty) return normalized;
    final removeSet = remove.map((t) => t.trim()).where((t) => t.isNotEmpty);
    return normalized.where((tag) => !removeSet.contains(tag)).toList();
  }

  List<String> _normalizeTags(List<String> tags) {
    final normalized = <String>[];
    for (final tag in tags) {
      final next = tag.trim();
      if (next.isEmpty || normalized.contains(next)) continue;
      normalized.add(next);
    }
    return normalized;
  }

  String _operationId({
    required DateTime createdAt,
    required OutboxOperationType type,
    required String entity,
    required String entityId,
  }) {
    return 'op-${createdAt.microsecondsSinceEpoch}-${type.name}-$entity-${_sanitizeForId(entityId)}';
  }

  String _activityEventId({
    required DateTime createdAt,
    required WorkItemActivityType type,
    required String itemId,
  }) {
    return 'evt-${createdAt.microsecondsSinceEpoch}-${type.name}-${_sanitizeForId(itemId)}';
  }

  Future<void> _recordActivity({
    required String boardId,
    required String itemId,
    required WorkItemActivityType type,
    required DateTime at,
    Map<String, Object?> payload = const {},
  }) {
    return _activityRepository.append(
      WorkItemActivityEvent(
        eventId: _activityEventId(createdAt: at, type: type, itemId: itemId),
        boardId: boardId,
        itemId: itemId,
        type: type,
        actorUserId: currentUserId,
        createdAt: at,
        payload: payload,
      ),
    );
  }

  Map<String, Object?> _withPayloadContract({
    required String boardId,
    required Map<String, Object?> payload,
  }) {
    return <String, Object?>{
      'version': OutboxOperation.currentPayloadVersion,
      'boardId': boardId,
      'actorUserId': currentUserId,
      ...payload,
    };
  }

  Map<String, Object?> _boardPayload(Board board) {
    return {
      'name': board.name,
      'ownerId': board.ownerId,
      'createdAt': board.createdAt.toIso8601String(),
      'updatedAt': board.updatedAt.toIso8601String(),
      'validationSettings': board.validationSettings.toMap(),
      'workflowSettings': board.workflowSettings.toMap(),
    };
  }

  Map<String, Object?> _columnPayload(BoardColumn column) {
    return {
      'columnId': column.columnId,
      'name': column.name,
      'orderIndex': column.orderIndex,
      'kind': column.kind.name,
      'isDoneState': column.isDoneState,
      'isBlockedState': column.isBlockedState,
      'isCancelledState': column.isCancelledState,
      'isDesignated': column.isDesignated,
      'isEnabled': column.isEnabled,
    };
  }

  Map<String, Object?> _workItemPayload(WorkItem item) {
    return {
      'itemId': item.itemId,
      'title': item.title,
      'type': item.type.name,
      'sortOrder': item.sortOrder,
      'parentId': item.parentId,
      'columnId': item.columnId,
      'toColumnId': item.columnId,
      'description': item.description,
      'assigneeIds': item.assigneeIds,
      'startAt': item.startAt?.toIso8601String(),
      'targetEndAt': item.targetEndAt?.toIso8601String(),
      'dueAt': item.dueAt?.toIso8601String(),
      'completedAt': item.completedAt?.toIso8601String(),
      'estimatedEffortMinutes': item.estimatedEffortMinutes,
      'actualEffortMinutes': item.actualEffortMinutes,
      'tags': item.tags,
      'archived': item.archived,
      'isInbox': item.isInbox,
      'recurrence': item.recurrence?.toMap(),
      'createdAt': item.createdAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
    };
  }

  int _compareItemSortOrder(WorkItem a, WorkItem b) {
    final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
    if (bySortOrder != 0) return bySortOrder;
    final byUpdated = b.updatedAt.compareTo(a.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  double _nextItemSortOrder(Iterable<WorkItem> items) {
    if (items.isEmpty) return _itemSortOrderStep;
    final currentMax = items
        .map((item) => item.sortOrder)
        .reduce((value, element) => value > element ? value : element);
    return currentMax + _itemSortOrderStep;
  }

  double? _betweenSortOrder({
    WorkItem? beforeItem,
    WorkItem? afterItem,
  }) {
    if (beforeItem == null && afterItem == null) {
      return _itemSortOrderStep;
    }
    if (beforeItem == null) {
      return afterItem!.sortOrder - _itemSortOrderStep;
    }
    if (afterItem == null) {
      return beforeItem.sortOrder + _itemSortOrderStep;
    }
    final gap = afterItem.sortOrder - beforeItem.sortOrder;
    if (gap.abs() < 0.001) {
      return null;
    }
    return beforeItem.sortOrder + (gap / 2);
  }

  int _insertionIndex({
    required List<WorkItem> orderedItems,
    String? beforeItemId,
    String? afterItemId,
  }) {
    if (afterItemId != null) {
      final afterIndex =
          orderedItems.indexWhere((item) => item.itemId == afterItemId);
      if (afterIndex >= 0) return afterIndex;
    }
    if (beforeItemId != null) {
      final beforeIndex =
          orderedItems.indexWhere((item) => item.itemId == beforeItemId);
      if (beforeIndex >= 0) return beforeIndex + 1;
    }
    return orderedItems.length;
  }

  List<WorkItem> _normalizedItemOrder({
    required List<WorkItem> items,
    required WorkItem movedItem,
    String? beforeItemId,
    String? afterItemId,
  }) {
    final ordered = [...items]..sort(_compareItemSortOrder);
    ordered.removeWhere((item) => item.itemId == movedItem.itemId);
    final insertIndex = _insertionIndex(
      orderedItems: ordered,
      beforeItemId: beforeItemId,
      afterItemId: afterItemId,
    );
    ordered.insert(insertIndex.clamp(0, ordered.length), movedItem);
    return [
      for (var index = 0; index < ordered.length; index++)
        ordered[index].copyWith(sortOrder: index * _itemSortOrderStep)
    ];
  }

  String? _doneColumnId(BoardSnapshot snapshot) {
    return WorkflowSemanticsPolicy.doneColumn(snapshot.columns)?.columnId;
  }

  bool _isInProgressColumn(BoardSnapshot snapshot, String columnId) {
    final column = snapshot.columns
        .where((entry) => entry.columnId == columnId)
        .cast<BoardColumn?>()
        .firstWhere((_) => true, orElse: () => null);
    return column?.kind == BoardColumnKind.inProgress;
  }

  String _defaultRecurringColumnId({
    required BoardSnapshot snapshot,
    required String fallbackColumnId,
  }) {
    final ordered = [...snapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final fallbackExists =
        ordered.any((column) => column.columnId == fallbackColumnId);
    if (fallbackExists) {
      final fallbackColumn =
          ordered.firstWhere((column) => column.columnId == fallbackColumnId);
      if (!fallbackColumn.isDoneState && !fallbackColumn.isCancelledState) {
        return fallbackColumn.columnId;
      }
    }
    final nonDone = ordered
        .where((column) => !column.isDoneState && !column.isCancelledState)
        .cast<BoardColumn?>()
        .firstWhere((_) => true, orElse: () => null);
    return nonDone?.columnId ?? fallbackColumnId;
  }

  DateTime? _advanceRecurrenceDate({
    required DateTime? base,
    required DateTime completedAt,
    required int intervalDays,
    required WorkItemRecurrenceMissedWindowPolicy missedWindowPolicy,
  }) {
    if (base == null) return null;
    final next = base.add(Duration(days: intervalDays));
    return switch (missedWindowPolicy) {
      WorkItemRecurrenceMissedWindowPolicy.singleStep => next,
      WorkItemRecurrenceMissedWindowPolicy.manualCatchUp =>
        next.isAfter(completedAt) ? next : null,
      WorkItemRecurrenceMissedWindowPolicy.nextEligible =>
        _advanceToNextEligibleDate(
          initialNext: next,
          completedAt: completedAt,
          intervalDays: intervalDays,
        ),
    };
  }

  DateTime _advanceToNextEligibleDate({
    required DateTime initialNext,
    required DateTime completedAt,
    required int intervalDays,
  }) {
    var next = initialNext;
    var guard = 0;
    while (!next.isAfter(completedAt) && guard < 2048) {
      next = next.add(Duration(days: intervalDays));
      guard++;
    }
    return next;
  }

  bool _hasMissedRecurringWindow({
    required WorkItem item,
    required DateTime completedAt,
    required int intervalDays,
  }) {
    bool missed(DateTime? base) {
      if (base == null) return false;
      return !base.add(Duration(days: intervalDays)).isAfter(completedAt);
    }

    return missed(item.startAt) ||
        missed(item.targetEndAt) ||
        missed(item.dueAt);
  }

  Future<void> _maybeGenerateRecurringInstance({
    required String boardId,
    required WorkItem before,
    required WorkItem after,
    required DateTime now,
  }) async {
    if (before.completedAt != null || after.completedAt == null) return;
    final recurrence = after.recurrence;
    if (recurrence == null ||
        !recurrence.enabled ||
        !recurrence.completionGated) {
      return;
    }
    if (after.type != WorkItemType.task && after.type != WorkItemType.action) {
      return;
    }

    final latestSnapshot = await _snapshot(boardId);
    final rootId = recurrence.rootItemId.trim().isEmpty
        ? after.itemId
        : recurrence.rootItemId.trim();
    final nextSequence = recurrence.sequence + 1;

    final alreadyExists = latestSnapshot.items.any((item) {
      final itemRecurrence = item.recurrence;
      if (itemRecurrence == null) return false;
      return itemRecurrence.rootItemId == rootId &&
          itemRecurrence.sequence == nextSequence;
    });
    if (alreadyExists) return;

    final generatedItemId = 'w-rec-${_sanitizeForId(rootId)}-$nextSequence';
    if (latestSnapshot.items.any((item) => item.itemId == generatedItemId)) {
      return;
    }

    final completedAt = after.completedAt ?? now;
    final intervalDays = recurrence.intervalDays;
    if (recurrence.missedWindowPolicy ==
            WorkItemRecurrenceMissedWindowPolicy.manualCatchUp &&
        _hasMissedRecurringWindow(
          item: after,
          completedAt: completedAt,
          intervalDays: intervalDays,
        )) {
      return;
    }
    final targetColumnId = _defaultRecurringColumnId(
      snapshot: latestSnapshot,
      fallbackColumnId: after.columnId,
    );
    final nextRecurrence = recurrence.copyWith(
      rootItemId: rootId,
      sequence: nextSequence,
    );

    final generated = WorkItem(
      itemId: generatedItemId,
      boardId: boardId,
      title: after.title,
      type: after.type,
      sortOrder: _nextItemSortOrder(latestSnapshot.items),
      parentId: after.parentId,
      columnId: targetColumnId,
      description: after.description,
      assigneeIds: after.assigneeIds,
      startAt: _advanceRecurrenceDate(
        base: after.startAt,
        completedAt: completedAt,
        intervalDays: intervalDays,
        missedWindowPolicy: recurrence.missedWindowPolicy,
      ),
      targetEndAt: _advanceRecurrenceDate(
        base: after.targetEndAt,
        completedAt: completedAt,
        intervalDays: intervalDays,
        missedWindowPolicy: recurrence.missedWindowPolicy,
      ),
      dueAt: _advanceRecurrenceDate(
        base: after.dueAt,
        completedAt: completedAt,
        intervalDays: intervalDays,
        missedWindowPolicy: recurrence.missedWindowPolicy,
      ),
      estimatedEffortMinutes: after.estimatedEffortMinutes,
      actualEffortMinutes: null,
      tags: after.tags,
      archived: false,
      isInbox: false,
      recurrence: nextRecurrence,
      createdAt: now,
      updatedAt: now,
    );

    final validationMessage = BoardValidationPolicy.validateNewItem(
      settings: latestSnapshot.board.validationSettings,
      type: generated.type,
      title: generated.title,
      parentId: generated.parentId,
      startAt: generated.startAt,
      targetEndAt: generated.targetEndAt,
      dueAt: generated.dueAt,
      estimatedEffortMinutes: generated.estimatedEffortMinutes,
      existingItems: latestSnapshot.items,
    );
    if (validationMessage != null) {
      return;
    }

    await _localStore.upsertItem(generated);
    await _recordActivity(
      boardId: boardId,
      itemId: generated.itemId,
      type: WorkItemActivityType.created,
      at: now,
      payload: {
        'columnId': generated.columnId,
        'type': generated.type.name,
        'generatedByRecurrence': true,
        'sourceItemId': after.itemId,
        'recurrenceRootItemId': rootId,
        'recurrenceSequence': nextSequence,
      },
    );
    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: generated.itemId,
      boardId: boardId,
      payload: {
        ..._workItemPayload(generated),
        'generatedByRecurrence': true,
        'sourceItemId': after.itemId,
      },
    );
  }

  Future<BoardSnapshot> _snapshot(String boardId) {
    return _localStore.getBoard(boardId);
  }

  Future<BoardPermissionProfile> _profile(String boardId) async {
    final snapshot = await _snapshot(boardId);
    return BoardPermissions.profileFor(
        snapshot: snapshot, userId: currentUserId);
  }

  Future<void> _requireCapability(
    String boardId,
    BoardCapability capability,
    String message,
  ) async {
    final profile = await _profile(boardId);
    if (profile.has(capability)) return;
    throw BoardPermissionDeniedException(message);
  }

  void _throwValidation(String message) {
    throw BoardValidationException(message);
  }

  Future<void> _recordReorderSideEffects({
    required String boardId,
    required WorkItem existing,
    required WorkItem updated,
    required DateTime now,
  }) async {
    if (existing.parentId != updated.parentId) {
      await _recordActivity(
        boardId: boardId,
        itemId: updated.itemId,
        type: WorkItemActivityType.reparented,
        at: now,
        payload: {
          'fromParentId': existing.parentId,
          'toParentId': updated.parentId,
        },
      );
    }
    if (existing.columnId != updated.columnId) {
      await _recordActivity(
        boardId: boardId,
        itemId: updated.itemId,
        type: WorkItemActivityType.moved,
        at: now,
        payload: {
          'fromColumnId': existing.columnId,
          'toColumnId': updated.columnId,
        },
      );
    }
    if (existing.completedAt == null && updated.completedAt != null) {
      await _recordActivity(
        boardId: boardId,
        itemId: updated.itemId,
        type: WorkItemActivityType.completed,
        at: now,
        payload: {
          'columnId': updated.columnId,
        },
      );
      await _maybeGenerateRecurringInstance(
        boardId: boardId,
        before: existing,
        after: updated,
        now: now,
      );
    } else if (existing.completedAt != null && updated.completedAt == null) {
      await _recordActivity(
        boardId: boardId,
        itemId: updated.itemId,
        type: WorkItemActivityType.reopened,
        at: now,
        payload: {
          'columnId': updated.columnId,
        },
      );
    }
  }

  Future<void> _enqueue({
    required DateTime now,
    required OutboxOperationType type,
    required String entity,
    required String entityId,
    required String boardId,
    required Map<String, Object?> payload,
  }) async {
    await _outboxQueue.enqueue(
      OutboxOperation(
        id: _operationId(
          createdAt: now,
          type: type,
          entity: entity,
          entityId: entityId,
        ),
        type: type,
        entity: entity,
        entityId: entityId,
        payload: _withPayloadContract(boardId: boardId, payload: payload),
        createdAt: now,
      ),
    );
  }

  @override
  Future<List<Board>> listBoards() => _localStore.listBoards();

  @override
  Future<Board> createBoard(String name) async {
    final board = await _localStore.createBoard(name);
    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'board',
      entityId: board.boardId,
      boardId: board.boardId,
      payload: _boardPayload(board),
    );
    return board;
  }

  @override
  Stream<BoardSnapshot> watchBoard(String boardId) =>
      _localStore.watchBoard(boardId);

  @override
  Future<void> renameBoard({
    required String boardId,
    required String name,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageBoard,
      'Current user cannot manage board settings.',
    );
    final snapshot = await _snapshot(boardId);
    final now = DateTime.now();
    final updated = snapshot.board.copyWith(name: name, updatedAt: now);
    await _localStore.upsertBoard(updated);
    await _enqueue(
      now: now,
      type: OutboxOperationType.update,
      entity: 'board',
      entityId: boardId,
      boardId: boardId,
      payload: _boardPayload(updated),
    );
  }

  @override
  Future<void> deleteBoard({
    required String boardId,
  }) async {
    final profile = await _profile(boardId);
    final member = profile.member;
    final isOwner = member != null &&
        !BoardPermissions.isInvitePending(member) &&
        member.role == BoardRole.owner;
    if (!isOwner) {
      throw BoardPermissionDeniedException(
          'Only the board owner can delete a board.');
    }

    final boards = await _localStore.listBoards();
    if (boards.length <= 1) {
      throw BoardValidationException('You must keep at least one board.');
    }

    await _localStore.deleteBoard(boardId);
    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.delete,
      entity: 'board',
      entityId: boardId,
      boardId: boardId,
      payload: {
        'boardId': boardId,
      },
    );
  }

  @override
  Future<void> inviteMember({
    required String boardId,
    required String userId,
    required BoardRole role,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageMembers,
      'Current user cannot manage board members.',
    );

    final pendingJoinedAt = DateTime.fromMillisecondsSinceEpoch(
      BoardPermissions.pendingInviteEpochMillis,
      isUtc: true,
    );
    await _localStore.upsertMember(
      BoardMember(
        boardId: boardId,
        userId: userId,
        role: role,
        joinedAt: pendingJoinedAt,
      ),
    );

    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'boardMember',
      entityId: '$boardId:$userId',
      boardId: boardId,
      payload: {
        'userId': userId,
        'role': role.name,
        'joinedAt': pendingJoinedAt.toIso8601String(),
        'joinedAtEpochMillis': pendingJoinedAt.millisecondsSinceEpoch,
        'invitePending': true,
      },
    );
  }

  @override
  Future<void> acceptInvite({
    required String boardId,
  }) async {
    final snapshot = await _snapshot(boardId);
    final member = BoardPermissions.memberForUser(snapshot, currentUserId);
    final canJoin =
        BoardPermissions.canJoinInvite(member: member, userId: currentUserId);
    if (!canJoin || member == null) {
      throw BoardPermissionDeniedException(
          'No pending invite found to accept.');
    }

    final now = DateTime.now();
    final updated = BoardMember(
      boardId: member.boardId,
      userId: member.userId,
      role: member.role,
      joinedAt: now,
    );
    await _localStore.upsertMember(updated);
    await _enqueue(
      now: now,
      type: OutboxOperationType.update,
      entity: 'boardMember',
      entityId: '$boardId:${member.userId}',
      boardId: boardId,
      payload: {
        'userId': member.userId,
        'role': member.role.name,
        'joinedAt': now.toIso8601String(),
        'joinedAtEpochMillis': now.millisecondsSinceEpoch,
        'acceptInvite': true,
      },
    );
  }

  @override
  Future<void> addMember({
    required String boardId,
    required String userId,
    required BoardRole role,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageMembers,
      'Current user cannot manage board members.',
    );
    final now = DateTime.now();
    await _localStore.upsertMember(
      BoardMember(boardId: boardId, userId: userId, role: role, joinedAt: now),
    );
    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'boardMember',
      entityId: '$boardId:$userId',
      boardId: boardId,
      payload: {
        'userId': userId,
        'role': role.name,
        'joinedAt': now.toIso8601String(),
        'joinedAtEpochMillis': now.millisecondsSinceEpoch,
        'invitePending': false,
      },
    );
  }

  @override
  Future<void> updateMemberRole({
    required String boardId,
    required String userId,
    required BoardRole role,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageMembers,
      'Current user cannot manage board members.',
    );
    final snapshot = await _snapshot(boardId);
    final existing = snapshot.members.firstWhere((m) => m.userId == userId);
    if (existing.role == BoardRole.owner && role != BoardRole.owner) {
      throw BoardPermissionDeniedException('Owner role cannot be changed.');
    }

    final updated = BoardMember(
      boardId: existing.boardId,
      userId: existing.userId,
      role: role,
      joinedAt: existing.joinedAt,
    );
    await _localStore.upsertMember(updated);
    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.update,
      entity: 'boardMember',
      entityId: '$boardId:$userId',
      boardId: boardId,
      payload: {
        'userId': userId,
        'role': role.name,
        'joinedAt': updated.joinedAt.toIso8601String(),
        'joinedAtEpochMillis': updated.joinedAt.millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<void> removeMember({
    required String boardId,
    required String userId,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageMembers,
      'Current user cannot manage board members.',
    );
    final snapshot = await _snapshot(boardId);
    final existing = snapshot.members.firstWhere((m) => m.userId == userId);
    if (existing.role == BoardRole.owner) {
      throw BoardPermissionDeniedException('Owner cannot be removed.');
    }

    await _localStore.deleteMember(boardId: boardId, userId: userId);
    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.delete,
      entity: 'boardMember',
      entityId: '$boardId:$userId',
      boardId: boardId,
      payload: {
        'userId': userId,
      },
    );
  }

  @override
  Future<void> createColumn({
    required String boardId,
    required String name,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageBoard,
      'Current user cannot manage board settings.',
    );
    final snapshot = await _snapshot(boardId);
    if (!snapshot.board.workflowSettings.allowCustomColumns) {
      throw BoardValidationException(
        'Custom columns are disabled for this board workflow.',
      );
    }
    final nextOrder = snapshot.columns.isEmpty
        ? 0
        : snapshot.columns
                .map((c) => c.orderIndex)
                .reduce((a, b) => a > b ? a : b) +
            1;
    final now = DateTime.now();
    final columnId = 'c-${now.microsecondsSinceEpoch}';

    final column = BoardColumn(
      columnId: columnId,
      boardId: boardId,
      name: name,
      orderIndex: nextOrder,
    );

    await _localStore.upsertColumn(column);

    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'column',
      entityId: columnId,
      boardId: boardId,
      payload: _columnPayload(column),
    );
  }

  @override
  Future<void> renameColumn({
    required String boardId,
    required String columnId,
    required String name,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageBoard,
      'Current user cannot manage board settings.',
    );
    final snapshot = await _snapshot(boardId);
    final existing = snapshot.columns.firstWhere((c) => c.columnId == columnId);
    final updated = existing.copyWith(name: name);

    await _localStore.upsertColumn(updated);
    final now = DateTime.now();

    await _enqueue(
      now: now,
      type: OutboxOperationType.update,
      entity: 'column',
      entityId: columnId,
      boardId: boardId,
      payload: _columnPayload(updated),
    );
  }

  @override
  Future<void> deleteColumn({
    required String boardId,
    required String columnId,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageBoard,
      'Current user cannot manage board settings.',
    );
    final snapshot = await _snapshot(boardId);
    if (snapshot.columns.length <= 1) return;

    final orderedColumns = [...snapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final fallbackColumn = orderedColumns.firstWhere(
        (c) => c.columnId != columnId,
        orElse: () =>
            snapshot.columns.firstWhere((c) => c.columnId != columnId));
    final itemsToMove =
        snapshot.items.where((item) => item.columnId == columnId).toList();

    final doneColumnId = _doneColumnId(snapshot);

    for (final item in itemsToMove) {
      final updated = item.copyWith(
        columnId: fallbackColumn.columnId,
        updatedAt: DateTime.now(),
      );
      final shouldBeCompleted = fallbackColumn.columnId == doneColumnId;
      final updatedWithCompletion = updated.copyWith(
        completedAt: shouldBeCompleted ? DateTime.now() : null,
      );
      await _localStore.upsertItem(updatedWithCompletion);
      final now = DateTime.now();
      await _enqueue(
        now: now,
        type: OutboxOperationType.move,
        entity: 'workItem',
        entityId: item.itemId,
        boardId: boardId,
        payload: {
          'itemId': item.itemId,
          'columnId': fallbackColumn.columnId,
          'toColumnId': fallbackColumn.columnId,
          'sortOrder': updatedWithCompletion.sortOrder,
          'updatedAt': updatedWithCompletion.updatedAt.toIso8601String(),
          'completedAt': updatedWithCompletion.completedAt?.toIso8601String(),
        },
      );
    }

    await _localStore.deleteColumn(boardId: boardId, columnId: columnId);
    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.delete,
      entity: 'column',
      entityId: columnId,
      boardId: boardId,
      payload: {
        'columnId': columnId,
        'fallbackColumnId': fallbackColumn.columnId,
      },
    );
  }

  @override
  Future<void> reorderColumns({
    required String boardId,
    required List<String> orderedColumnIds,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageBoard,
      'Current user cannot manage board settings.',
    );
    await _localStore.reorderColumns(
      boardId: boardId,
      orderedColumnIds: orderedColumnIds,
    );
    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.reorder,
      entity: 'column',
      entityId: boardId,
      boardId: boardId,
      payload: {
        'orderedColumnIds': orderedColumnIds,
      },
    );
  }

  @override
  Future<WorkItem> createItem({
    required String boardId,
    required String title,
    required WorkItemType type,
    required String toColumnId,
    String? parentId,
    String? description,
    DateTime? startAt,
    DateTime? targetEndAt,
    DateTime? dueAt,
    List<String> tags = const [],
    int? estimatedEffortMinutes,
    int? actualEffortMinutes,
    WorkItemRecurrence? recurrence,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in this board.',
    );

    final snapshot = await _snapshot(boardId);
    final now = DateTime.now();
    final effectiveStartAt =
        startAt ?? (_isInProgressColumn(snapshot, toColumnId) ? now : null);
    final validationMessage = BoardValidationPolicy.validateNewItem(
      settings: snapshot.board.validationSettings,
      type: type,
      title: title,
      parentId: parentId,
      startAt: effectiveStartAt,
      targetEndAt: targetEndAt,
      dueAt: dueAt,
      estimatedEffortMinutes: estimatedEffortMinutes,
      existingItems: snapshot.items,
    );
    if (validationMessage != null) {
      _throwValidation(validationMessage);
    }
    final itemId = 'w-${now.microsecondsSinceEpoch}';
    final doneColumnId = _doneColumnId(snapshot);
    final normalizedTags = _normalizeTags(tags);
    final normalizedDescription = description?.trim();
    final normalizedRecurrence = recurrence?.copyWith(
      rootItemId: recurrence.rootItemId.trim().isEmpty
          ? itemId
          : recurrence.rootItemId.trim(),
    );

    final item = WorkItem(
      itemId: itemId,
      boardId: boardId,
      title: title,
      type: type,
      sortOrder: _nextItemSortOrder(snapshot.items),
      parentId: parentId,
      columnId: toColumnId,
      description:
          normalizedDescription?.isEmpty == true ? null : normalizedDescription,
      startAt: effectiveStartAt,
      targetEndAt: targetEndAt,
      dueAt: dueAt,
      completedAt: toColumnId == doneColumnId ? now : null,
      estimatedEffortMinutes: estimatedEffortMinutes,
      actualEffortMinutes: actualEffortMinutes,
      tags: normalizedTags,
      isInbox: false,
      recurrence: normalizedRecurrence,
      createdAt: now,
      updatedAt: now,
    );

    await _localStore.upsertItem(item);
    await _recordActivity(
      boardId: boardId,
      itemId: item.itemId,
      type: WorkItemActivityType.created,
      at: now,
      payload: {
        'columnId': item.columnId,
        'type': item.type.name,
        'isInbox': item.isInbox,
      },
    );

    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: itemId,
      boardId: boardId,
      payload: _workItemPayload(item),
    );
    return item;
  }

  @override
  Future<void> createInboxCapture({
    required String boardId,
    required String title,
    List<String> tags = const [],
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw BoardValidationException('Capture title cannot be empty.');
    }
    await _requireCapability(
      boardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in this board.',
    );

    final snapshot = await _snapshot(boardId);
    if (snapshot.columns.isEmpty) {
      throw BoardValidationException('Board has no columns to hold captures.');
    }

    final orderedColumns = [...snapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final now = DateTime.now();
    final itemId = 'w-${now.microsecondsSinceEpoch}';
    final normalizedTags = _normalizeTags(tags);

    final capture = WorkItem(
      itemId: itemId,
      boardId: boardId,
      title: normalizedTitle,
      type: WorkItemType.task,
      sortOrder: _nextItemSortOrder(snapshot.items),
      columnId: orderedColumns.first.columnId,
      tags: normalizedTags,
      isInbox: true,
      createdAt: now,
      updatedAt: now,
    );

    await _localStore.upsertItem(capture);
    await _recordActivity(
      boardId: boardId,
      itemId: capture.itemId,
      type: WorkItemActivityType.created,
      at: now,
      payload: {
        'columnId': capture.columnId,
        'type': capture.type.name,
        'isInbox': true,
      },
    );
    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: itemId,
      boardId: boardId,
      payload: _workItemPayload(capture),
    );
  }

  @override
  Future<void> triageInboxItem({
    required String fromBoardId,
    required String itemId,
    required String toBoardId,
    required String toColumnId,
    required WorkItemType type,
    String? parentId,
  }) async {
    await _requireCapability(
      fromBoardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in source board.',
    );
    await _requireCapability(
      toBoardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in target board.',
    );

    final sourceSnapshot = await _snapshot(fromBoardId);
    final targetSnapshot = await _snapshot(toBoardId);
    final sourceItem =
        sourceSnapshot.items.firstWhere((item) => item.itemId == itemId);
    if (!sourceItem.isInbox) {
      throw BoardValidationException('Only inbox captures can be triaged.');
    }

    if (!targetSnapshot.columns
        .any((column) => column.columnId == toColumnId)) {
      throw BoardValidationException('Target column was not found.');
    }

    final targetItems = targetSnapshot.items
        .where((item) => item.itemId != itemId)
        .toList(growable: false);
    final validationMessage = BoardValidationPolicy.validateNewItem(
      settings: targetSnapshot.board.validationSettings,
      type: type,
      title: sourceItem.title,
      parentId: parentId,
      startAt: sourceItem.startAt ??
          (_isInProgressColumn(targetSnapshot, toColumnId)
              ? DateTime.now()
              : null),
      targetEndAt: sourceItem.targetEndAt,
      dueAt: sourceItem.dueAt,
      estimatedEffortMinutes: sourceItem.estimatedEffortMinutes,
      existingItems: targetItems,
    );
    if (validationMessage != null) {
      _throwValidation(validationMessage);
    }

    final now = DateTime.now();
    final targetDoneColumnId = _doneColumnId(targetSnapshot);
    final triaged = WorkItem(
      itemId: sourceItem.itemId,
      boardId: toBoardId,
      title: sourceItem.title,
      type: type,
      sortOrder: fromBoardId == toBoardId
          ? sourceItem.sortOrder
          : _nextItemSortOrder(targetSnapshot.items),
      parentId: parentId,
      columnId: toColumnId,
      description: sourceItem.description,
      assigneeIds: sourceItem.assigneeIds,
      startAt: sourceItem.startAt ??
          (_isInProgressColumn(targetSnapshot, toColumnId) ? now : null),
      targetEndAt: sourceItem.targetEndAt,
      dueAt: sourceItem.dueAt,
      completedAt: toColumnId == targetDoneColumnId ? now : null,
      estimatedEffortMinutes: sourceItem.estimatedEffortMinutes,
      actualEffortMinutes: sourceItem.actualEffortMinutes,
      tags: sourceItem.tags,
      archived: sourceItem.archived,
      isInbox: false,
      recurrence: sourceItem.recurrence,
      createdAt: sourceItem.createdAt,
      updatedAt: now,
    );

    if (fromBoardId == toBoardId) {
      await _localStore.upsertItem(triaged);
      await _recordActivity(
        boardId: toBoardId,
        itemId: triaged.itemId,
        type: WorkItemActivityType.moved,
        at: now,
        payload: {
          'fromColumnId': sourceItem.columnId,
          'toColumnId': triaged.columnId,
        },
      );
      if (sourceItem.parentId != triaged.parentId) {
        await _recordActivity(
          boardId: toBoardId,
          itemId: triaged.itemId,
          type: WorkItemActivityType.reparented,
          at: now,
          payload: {
            'fromParentId': sourceItem.parentId,
            'toParentId': triaged.parentId,
          },
        );
      }
      if (sourceItem.type != triaged.type ||
          sourceItem.isInbox != triaged.isInbox) {
        await _recordActivity(
          boardId: toBoardId,
          itemId: triaged.itemId,
          type: WorkItemActivityType.updated,
          at: now,
          payload: {
            'fromType': sourceItem.type.name,
            'toType': triaged.type.name,
            'fromInbox': sourceItem.isInbox,
            'toInbox': triaged.isInbox,
          },
        );
      }
      if (sourceItem.completedAt == null && triaged.completedAt != null) {
        await _recordActivity(
          boardId: toBoardId,
          itemId: triaged.itemId,
          type: WorkItemActivityType.completed,
          at: now,
          payload: {
            'columnId': triaged.columnId,
          },
        );
        await _maybeGenerateRecurringInstance(
          boardId: toBoardId,
          before: sourceItem,
          after: triaged,
          now: now,
        );
      }
      await _enqueue(
        now: now,
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: triaged.itemId,
        boardId: toBoardId,
        payload: _workItemPayload(triaged),
      );
      return;
    }

    await _localStore.upsertItem(triaged);
    await _localStore.deleteItem(boardId: fromBoardId, itemId: itemId);
    await _recordActivity(
      boardId: toBoardId,
      itemId: triaged.itemId,
      type: WorkItemActivityType.moved,
      at: now,
      payload: {
        'fromBoardId': fromBoardId,
        'toBoardId': toBoardId,
        'fromColumnId': sourceItem.columnId,
        'toColumnId': triaged.columnId,
      },
    );
    if (sourceItem.parentId != triaged.parentId) {
      await _recordActivity(
        boardId: toBoardId,
        itemId: triaged.itemId,
        type: WorkItemActivityType.reparented,
        at: now,
        payload: {
          'fromParentId': sourceItem.parentId,
          'toParentId': triaged.parentId,
        },
      );
    }
    if (sourceItem.type != triaged.type ||
        sourceItem.isInbox != triaged.isInbox) {
      await _recordActivity(
        boardId: toBoardId,
        itemId: triaged.itemId,
        type: WorkItemActivityType.updated,
        at: now,
        payload: {
          'fromType': sourceItem.type.name,
          'toType': triaged.type.name,
          'fromInbox': sourceItem.isInbox,
          'toInbox': triaged.isInbox,
        },
      );
    }
    if (sourceItem.completedAt == null && triaged.completedAt != null) {
      await _recordActivity(
        boardId: toBoardId,
        itemId: triaged.itemId,
        type: WorkItemActivityType.completed,
        at: now,
        payload: {
          'columnId': triaged.columnId,
        },
      );
      await _maybeGenerateRecurringInstance(
        boardId: toBoardId,
        before: sourceItem,
        after: triaged,
        now: now,
      );
    }

    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: triaged.itemId,
      boardId: toBoardId,
      payload: _workItemPayload(triaged),
    );

    await _enqueue(
      now: DateTime.now(),
      type: OutboxOperationType.delete,
      entity: 'workItem',
      entityId: itemId,
      boardId: fromBoardId,
      payload: {'itemId': itemId},
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
    await _requireCapability(
      boardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in this board.',
    );
    final snapshot = await _snapshot(boardId);
    final existing = snapshot.items.firstWhere((item) => item.itemId == itemId);
    final doneColumn = _doneColumnId(snapshot);

    final updated = existing.copyWith(
      columnId: toColumnId,
      startAt: existing.startAt ??
          (_isInProgressColumn(snapshot, toColumnId) ? DateTime.now() : null),
      completedAt: doneColumn == toColumnId ? DateTime.now() : null,
      isInbox: false,
      updatedAt: DateTime.now(),
    );

    await _localStore.upsertItem(updated);
    final now = DateTime.now();
    await _recordActivity(
      boardId: boardId,
      itemId: itemId,
      type: WorkItemActivityType.moved,
      at: now,
      payload: {
        'fromColumnId': existing.columnId,
        'toColumnId': toColumnId,
      },
    );
    if (existing.completedAt == null && updated.completedAt != null) {
      await _recordActivity(
        boardId: boardId,
        itemId: itemId,
        type: WorkItemActivityType.completed,
        at: now,
        payload: {
          'columnId': toColumnId,
        },
      );
      await _maybeGenerateRecurringInstance(
        boardId: boardId,
        before: existing,
        after: updated,
        now: now,
      );
    } else if (existing.completedAt != null && updated.completedAt == null) {
      await _recordActivity(
        boardId: boardId,
        itemId: itemId,
        type: WorkItemActivityType.reopened,
        at: now,
        payload: {
          'columnId': toColumnId,
        },
      );
    }

    await _enqueue(
      now: now,
      type: OutboxOperationType.move,
      entity: 'workItem',
      entityId: itemId,
      boardId: boardId,
      payload: {
        'itemId': itemId,
        'columnId': toColumnId,
        'toColumnId': toColumnId,
        'sortOrder': updated.sortOrder,
        'startAt': updated.startAt?.toIso8601String(),
        'updatedAt': updated.updatedAt.toIso8601String(),
        'completedAt': updated.completedAt?.toIso8601String(),
        'isInbox': updated.isInbox,
        'recurrence': updated.recurrence?.toMap(),
      },
    );
  }

  @override
  Future<void> reorderItem({
    required String boardId,
    required String itemId,
    String? toColumnId,
    String? parentId,
    bool clearParent = false,
    String? beforeItemId,
    String? afterItemId,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in this board.',
    );
    final snapshot = await _snapshot(boardId);
    final existing = snapshot.items.firstWhere((item) => item.itemId == itemId);
    final nextColumnId = toColumnId ?? existing.columnId;
    final nextParentId = clearParent ? null : (parentId ?? existing.parentId);
    final now = DateTime.now();
    final validationMessage = BoardValidationPolicy.validateItemUpdate(
      settings: snapshot.board.validationSettings,
      existing: existing,
      nextTitle: existing.title,
      nextParentId: nextParentId,
      nextStartAt: existing.startAt ??
          (_isInProgressColumn(snapshot, nextColumnId) ? now : null),
      nextTargetEndAt: existing.targetEndAt,
      nextDueAt: existing.dueAt,
      nextEstimatedEffortMinutes: existing.estimatedEffortMinutes,
      allItems: snapshot.items,
    );
    if (validationMessage != null) {
      _throwValidation(validationMessage);
    }

    final beforeItem = beforeItemId == null
        ? null
        : snapshot.items
            .where((item) => item.itemId == beforeItemId)
            .cast<WorkItem?>()
            .firstWhere((_) => true, orElse: () => null);
    final afterItem = afterItemId == null
        ? null
        : snapshot.items
            .where((item) => item.itemId == afterItemId)
            .cast<WorkItem?>()
            .firstWhere((_) => true, orElse: () => null);

    final baseUpdated = existing.copyWith(
      columnId: nextColumnId,
      parentId: parentId,
      clearParent: clearParent,
      startAt: existing.startAt ??
          (_isInProgressColumn(snapshot, nextColumnId) ? now : null),
      completedAt: _doneColumnId(snapshot) == nextColumnId
          ? (existing.completedAt ?? now)
          : null,
      isInbox: false,
      updatedAt: now,
    );
    final betweenOrder = _betweenSortOrder(
      beforeItem: beforeItem,
      afterItem: afterItem,
    );

    if (betweenOrder != null) {
      final reordered = baseUpdated.copyWith(sortOrder: betweenOrder);
      await _localStore.upsertItem(reordered);
      await _recordReorderSideEffects(
        boardId: boardId,
        existing: existing,
        updated: reordered,
        now: now,
      );
      await _enqueue(
        now: now,
        type: existing.columnId == reordered.columnId
            ? OutboxOperationType.update
            : OutboxOperationType.move,
        entity: 'workItem',
        entityId: reordered.itemId,
        boardId: boardId,
        payload: _workItemPayload(reordered),
      );
      return;
    }

    final normalized = _normalizedItemOrder(
      items: snapshot.items,
      movedItem: baseUpdated,
      beforeItemId: beforeItemId,
      afterItemId: afterItemId,
    );
    final updatedById = {for (final item in normalized) item.itemId: item};
    final reordered = updatedById[itemId]!;
    for (final item in normalized) {
      final previous = snapshot.items
          .where((entry) => entry.itemId == item.itemId)
          .cast<WorkItem?>()
          .firstWhere((_) => true, orElse: () => null);
      if (previous == null ||
          previous.sortOrder != item.sortOrder ||
          previous.columnId != item.columnId ||
          previous.parentId != item.parentId ||
          previous.updatedAt != item.updatedAt) {
        await _localStore.upsertItem(item);
        await _enqueue(
          now: now,
          type: previous != null && previous.columnId != item.columnId
              ? OutboxOperationType.move
              : OutboxOperationType.update,
          entity: 'workItem',
          entityId: item.itemId,
          boardId: boardId,
          payload: _workItemPayload(item),
        );
      }
    }
    await _recordReorderSideEffects(
      boardId: boardId,
      existing: existing,
      updated: reordered,
      now: now,
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
      await moveItem(
        boardId: fromBoardId,
        itemId: itemId,
        toColumnId: toColumnId,
      );
      return;
    }

    await _requireCapability(
      fromBoardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in source board.',
    );
    await _requireCapability(
      toBoardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in target board.',
    );

    final sourceSnapshot = await _snapshot(fromBoardId);
    final targetSnapshot = await _snapshot(toBoardId);
    final item = sourceSnapshot.items.firstWhere((it) => it.itemId == itemId);
    final now = DateTime.now();
    final targetDoneColumnId = _doneColumnId(targetSnapshot);

    final moved = WorkItem(
      itemId: item.itemId,
      boardId: toBoardId,
      title: item.title,
      type: item.type,
      sortOrder: _nextItemSortOrder(targetSnapshot.items),
      parentId: item.parentId,
      columnId: toColumnId,
      description: item.description,
      assigneeIds: item.assigneeIds,
      startAt: item.startAt ??
          (_isInProgressColumn(targetSnapshot, toColumnId) ? now : null),
      targetEndAt: item.targetEndAt,
      dueAt: item.dueAt,
      completedAt: toColumnId == targetDoneColumnId ? now : null,
      estimatedEffortMinutes: item.estimatedEffortMinutes,
      actualEffortMinutes: item.actualEffortMinutes,
      tags: item.tags,
      archived: item.archived,
      isInbox: item.isInbox,
      recurrence: item.recurrence,
      createdAt: item.createdAt,
      updatedAt: now,
    );

    await _localStore.upsertItem(moved);
    await _localStore.deleteItem(boardId: fromBoardId, itemId: itemId);
    await _recordActivity(
      boardId: toBoardId,
      itemId: itemId,
      type: WorkItemActivityType.moved,
      at: now,
      payload: {
        'fromBoardId': fromBoardId,
        'toBoardId': toBoardId,
        'fromColumnId': item.columnId,
        'toColumnId': moved.columnId,
      },
    );
    if (item.completedAt == null && moved.completedAt != null) {
      await _recordActivity(
        boardId: toBoardId,
        itemId: itemId,
        type: WorkItemActivityType.completed,
        at: now,
      );
      await _maybeGenerateRecurringInstance(
        boardId: toBoardId,
        before: item,
        after: moved,
        now: now,
      );
    } else if (item.completedAt != null && moved.completedAt == null) {
      await _recordActivity(
        boardId: toBoardId,
        itemId: itemId,
        type: WorkItemActivityType.reopened,
        at: now,
      );
    }

    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: itemId,
      boardId: toBoardId,
      payload: _workItemPayload(moved),
    );

    final deleteNow = DateTime.now();
    await _enqueue(
      now: deleteNow,
      type: OutboxOperationType.delete,
      entity: 'workItem',
      entityId: itemId,
      boardId: fromBoardId,
      payload: {
        'itemId': itemId,
      },
    );
  }

  @override
  Future<void> updateItem({
    required String boardId,
    required String itemId,
    String? title,
    String? description,
    double? sortOrder,
    String? parentId,
    DateTime? startAt,
    DateTime? targetEndAt,
    DateTime? dueAt,
    int? estimatedEffortMinutes,
    int? actualEffortMinutes,
    WorkItemRecurrence? recurrence,
    List<String>? tags,
    bool? archived,
    bool clearParent = false,
    bool clearDescription = false,
    bool clearStartAt = false,
    bool clearTargetEndAt = false,
    bool clearDueAt = false,
    bool clearEstimatedEffort = false,
    bool clearActualEffort = false,
    bool clearRecurrence = false,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in this board.',
    );
    final snapshot = await _snapshot(boardId);
    final existing = snapshot.items.firstWhere((item) => item.itemId == itemId);

    final nextParentId = clearParent ? null : (parentId ?? existing.parentId);
    final validationMessage = BoardValidationPolicy.validateItemUpdate(
      settings: snapshot.board.validationSettings,
      existing: existing,
      nextTitle: title,
      nextParentId: nextParentId,
      nextStartAt: clearStartAt ? null : (startAt ?? existing.startAt),
      nextTargetEndAt:
          clearTargetEndAt ? null : (targetEndAt ?? existing.targetEndAt),
      nextDueAt: clearDueAt ? null : (dueAt ?? existing.dueAt),
      nextEstimatedEffortMinutes: clearEstimatedEffort
          ? null
          : (estimatedEffortMinutes ?? existing.estimatedEffortMinutes),
      allItems: snapshot.items,
    );
    if (validationMessage != null) {
      _throwValidation(validationMessage);
    }

    final updated = existing.copyWith(
      title: title,
      description: description,
      sortOrder: sortOrder,
      parentId: parentId,
      startAt: startAt,
      targetEndAt: targetEndAt,
      dueAt: dueAt,
      estimatedEffortMinutes: estimatedEffortMinutes,
      actualEffortMinutes: actualEffortMinutes,
      recurrence: recurrence,
      tags: tags,
      archived: archived,
      clearParent: clearParent,
      clearDescription: clearDescription,
      clearStartAt: clearStartAt,
      clearTargetEndAt: clearTargetEndAt,
      clearDueAt: clearDueAt,
      clearEstimatedEffort: clearEstimatedEffort,
      clearActualEffort: clearActualEffort,
      clearRecurrence: clearRecurrence,
      updatedAt: DateTime.now(),
    );

    await _localStore.upsertItem(updated);
    final now = DateTime.now();
    if (existing.parentId != updated.parentId) {
      await _recordActivity(
        boardId: boardId,
        itemId: itemId,
        type: WorkItemActivityType.reparented,
        at: now,
        payload: {
          'fromParentId': existing.parentId,
          'toParentId': updated.parentId,
        },
      );
    }
    if (existing.archived != updated.archived) {
      await _recordActivity(
        boardId: boardId,
        itemId: itemId,
        type: updated.archived
            ? WorkItemActivityType.archived
            : WorkItemActivityType.unarchived,
        at: now,
      );
    }
    final hasGenericUpdate = existing.title != updated.title ||
        existing.description != updated.description ||
        existing.startAt != updated.startAt ||
        existing.targetEndAt != updated.targetEndAt ||
        existing.dueAt != updated.dueAt ||
        existing.estimatedEffortMinutes != updated.estimatedEffortMinutes ||
        existing.actualEffortMinutes != updated.actualEffortMinutes ||
        existing.recurrence?.toMap().toString() !=
            updated.recurrence?.toMap().toString() ||
        existing.tags.join('|') != updated.tags.join('|') ||
        existing.isInbox != updated.isInbox;
    if (hasGenericUpdate) {
      await _recordActivity(
        boardId: boardId,
        itemId: itemId,
        type: WorkItemActivityType.updated,
        at: now,
      );
    }

    await _enqueue(
      now: now,
      type: OutboxOperationType.update,
      entity: 'workItem',
      entityId: itemId,
      boardId: boardId,
      payload: {
        'itemId': itemId,
        'title': updated.title,
        'description': updated.description,
        'sortOrder': updated.sortOrder,
        'parentId': updated.parentId,
        'columnId': updated.columnId,
        'startAt': updated.startAt?.toIso8601String(),
        'targetEndAt': updated.targetEndAt?.toIso8601String(),
        'dueAt': updated.dueAt?.toIso8601String(),
        'estimatedEffortMinutes': updated.estimatedEffortMinutes,
        'actualEffortMinutes': updated.actualEffortMinutes,
        'tags': updated.tags,
        'archived': updated.archived,
        'isInbox': updated.isInbox,
        'recurrence': updated.recurrence?.toMap(),
        'updatedAt': updated.updatedAt.toIso8601String(),
      },
    );
  }

  @override
  Future<void> reparentItem({
    required String boardId,
    required String itemId,
    String? parentId,
    bool clearParent = false,
  }) {
    return updateItem(
      boardId: boardId,
      itemId: itemId,
      parentId: parentId,
      clearParent: clearParent,
    );
  }

  @override
  Future<void> deleteItem({
    required String boardId,
    required String itemId,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in this board.',
    );

    final snapshot = await _snapshot(boardId);
    snapshot.items.firstWhere((item) => item.itemId == itemId);
    final hasChildren = snapshot.items.any((item) => item.parentId == itemId);
    if (hasChildren) {
      throw BoardValidationException(
        'Cannot delete an item with children. Re-parent or delete children first.',
      );
    }

    await _localStore.deleteItem(boardId: boardId, itemId: itemId);
    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.delete,
      entity: 'workItem',
      entityId: itemId,
      boardId: boardId,
      payload: {
        'itemId': itemId,
      },
    );
  }

  @override
  Future<void> restoreItem({
    required String boardId,
    required WorkItem item,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in this board.',
    );

    final snapshot = await _snapshot(boardId);
    final orderedColumns = [...snapshot.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (orderedColumns.isEmpty) {
      throw BoardValidationException('Board has no columns.');
    }

    var restoredColumnId = item.columnId;
    if (!orderedColumns.any((column) => column.columnId == restoredColumnId)) {
      restoredColumnId = orderedColumns.first.columnId;
    }

    final nextParentId = item.parentId != null &&
            snapshot.items.any((entry) => entry.itemId == item.parentId)
        ? item.parentId
        : null;

    final now = DateTime.now();
    final doneColumnId = _doneColumnId(snapshot);
    final restored = WorkItem(
      itemId: item.itemId,
      boardId: boardId,
      title: item.title,
      type: item.type,
      sortOrder: _nextItemSortOrder(snapshot.items),
      parentId: nextParentId,
      columnId: restoredColumnId,
      description: item.description,
      assigneeIds: item.assigneeIds,
      startAt: item.startAt,
      targetEndAt: item.targetEndAt,
      dueAt: item.dueAt,
      completedAt:
          restoredColumnId == doneColumnId ? (item.completedAt ?? now) : null,
      estimatedEffortMinutes: item.estimatedEffortMinutes,
      actualEffortMinutes: item.actualEffortMinutes,
      tags: item.tags,
      archived: item.archived,
      isInbox: item.isInbox,
      recurrence: item.recurrence,
      createdAt: item.createdAt,
      updatedAt: now,
    );

    await _localStore.upsertItem(restored);
    await _recordActivity(
      boardId: boardId,
      itemId: restored.itemId,
      type: WorkItemActivityType.created,
      at: now,
      payload: {
        'columnId': restored.columnId,
        'type': restored.type.name,
        'restored': true,
      },
    );

    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: restored.itemId,
      boardId: boardId,
      payload: _workItemPayload(restored),
    );
  }

  @override
  Future<void> bulkUpdateItems({
    required String boardId,
    required List<String> itemIds,
    String? toColumnId,
    bool? archived,
    List<String> addTags = const [],
    List<String> removeTags = const [],
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.modifyItems,
      'Current user cannot modify items in this board.',
    );

    final uniqueIds = itemIds.toSet().toList();
    if (uniqueIds.isEmpty) return;

    final snapshot = await _snapshot(boardId);
    final doneColumnId = _doneColumnId(snapshot);
    if (toColumnId != null &&
        !snapshot.columns.any((column) => column.columnId == toColumnId)) {
      throw BoardValidationException('Target column was not found.');
    }

    final allItemsById = {
      for (final item in snapshot.items) item.itemId: item,
    };

    for (final id in uniqueIds) {
      final existing = allItemsById[id];
      if (existing == null) {
        throw BoardValidationException('Item not found: $id');
      }

      final nextColumnId = toColumnId ?? existing.columnId;
      final nextCompletedAt = toColumnId == null
          ? existing.completedAt
          : (nextColumnId == doneColumnId ? DateTime.now() : null);
      final nextTags = _mergeTags(
        existing: existing.tags,
        add: addTags,
        remove: removeTags,
      );

      final now = DateTime.now();
      final updated = existing.copyWith(
        columnId: nextColumnId,
        startAt: existing.startAt ??
            (_isInProgressColumn(snapshot, nextColumnId) ? now : null),
        archived: archived,
        tags: nextTags,
        completedAt: nextCompletedAt,
        isInbox: toColumnId == null ? existing.isInbox : false,
        recurrence: existing.recurrence,
        updatedAt: now,
      );

      await _localStore.upsertItem(updated);
      await _recordActivity(
        boardId: boardId,
        itemId: updated.itemId,
        type: toColumnId == null
            ? WorkItemActivityType.updated
            : WorkItemActivityType.moved,
        at: now,
        payload: {
          if (toColumnId != null) 'fromColumnId': existing.columnId,
          if (toColumnId != null) 'toColumnId': updated.columnId,
        },
      );
      if (existing.archived != updated.archived) {
        await _recordActivity(
          boardId: boardId,
          itemId: updated.itemId,
          type: updated.archived
              ? WorkItemActivityType.archived
              : WorkItemActivityType.unarchived,
          at: now,
        );
      }
      if (existing.completedAt == null && updated.completedAt != null) {
        await _recordActivity(
          boardId: boardId,
          itemId: updated.itemId,
          type: WorkItemActivityType.completed,
          at: now,
        );
        await _maybeGenerateRecurringInstance(
          boardId: boardId,
          before: existing,
          after: updated,
          now: now,
        );
      } else if (existing.completedAt != null && updated.completedAt == null) {
        await _recordActivity(
          boardId: boardId,
          itemId: updated.itemId,
          type: WorkItemActivityType.reopened,
          at: now,
        );
      }

      await _enqueue(
        now: now,
        type: toColumnId == null
            ? OutboxOperationType.update
            : OutboxOperationType.move,
        entity: 'workItem',
        entityId: updated.itemId,
        boardId: boardId,
        payload: {
          'itemId': updated.itemId,
          'title': updated.title,
          'type': updated.type.name,
          'parentId': updated.parentId,
          'columnId': updated.columnId,
          'toColumnId': updated.columnId,
          'description': updated.description,
          'startAt': updated.startAt?.toIso8601String(),
          'targetEndAt': updated.targetEndAt?.toIso8601String(),
          'dueAt': updated.dueAt?.toIso8601String(),
          'estimatedEffortMinutes': updated.estimatedEffortMinutes,
          'actualEffortMinutes': updated.actualEffortMinutes,
          'tags': updated.tags,
          'archived': updated.archived,
          'isInbox': updated.isInbox,
          'recurrence': updated.recurrence?.toMap(),
          'completedAt': updated.completedAt?.toIso8601String(),
          'updatedAt': updated.updatedAt.toIso8601String(),
        },
      );
    }
  }

  @override
  Future<void> updateBoardValidationSettings({
    required String boardId,
    required BoardValidationSettings settings,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.configureValidation,
      'Current user cannot configure board validation settings.',
    );
    final snapshot = await _snapshot(boardId);
    final now = DateTime.now();
    final updatedBoard = snapshot.board.copyWith(
      updatedAt: now,
      validationSettings: settings,
    );
    await _localStore.upsertBoard(updatedBoard);

    await _enqueue(
      now: now,
      type: OutboxOperationType.update,
      entity: 'board',
      entityId: boardId,
      boardId: boardId,
      payload: _boardPayload(updatedBoard),
    );
  }

  @override
  Future<void> updateBoardWorkflowSettings({
    required String boardId,
    required BoardWorkflowSettings settings,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageBoard,
      'Current user cannot manage board settings.',
    );
    final snapshot = await _snapshot(boardId);
    final now = DateTime.now();
    final updatedBoard = snapshot.board.copyWith(
      updatedAt: now,
      workflowSettings: settings,
    );
    await _localStore.upsertBoard(updatedBoard);

    await _enqueue(
      now: now,
      type: OutboxOperationType.update,
      entity: 'board',
      entityId: boardId,
      boardId: boardId,
      payload: _boardPayload(updatedBoard),
    );
  }

  @override
  Future<void> updateColumnSemantics({
    required String boardId,
    required String columnId,
    BoardColumnKind? kind,
    bool? isDoneState,
    bool? isBlockedState,
    bool? isCancelledState,
    bool? isEnabled,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageBoard,
      'Current user cannot manage board settings.',
    );
    final snapshot = await _snapshot(boardId);
    final existing = snapshot.columns.firstWhere((c) => c.columnId == columnId);
    final updated = existing.copyWith(
      kind: kind,
      isDoneState: isDoneState,
      isBlockedState: isBlockedState,
      isCancelledState: isCancelledState,
      isEnabled: isEnabled,
    );

    await _localStore.upsertColumn(updated);
    final now = DateTime.now();
    await _enqueue(
      now: now,
      type: OutboxOperationType.update,
      entity: 'column',
      entityId: columnId,
      boardId: boardId,
      payload: _columnPayload(updated),
    );

    final itemsInColumn =
        snapshot.items.where((item) => item.columnId == columnId).toList();
    if (itemsInColumn.isEmpty) return;

    for (final item in itemsInColumn) {
      final desiredCompletedAt = updated.isDoneState ? now : null;
      final completionPresenceUnchanged =
          (item.completedAt == null) == (desiredCompletedAt == null);
      if (completionPresenceUnchanged) continue;

      final updatedItem = item.copyWith(
        completedAt: desiredCompletedAt,
        updatedAt: now,
      );
      await _localStore.upsertItem(updatedItem);
      if (item.completedAt == null && updatedItem.completedAt != null) {
        await _maybeGenerateRecurringInstance(
          boardId: boardId,
          before: item,
          after: updatedItem,
          now: now,
        );
      }
      await _enqueue(
        now: now,
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: item.itemId,
        boardId: boardId,
        payload: {
          'itemId': item.itemId,
          'title': updatedItem.title,
          'type': updatedItem.type.name,
          'sortOrder': updatedItem.sortOrder,
          'parentId': updatedItem.parentId,
          'columnId': updatedItem.columnId,
          'completedAt': updatedItem.completedAt?.toIso8601String(),
          'recurrence': updatedItem.recurrence?.toMap(),
          'updatedAt': updatedItem.updatedAt.toIso8601String(),
        },
      );
    }
  }

  @override
  Future<void> applyWorkflowTemplate({
    required String boardId,
    required String templateId,
  }) async {
    await _requireCapability(
      boardId,
      BoardCapability.manageBoard,
      'Current user cannot manage board settings.',
    );

    if (templateId != BoardWorkflowSettings.designatedTemplateId) {
      throw BoardValidationException(
          'Unsupported workflow template: $templateId');
    }

    final snapshot = await _snapshot(boardId);
    final existingById = {for (final c in snapshot.columns) c.columnId: c};
    final templateColumns =
        WorkflowSemanticsPolicy.designatedTemplateColumns(boardId);

    for (final template in templateColumns) {
      final existing = existingById[template.columnId];
      final next = existing == null
          ? template
          : existing.copyWith(
              kind: template.kind,
              isDoneState: template.isDoneState,
              isBlockedState: template.isBlockedState,
              isCancelledState: template.isCancelledState,
              isDesignated: true,
              isEnabled: template.isEnabled,
            );
      await _localStore.upsertColumn(next);
      final now = DateTime.now();
      await _enqueue(
        now: now,
        type: existing == null
            ? OutboxOperationType.create
            : OutboxOperationType.update,
        entity: 'column',
        entityId: next.columnId,
        boardId: boardId,
        payload: _columnPayload(next),
      );
    }

    await updateBoardWorkflowSettings(
      boardId: boardId,
      settings:
          snapshot.board.workflowSettings.copyWith(templateId: templateId),
    );
  }
}
