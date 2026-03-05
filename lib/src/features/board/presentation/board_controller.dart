import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_flags.dart';
import '../../../core/outbox/in_memory_outbox_queue.dart';
import '../../../core/outbox/drift_outbox_queue.dart';
import '../../../core/outbox/outbox_queue.dart';
import '../../../core/sync/firestore_board_hydrator.dart';
import '../../../core/sync/firestore_sync_remote_adapter.dart';
import '../../../core/sync/in_memory_sync_remote_adapter.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_remote_adapter.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/local/drift/board_database.dart' as drift_db;
import '../data/local/drift/drift_local_board_store.dart';
import '../data/local/in_memory_local_board_store.dart';
import '../data/local/local_board_store.dart';
import '../data/repositories/autofill_settings_repository_impl.dart';
import '../data/repositories/board_filter_preset_repository_impl.dart';
import '../data/repositories/notification_preferences_repository_impl.dart';
import '../data/repositories/board_repository_impl.dart';
import '../data/repositories/work_item_activity_repository_impl.dart';
import '../domain/models/autofill_settings.dart';
import '../domain/models/board_reminder_alert.dart';
import '../domain/models/board.dart';
import '../domain/models/board_filter_preset.dart';
import '../domain/models/board_member.dart';
import '../domain/models/board_snapshot.dart';
import '../domain/models/board_validation_settings.dart';
import '../domain/models/board_workflow_settings.dart';
import '../domain/models/column.dart';
import '../domain/models/notification_preferences.dart';
import '../domain/models/work_item.dart';
import '../domain/models/work_item_activity_event.dart';
import '../domain/models/work_item_recurrence.dart';
import '../domain/models/work_item_type.dart';
import '../domain/policies/autofill_suggestion_policy.dart';
import '../domain/policies/board_permissions.dart';
import '../domain/policies/notification_reminder_policy.dart';
import '../domain/repositories/autofill_settings_repository.dart';
import '../domain/repositories/board_filter_preset_repository.dart';
import '../domain/repositories/board_repository.dart';
import '../domain/repositories/notification_preferences_repository.dart';
import '../domain/repositories/work_item_activity_repository.dart';

const defaultBoardId = 'board-1';

String _databaseNameForUser(String userId) {
  final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  return 'plandone_$safeUserId.sqlite';
}

final boardScopeUserIdProvider = Provider<String>((ref) {
  return ref.watch(activeUserIdProvider) ?? 'guest';
});

enum BoardVisibilityFilter {
  tasksOnly,
  goalsOnly,
  projectsOnly,
  actionsOnly,
  allItems
}

enum BoardPlanningView {
  kanban,
  hierarchy,
  backlog,
  focus,
}

enum BoardWorkspaceSurface {
  board,
  inbox,
}

enum BoardCardDensity {
  comfortable,
  compact,
}

enum BoardUndoOperationKind {
  move,
  reparent,
  archiveToggle,
  delete,
}

class BoardUndoOperation {
  const BoardUndoOperation({
    required this.operationId,
    required this.kind,
    required this.itemId,
    required this.message,
    required this.createdAt,
    required this.expiresAt,
    this.fromBoardId,
    this.toBoardId,
    this.fromColumnId,
    this.toColumnId,
    this.fromParentId,
    this.toParentId,
    this.fromArchived,
    this.toArchived,
    this.deletedItem,
  });

  final String operationId;
  final BoardUndoOperationKind kind;
  final String itemId;
  final String message;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? fromBoardId;
  final String? toBoardId;
  final String? fromColumnId;
  final String? toColumnId;
  final String? fromParentId;
  final String? toParentId;
  final bool? fromArchived;
  final bool? toArchived;
  final WorkItem? deletedItem;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

enum BoardItemStateFilter {
  any,
  active,
  done,
  blocked,
  cancelled,
  urgent,
  overdue,
  dueSoon,
}

final boardDatabaseProvider = Provider<drift_db.BoardDatabase>((ref) {
  final scopeUserId = ref.watch(boardScopeUserIdProvider);
  final db =
      drift_db.BoardDatabase(databaseName: _databaseNameForUser(scopeUserId));
  ref.onDispose(db.close);
  return db;
});

final localBoardStoreProvider = Provider<LocalBoardStore>((ref) {
  final currentUserId = ref.watch(boardScopeUserIdProvider);
  if (!useInMemoryLocalStore) {
    return DriftLocalBoardStore(
      database: ref.watch(boardDatabaseProvider),
      currentUserId: currentUserId,
    );
  }
  return InMemoryLocalBoardStore(currentUserId: currentUserId);
});

final outboxQueueProvider = Provider<OutboxQueue>((ref) {
  if (!useInMemoryLocalStore) {
    return DriftOutboxQueue(ref.watch(boardDatabaseProvider));
  }
  return InMemoryOutboxQueue();
});

final workItemActivityRepositoryProvider = Provider<WorkItemActivityRepository>(
  (ref) {
    if (!useInMemoryLocalStore) {
      return DriftWorkItemActivityRepository(
        database: ref.watch(boardDatabaseProvider),
      );
    }
    return InMemoryWorkItemActivityRepository();
  },
);

final boardRepositoryProvider = Provider<BoardRepository>((ref) {
  final currentUserId = ref.watch(boardScopeUserIdProvider);
  return BoardRepositoryImpl(
    localStore: ref.watch(localBoardStoreProvider),
    outboxQueue: ref.watch(outboxQueueProvider),
    activityRepository: ref.watch(workItemActivityRepositoryProvider),
    currentUserId: currentUserId,
  );
});

final syncRemoteAdapterProvider = Provider<SyncRemoteAdapter>((ref) {
  if (!useInMemoryLocalStore && useFirebaseSync) {
    return FirestoreSyncRemoteAdapter(firestore: FirebaseFirestore.instance);
  }
  return InMemorySyncRemoteAdapter();
});

final firestoreBoardHydratorProvider = Provider<FirestoreBoardHydrator?>((ref) {
  if (useInMemoryLocalStore || !useFirebaseSync) {
    return null;
  }

  final hydrator = FirestoreBoardHydrator(
    firestore: FirebaseFirestore.instance,
    localStore: ref.watch(localBoardStoreProvider),
  );

  ref.onDispose(() {
    hydrator.stop();
  });

  return hydrator;
});

final boardHydrationBootstrapProvider = FutureProvider<void>((ref) async {
  if (useInMemoryLocalStore || !useFirebaseSync) {
    return;
  }

  final boardId = ref.watch(currentBoardIdProvider);
  final hydrator = ref.watch(firestoreBoardHydratorProvider);
  await hydrator?.startForBoard(boardId);
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    outboxQueue: ref.watch(outboxQueueProvider),
    remoteAdapter: ref.watch(syncRemoteAdapterProvider),
  );
});

final lastSyncReportProvider = StateProvider<SyncRunReport?>((ref) => null);

class SyncUiState {
  const SyncUiState({
    this.isSyncing = false,
    this.lastAttemptAt,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastError,
    this.lastReport,
  });

  final bool isSyncing;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastError;
  final SyncRunReport? lastReport;

  SyncUiState copyWith({
    bool? isSyncing,
    DateTime? lastAttemptAt,
    DateTime? lastSuccessAt,
    DateTime? lastFailureAt,
    String? lastError,
    bool clearLastError = false,
    SyncRunReport? lastReport,
  }) {
    return SyncUiState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastFailureAt: lastFailureAt ?? this.lastFailureAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastReport: lastReport ?? this.lastReport,
    );
  }
}

final syncUiStateProvider = StateProvider<SyncUiState>(
  (ref) => const SyncUiState(),
);

class OutboxStatusSnapshot {
  const OutboxStatusSnapshot({
    required this.pendingCount,
    required this.retryScheduledCount,
    required this.failedCount,
    required this.nextRetryAt,
    this.latestError,
  });

  final int pendingCount;
  final int retryScheduledCount;
  final int failedCount;
  final DateTime? nextRetryAt;
  final String? latestError;
}

final outboxStatusProvider = FutureProvider<OutboxStatusSnapshot>((ref) async {
  ref.watch(boardStreamProvider);
  ref.watch(lastSyncReportProvider);

  final pending = await ref.watch(outboxQueueProvider).listPending();
  final now = DateTime.now();
  final retryScheduled = pending
      .where((op) => op.nextAttemptAt != null && op.nextAttemptAt!.isAfter(now))
      .toList();
  final failed = pending.where((op) => op.attemptCount > 0).toList();
  DateTime? nextRetryAt;
  for (final op in retryScheduled) {
    final candidate = op.nextAttemptAt;
    if (candidate == null) continue;
    if (nextRetryAt == null || candidate.isBefore(nextRetryAt)) {
      nextRetryAt = candidate;
    }
  }

  final latestFailed = failed.isEmpty ? null : failed.last;

  return OutboxStatusSnapshot(
    pendingCount: pending.length,
    retryScheduledCount: retryScheduled.length,
    failedCount: failed.length,
    nextRetryAt: nextRetryAt,
    latestError: latestFailed?.lastError,
  );
});

final currentBoardIdProvider = StateProvider<String>((ref) {
  // Reset board scope when authenticated user changes.
  ref.watch(boardScopeUserIdProvider);
  return defaultBoardId;
});

final boardsProvider = FutureProvider<List<Board>>((ref) {
  return ref.watch(boardRepositoryProvider).listBoards();
});

final boardStreamProvider = StreamProvider<BoardSnapshot>((ref) {
  ref.watch(boardHydrationBootstrapProvider);
  final boardId = ref.watch(currentBoardIdProvider);
  return ref.watch(boardRepositoryProvider).watchBoard(boardId);
});

final boardPermissionProfileProvider = Provider<BoardPermissionProfile?>((ref) {
  final snapshot = ref.watch(boardStreamProvider).valueOrNull;
  if (snapshot == null) return null;
  final userId = ref.watch(boardScopeUserIdProvider);
  return BoardPermissions.profileFor(snapshot: snapshot, userId: userId);
});

final pendingOutboxCountProvider = FutureProvider<int>((ref) async {
  // Recompute when board data changes so count updates after local operations.
  ref.watch(boardStreamProvider);
  final pending = await ref.watch(outboxQueueProvider).listPending();
  return pending.length;
});

final boardVisibilityFilterProvider =
    StateProvider<BoardVisibilityFilter>((ref) {
  // Spec default board filter: show tasks first.
  return BoardVisibilityFilter.tasksOnly;
});

final boardPlanningViewProvider =
    StateProvider<BoardPlanningView>((ref) => BoardPlanningView.kanban);

final boardItemStateFilterProvider =
    StateProvider<BoardItemStateFilter>((ref) => BoardItemStateFilter.any);

final boardTagFilterProvider = StateProvider<String>((ref) => '');

final selectedBoardItemIdsProvider = StateProvider<Set<String>>((ref) {
  // Reset selection when switching boards.
  ref.watch(currentBoardIdProvider);
  return <String>{};
});

final focusedItemIdProvider = StateProvider<String?>((ref) => null);
final focusModeEnabledProvider = StateProvider<bool>((ref) => false);
final activeDraggedItemProvider = StateProvider<WorkItem?>((ref) => null);
final boardTextQueryProvider = StateProvider<String>((ref) => '');
final workspaceSearchExpandedProvider = StateProvider<bool>((ref) => false);
final workspaceSelectedBoardIdsProvider = StateProvider<Set<String>>((ref) {
  // Empty means "all boards".
  return <String>{};
});
final boardWorkspaceSurfaceProvider =
    StateProvider<BoardWorkspaceSurface>((ref) => BoardWorkspaceSurface.board);
final boardCardDensityProvider =
    StateProvider<BoardCardDensity>((ref) => BoardCardDensity.comfortable);
final lastAutoFocusedDoingBoardIdProvider =
    StateProvider.autoDispose<String?>((ref) => null);
final collapsedHierarchyItemIdsProvider = StateProvider<Set<String>>((ref) {
  return <String>{};
});
final showOverdueOnlyProvider = StateProvider<bool>((ref) => false);
final showDueSoonOnlyProvider = StateProvider<bool>((ref) => false);
final showArchivedOnlyProvider = StateProvider<bool>((ref) => false);
final pendingBoardUndoOperationProvider =
    StateProvider<BoardUndoOperation?>((ref) => null);

final boardFilterPresetRepositoryProvider =
    Provider<BoardFilterPresetRepository>((ref) {
  final userId = ref.watch(boardScopeUserIdProvider);
  if (!useInMemoryLocalStore) {
    return DriftBoardFilterPresetRepository(
      database: ref.watch(boardDatabaseProvider),
      userId: userId,
    );
  }
  return InMemoryBoardFilterPresetRepository();
});

final boardFilterPresetsProvider = FutureProvider<List<BoardFilterPreset>>((
  ref,
) {
  ref.watch(boardScopeUserIdProvider);
  return ref.watch(boardFilterPresetRepositoryProvider).listPresets();
});

final autofillSettingsRepositoryProvider = Provider<AutofillSettingsRepository>(
  (ref) {
    final userId = ref.watch(boardScopeUserIdProvider);
    if (!useInMemoryLocalStore) {
      return DriftAutofillSettingsRepository(
        database: ref.watch(boardDatabaseProvider),
        userId: userId,
      );
    }
    return InMemoryAutofillSettingsRepository(userId: userId);
  },
);

final autofillSettingsProvider = FutureProvider<AutofillSettings>((ref) async {
  ref.watch(boardScopeUserIdProvider);
  return ref.watch(autofillSettingsRepositoryProvider).load();
});

final createItemAutofillSuggestionProvider =
    Provider<AsyncValue<AutofillSuggestionDraft>>((ref) {
  final snapshot = ref.watch(boardStreamProvider).valueOrNull;
  final settingsAsync = ref.watch(autofillSettingsProvider);
  if (snapshot == null || !settingsAsync.hasValue) {
    return const AsyncValue<AutofillSuggestionDraft>.loading();
  }
  return AsyncValue<AutofillSuggestionDraft>.data(
    AutofillSuggestionPolicy.forCreateItem(
      snapshot: snapshot,
      settings: settingsAsync.value!,
    ),
  );
});

final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>((ref) {
  final userId = ref.watch(boardScopeUserIdProvider);
  if (!useInMemoryLocalStore) {
    return DriftNotificationPreferencesRepository(
      database: ref.watch(boardDatabaseProvider),
      userId: userId,
    );
  }
  return InMemoryNotificationPreferencesRepository(userId: userId);
});

final notificationPreferencesProvider =
    FutureProvider<NotificationPreferences>((ref) async {
  ref.watch(boardScopeUserIdProvider);
  return ref.watch(notificationPreferencesRepositoryProvider).load();
});

final reminderClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(minutes: 1),
    (_) => DateTime.now(),
  );
});

final boardActiveRemindersProvider =
    Provider<AsyncValue<List<BoardReminderAlert>>>((ref) {
  final boardAsync = ref.watch(boardStreamProvider);
  final preferencesAsync = ref.watch(notificationPreferencesProvider);
  final now = ref.watch(reminderClockProvider).valueOrNull ?? DateTime.now();

  if (boardAsync.hasError) {
    return AsyncValue<List<BoardReminderAlert>>.error(
      boardAsync.error!,
      boardAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (preferencesAsync.hasError) {
    return AsyncValue<List<BoardReminderAlert>>.error(
      preferencesAsync.error!,
      preferencesAsync.stackTrace ?? StackTrace.current,
    );
  }

  final snapshot = boardAsync.valueOrNull;
  final preferences = preferencesAsync.valueOrNull;
  if (snapshot == null || preferences == null) {
    return const AsyncValue<List<BoardReminderAlert>>.loading();
  }

  final columnsById = {
    for (final column in snapshot.columns) column.columnId: column
  };
  final reminders = NotificationReminderPolicy.buildActiveReminders(
    items: snapshot.items,
    columnsById: columnsById,
    preferences: preferences,
    now: now,
  );
  return AsyncValue<List<BoardReminderAlert>>.data(reminders);
});

final workItemActivityTimelineProvider = FutureProvider.family
    .autoDispose<List<WorkItemActivityEvent>, String>((ref, itemId) {
  final boardId = ref.watch(currentBoardIdProvider);
  return ref.watch(workItemActivityRepositoryProvider).listForItem(
        boardId: boardId,
        itemId: itemId,
      );
});

final boardControllerProvider = Provider<BoardController>((ref) {
  return BoardController(ref, ref.watch(boardRepositoryProvider));
});

class BoardController {
  static const Duration undoWindow = Duration(seconds: 8);

  BoardController(this._ref, this._repository);

  final Ref _ref;
  final BoardRepository _repository;

  void switchBoard(String boardId) {
    _ref.read(currentBoardIdProvider.notifier).state = boardId;
  }

  Future<void> createBoard(String name) async {
    final board = await _repository.createBoard(name);
    _ref.invalidate(boardsProvider);
    _ref.read(currentBoardIdProvider.notifier).state = board.boardId;
  }

  Future<void> renameBoard(String name) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.renameBoard(boardId: boardId, name: name);
    _ref.invalidate(boardsProvider);
  }

  Future<void> deleteCurrentBoard() async {
    final boardId = _ref.read(currentBoardIdProvider);
    final boardsBefore = await _repository.listBoards();
    await _repository.deleteBoard(boardId: boardId);
    _ref.invalidate(boardsProvider);

    final fallback = boardsBefore
        .where((board) => board.boardId != boardId)
        .cast<Board?>()
        .firstWhere((_) => true, orElse: () => null);
    if (fallback != null) {
      _ref.read(currentBoardIdProvider.notifier).state = fallback.boardId;
    }
  }

  Future<void> inviteMember({
    required String userId,
    required BoardRole role,
  }) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.inviteMember(
        boardId: boardId, userId: userId, role: role);
  }

  Future<void> acceptInvite() async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.acceptInvite(boardId: boardId);
  }

  Future<void> updateMemberRole({
    required String userId,
    required BoardRole role,
  }) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.updateMemberRole(
      boardId: boardId,
      userId: userId,
      role: role,
    );
  }

  Future<void> removeMember(String userId) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.removeMember(boardId: boardId, userId: userId);
  }

  Future<void> updateBoardValidationSettings(
      BoardValidationSettings settings) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.updateBoardValidationSettings(
      boardId: boardId,
      settings: settings,
    );
  }

  Future<void> updateBoardWorkflowSettings(
      BoardWorkflowSettings settings) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.updateBoardWorkflowSettings(
      boardId: boardId,
      settings: settings,
    );
  }

  Future<void> applyWorkflowTemplate(String templateId) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.applyWorkflowTemplate(
      boardId: boardId,
      templateId: templateId,
    );
  }

  Future<void> updateColumnSemantics({
    required String columnId,
    BoardColumnKind? kind,
    bool? isDoneState,
    bool? isBlockedState,
    bool? isCancelledState,
    bool? isEnabled,
  }) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.updateColumnSemantics(
      boardId: boardId,
      columnId: columnId,
      kind: kind,
      isDoneState: isDoneState,
      isBlockedState: isBlockedState,
      isCancelledState: isCancelledState,
      isEnabled: isEnabled,
    );
  }

  Future<void> createColumn(String name) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.createColumn(boardId: boardId, name: name);
  }

  Future<void> renameColumn({
    required String columnId,
    required String name,
  }) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.renameColumn(
        boardId: boardId, columnId: columnId, name: name);
  }

  Future<void> deleteColumn(String columnId) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.deleteColumn(boardId: boardId, columnId: columnId);
  }

  Future<void> reorderColumns(List<String> orderedColumnIds) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.reorderColumns(
        boardId: boardId, orderedColumnIds: orderedColumnIds);
  }

  Future<void> createTask({
    required String title,
    required String toColumnId,
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.createTask(
      boardId: boardId,
      title: title,
      toColumnId: toColumnId,
    );
  }

  Future<WorkItem> createItem({
    required String title,
    required WorkItemType type,
    required String toColumnId,
    String? parentId,
    List<String> tags = const [],
    int? estimatedEffortMinutes,
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.createItem(
      boardId: boardId,
      title: title,
      type: type,
      toColumnId: toColumnId,
      parentId: parentId,
      tags: tags,
      estimatedEffortMinutes: estimatedEffortMinutes,
    );
  }

  Future<void> createInboxCapture({
    required String title,
    List<String> tags = const [],
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.createInboxCapture(
      boardId: boardId,
      title: title,
      tags: tags,
    );
  }

  Future<void> triageInboxItem({
    required String itemId,
    required String toBoardId,
    required String toColumnId,
    required WorkItemType type,
    String? parentId,
  }) {
    final fromBoardId = _ref.read(currentBoardIdProvider);
    return _repository.triageInboxItem(
      fromBoardId: fromBoardId,
      itemId: itemId,
      toBoardId: toBoardId,
      toColumnId: toColumnId,
      type: type,
      parentId: parentId,
    );
  }

  Future<void> moveItem({
    required String itemId,
    required String toColumnId,
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.moveItem(
      boardId: boardId,
      itemId: itemId,
      toColumnId: toColumnId,
    );
  }

  Future<void> moveItemToBoard({
    required String itemId,
    required String toBoardId,
    required String toColumnId,
  }) {
    final fromBoardId = _ref.read(currentBoardIdProvider);
    return _repository.moveItemToBoard(
      fromBoardId: fromBoardId,
      itemId: itemId,
      toBoardId: toBoardId,
      toColumnId: toColumnId,
    );
  }

  Future<void> updateItem({
    required String itemId,
    String? title,
    String? description,
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
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.updateItem(
      boardId: boardId,
      itemId: itemId,
      title: title,
      description: description,
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
    );
  }

  Future<void> reparentItem({
    required String itemId,
    String? parentId,
    bool clearParent = false,
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.reparentItem(
      boardId: boardId,
      itemId: itemId,
      parentId: parentId,
      clearParent: clearParent,
    );
  }

  Future<void> deleteItem({
    required String itemId,
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.deleteItem(boardId: boardId, itemId: itemId);
  }

  void clearPendingUndo({String? operationId}) {
    final pending = _ref.read(pendingBoardUndoOperationProvider);
    if (pending == null) return;
    if (operationId != null && pending.operationId != operationId) return;
    _ref.read(pendingBoardUndoOperationProvider.notifier).state = null;
  }

  BoardUndoOperation stageMoveUndo({
    required WorkItem item,
    required String fromBoardId,
    required String fromColumnId,
    required String toBoardId,
    required String toColumnId,
  }) {
    final now = DateTime.now();
    final op = BoardUndoOperation(
      operationId: 'undo-${now.microsecondsSinceEpoch}',
      kind: BoardUndoOperationKind.move,
      itemId: item.itemId,
      message: 'Item moved',
      createdAt: now,
      expiresAt: now.add(undoWindow),
      fromBoardId: fromBoardId,
      toBoardId: toBoardId,
      fromColumnId: fromColumnId,
      toColumnId: toColumnId,
    );
    _ref.read(pendingBoardUndoOperationProvider.notifier).state = op;
    return op;
  }

  BoardUndoOperation stageReparentUndo({
    required WorkItem item,
    required String? fromParentId,
    required String? toParentId,
  }) {
    final now = DateTime.now();
    final op = BoardUndoOperation(
      operationId: 'undo-${now.microsecondsSinceEpoch}',
      kind: BoardUndoOperationKind.reparent,
      itemId: item.itemId,
      message: 'Parent updated',
      createdAt: now,
      expiresAt: now.add(undoWindow),
      fromBoardId: item.boardId,
      toBoardId: item.boardId,
      fromParentId: fromParentId,
      toParentId: toParentId,
    );
    _ref.read(pendingBoardUndoOperationProvider.notifier).state = op;
    return op;
  }

  BoardUndoOperation stageArchiveUndo({
    required WorkItem item,
    required bool fromArchived,
    required bool toArchived,
  }) {
    final now = DateTime.now();
    final op = BoardUndoOperation(
      operationId: 'undo-${now.microsecondsSinceEpoch}',
      kind: BoardUndoOperationKind.archiveToggle,
      itemId: item.itemId,
      message: toArchived ? 'Item archived' : 'Item unarchived',
      createdAt: now,
      expiresAt: now.add(undoWindow),
      fromBoardId: item.boardId,
      toBoardId: item.boardId,
      fromArchived: fromArchived,
      toArchived: toArchived,
    );
    _ref.read(pendingBoardUndoOperationProvider.notifier).state = op;
    return op;
  }

  BoardUndoOperation stageDeleteUndo({
    required WorkItem item,
  }) {
    final now = DateTime.now();
    final op = BoardUndoOperation(
      operationId: 'undo-${now.microsecondsSinceEpoch}',
      kind: BoardUndoOperationKind.delete,
      itemId: item.itemId,
      message: 'Item deleted',
      createdAt: now,
      expiresAt: now.add(undoWindow),
      fromBoardId: item.boardId,
      toBoardId: item.boardId,
      deletedItem: item,
    );
    _ref.read(pendingBoardUndoOperationProvider.notifier).state = op;
    return op;
  }

  Future<bool> undoPendingOperation() async {
    final pending = _ref.read(pendingBoardUndoOperationProvider);
    if (pending == null || pending.isExpired) {
      clearPendingUndo();
      return false;
    }

    switch (pending.kind) {
      case BoardUndoOperationKind.move:
        final fromBoardId = pending.fromBoardId;
        final toBoardId = pending.toBoardId;
        final fromColumnId = pending.fromColumnId;
        if (fromBoardId == null || toBoardId == null || fromColumnId == null) {
          clearPendingUndo();
          return false;
        }
        if (fromBoardId == toBoardId) {
          await _repository.moveItem(
            boardId: fromBoardId,
            itemId: pending.itemId,
            toColumnId: fromColumnId,
          );
        } else {
          await _repository.moveItemToBoard(
            fromBoardId: toBoardId,
            itemId: pending.itemId,
            toBoardId: fromBoardId,
            toColumnId: fromColumnId,
          );
        }
        break;
      case BoardUndoOperationKind.reparent:
        final String boardId =
            pending.fromBoardId ?? _ref.read(currentBoardIdProvider);
        await _repository.reparentItem(
          boardId: boardId,
          itemId: pending.itemId,
          parentId: pending.fromParentId,
          clearParent: pending.fromParentId == null,
        );
        break;
      case BoardUndoOperationKind.archiveToggle:
        final String boardId =
            pending.fromBoardId ?? _ref.read(currentBoardIdProvider);
        await _repository.updateItem(
          boardId: boardId,
          itemId: pending.itemId,
          archived: pending.fromArchived,
        );
        break;
      case BoardUndoOperationKind.delete:
        final String boardId =
            pending.fromBoardId ?? _ref.read(currentBoardIdProvider);
        final deleted = pending.deletedItem;
        if (deleted == null) {
          clearPendingUndo();
          return false;
        }
        await _repository.restoreItem(boardId: boardId, item: deleted);
        break;
    }

    clearPendingUndo(operationId: pending.operationId);
    return true;
  }

  Future<void> bulkUpdateItems({
    required List<String> itemIds,
    String? toColumnId,
    bool? archived,
    List<String> addTags = const [],
    List<String> removeTags = const [],
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.bulkUpdateItems(
      boardId: boardId,
      itemIds: itemIds,
      toColumnId: toColumnId,
      archived: archived,
      addTags: addTags,
      removeTags: removeTags,
    );
  }

  Future<BoardFilterPreset> saveCurrentFilterPreset({
    required String name,
    String? presetId,
  }) async {
    final now = DateTime.now();
    final existing = presetId == null
        ? null
        : (await _ref.read(boardFilterPresetRepositoryProvider).listPresets())
            .where((preset) => preset.presetId == presetId)
            .cast<BoardFilterPreset?>()
            .firstWhere((_) => true, orElse: () => null);

    final normalizedName = name.trim();
    final next = BoardFilterPreset(
      presetId:
          presetId ?? 'preset-${now.microsecondsSinceEpoch}-${now.second}',
      name: normalizedName,
      visibilityFilter: _ref.read(boardVisibilityFilterProvider).name,
      stateFilter: _ref.read(boardItemStateFilterProvider).name,
      tagFilter: _ref.read(boardTagFilterProvider).trim(),
      textQuery: _ref.read(boardTextQueryProvider).trim(),
      selectedBoardIds: _ref.read(workspaceSelectedBoardIdsProvider).toList()
        ..sort(),
      showOverdueOnly: _ref.read(showOverdueOnlyProvider),
      showDueSoonOnly: _ref.read(showDueSoonOnlyProvider),
      showArchivedOnly: _ref.read(showArchivedOnlyProvider),
      planningView: _ref.read(boardPlanningViewProvider).name,
      workspaceSurface: _ref.read(boardWorkspaceSurfaceProvider).name,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final saved =
        await _ref.read(boardFilterPresetRepositoryProvider).savePreset(next);
    _ref.invalidate(boardFilterPresetsProvider);
    return saved;
  }

  Future<void> applyFilterPreset(BoardFilterPreset preset) async {
    _ref.read(boardVisibilityFilterProvider.notifier).state =
        BoardVisibilityFilter.values.firstWhere(
      (entry) => entry.name == preset.visibilityFilter,
      orElse: () => BoardVisibilityFilter.allItems,
    );
    _ref.read(boardItemStateFilterProvider.notifier).state =
        BoardItemStateFilter.values.firstWhere(
      (entry) => entry.name == preset.stateFilter,
      orElse: () => BoardItemStateFilter.any,
    );
    _ref.read(boardTagFilterProvider.notifier).state = preset.tagFilter;
    _ref.read(boardTextQueryProvider.notifier).state = preset.textQuery;
    _ref.read(workspaceSelectedBoardIdsProvider.notifier).state =
        preset.selectedBoardIds.toSet();
    _ref.read(showOverdueOnlyProvider.notifier).state = preset.showOverdueOnly;
    _ref.read(showDueSoonOnlyProvider.notifier).state = preset.showDueSoonOnly;
    _ref.read(showArchivedOnlyProvider.notifier).state =
        preset.showArchivedOnly;
    _ref.read(boardPlanningViewProvider.notifier).state =
        BoardPlanningView.values.firstWhere(
      (entry) => entry.name == preset.planningView,
      orElse: () => BoardPlanningView.kanban,
    );
    _ref.read(boardWorkspaceSurfaceProvider.notifier).state =
        BoardWorkspaceSurface.values.firstWhere(
      (entry) => entry.name == preset.workspaceSurface,
      orElse: () => BoardWorkspaceSurface.board,
    );
  }

  Future<void> renameFilterPreset({
    required BoardFilterPreset preset,
    required String name,
  }) async {
    await _ref.read(boardFilterPresetRepositoryProvider).savePreset(
          preset.copyWith(name: name.trim(), updatedAt: DateTime.now()),
        );
    _ref.invalidate(boardFilterPresetsProvider);
  }

  Future<void> deleteFilterPreset(String presetId) async {
    await _ref.read(boardFilterPresetRepositoryProvider).deletePreset(presetId);
    _ref.invalidate(boardFilterPresetsProvider);
  }

  Future<AutofillSettings> updateAutofillSettings(
    AutofillSettings settings,
  ) async {
    final saved = await _ref.read(autofillSettingsRepositoryProvider).save(
          settings,
        );
    _ref.invalidate(autofillSettingsProvider);
    return saved;
  }

  Future<NotificationPreferences> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final saved = await _ref
        .read(notificationPreferencesRepositoryProvider)
        .save(preferences);
    _ref.invalidate(notificationPreferencesProvider);
    return saved;
  }

  Future<void> snoozeReminder({
    required String reminderId,
    Duration? duration,
  }) async {
    final preferences = await _ref.read(notificationPreferencesProvider.future);
    final now = DateTime.now();
    final snoozeFor = duration ??
        Duration(
            minutes: preferences.defaultSnoozeMinutes.clamp(5, 7 * 24 * 60));
    final nextSnoozed = Map<String, int>.from(
      preferences.snoozedReminderUntilEpochMillis,
    )..[reminderId] = now.add(snoozeFor).millisecondsSinceEpoch;

    await updateNotificationPreferences(
      preferences.copyWith(snoozedReminderUntilEpochMillis: nextSnoozed),
    );
  }

  Future<void> muteReminders(Duration duration) async {
    final preferences = await _ref.read(notificationPreferencesProvider.future);
    await updateNotificationPreferences(
      preferences.copyWith(mutedUntil: DateTime.now().add(duration)),
    );
  }

  Future<void> clearReminderMute() async {
    final preferences = await _ref.read(notificationPreferencesProvider.future);
    await updateNotificationPreferences(
      preferences.copyWith(clearMutedUntil: true),
    );
  }

  Future<SyncRunReport> syncNow({bool ignoreRetrySchedule = true}) async {
    final now = DateTime.now();
    _ref.read(syncUiStateProvider.notifier).state = _ref
        .read(syncUiStateProvider)
        .copyWith(isSyncing: true, lastAttemptAt: now);

    try {
      final report = await _ref
          .read(syncEngineProvider)
          .syncPending(ignoreRetrySchedule: ignoreRetrySchedule);
      _ref.read(lastSyncReportProvider.notifier).state = report;
      _ref.read(syncUiStateProvider.notifier).state =
          _ref.read(syncUiStateProvider).copyWith(
                isSyncing: false,
                lastSuccessAt: DateTime.now(),
                lastReport: report,
                clearLastError: true,
              );
      _ref.invalidate(pendingOutboxCountProvider);
      _ref.invalidate(outboxStatusProvider);
      return report;
    } catch (error) {
      _ref.read(syncUiStateProvider.notifier).state =
          _ref.read(syncUiStateProvider).copyWith(
                isSyncing: false,
                lastFailureAt: DateTime.now(),
                lastError: 'Sync failed: $error',
              );
      rethrow;
    }
  }
}
