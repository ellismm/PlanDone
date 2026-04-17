import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_flags.dart';
import '../../../core/outbox/outbox_queue.dart';
import '../../../core/sync/firestore_board_hydrator.dart';
import '../../../core/sync/firestore_sync_remote_adapter.dart';
import '../../../core/sync/in_memory_sync_remote_adapter.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_remote_adapter.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/local/local_board_store.dart';
import '../data/platform/storage_platform.dart' as storage_platform;
import '../data/platform/storage_platform_interface.dart';
import '../data/platform/user_scoped_board_database.dart';
import '../data/repositories/board_repository_impl.dart';
import '../domain/models/autofill_settings.dart';
import '../domain/models/board_backup_document.dart';
import '../domain/models/board_calendar_preferences.dart';
import '../domain/models/board_flow.dart';
import '../domain/models/board_insights.dart';
import '../domain/models/board_reminder_alert.dart';
import '../domain/models/board_scheduled_reminder.dart';
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
import '../domain/policies/board_flow_policy.dart';
import '../domain/policies/board_insights_policy.dart';
import '../domain/policies/board_permissions.dart';
import '../domain/policies/notification_reminder_policy.dart';
import '../domain/policies/workflow_semantics_policy.dart';
import '../domain/repositories/autofill_settings_repository.dart';
import '../domain/repositories/board_backup_repository.dart';
import '../domain/repositories/board_calendar_preferences_repository.dart';
import '../domain/repositories/board_flow_preferences_repository.dart';
import '../domain/repositories/board_filter_preset_repository.dart';
import '../domain/repositories/board_repository.dart';
import '../domain/repositories/notification_preferences_repository.dart';
import '../domain/repositories/work_item_activity_repository.dart';
import 'item_accent_colors.dart';
import 'workspace_attention.dart';

const defaultBoardId = 'board-1';
const boardItemFocusTapRegionGroup = 'board-item-focus-region';

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
  calendar,
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
  rescheduleDueDate,
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
    this.fromDueAt,
    this.toDueAt,
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
  final DateTime? fromDueAt;
  final DateTime? toDueAt;
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

final boardDatabaseProvider = Provider<PlatformBoardDatabase>((ref) {
  final scopeUserId = ref.watch(boardScopeUserIdProvider);
  final db = storage_platform.createBoardDatabase(
    databaseName: boardDatabaseNameForUser(scopeUserId),
  );
  ref.onDispose(db.close);
  return db;
});

final localBoardStoreProvider = Provider<LocalBoardStore>((ref) {
  final currentUserId = ref.watch(boardScopeUserIdProvider);
  return storage_platform.createLocalBoardStore(
    database: ref.watch(boardDatabaseProvider),
    currentUserId: currentUserId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
});

final outboxQueueProvider = Provider<OutboxQueue>((ref) {
  return storage_platform.createOutboxQueue(
    database: ref.watch(boardDatabaseProvider),
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
});

final workItemActivityRepositoryProvider = Provider<WorkItemActivityRepository>(
  (ref) {
    return storage_platform.createWorkItemActivityRepository(
      database: ref.watch(boardDatabaseProvider),
      useInMemoryLocalStore: useInMemoryLocalStore,
    );
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

final boardBackupRepositoryProvider = Provider<BoardBackupRepository>((ref) {
  final currentUserId = ref.watch(boardScopeUserIdProvider);
  return storage_platform.createBoardBackupRepository(
    localStore: ref.watch(localBoardStoreProvider),
    outboxQueue: ref.watch(outboxQueueProvider),
    currentUserId: currentUserId,
    useInMemoryLocalStore: useInMemoryLocalStore,
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

final boardSnapshotProvider =
    StreamProvider.family<BoardSnapshot, String>((ref, boardId) {
  return ref.watch(boardRepositoryProvider).watchBoard(boardId);
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

final boardVisibilityFilterProvider = StateProvider<Set<WorkItemType>>((ref) {
  // Spec default board filter: show tasks first.
  return {WorkItemType.task};
});

final boardPlanningViewProvider =
    StateProvider<BoardPlanningView>((ref) => BoardPlanningView.kanban);

final boardCalendarSubviewProvider = StateProvider<BoardCalendarSubview>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return BoardCalendarSubview.month;
});

final boardCalendarVisibleDateKindsProvider =
    StateProvider<Set<BoardCalendarMarkerKind>>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return const <BoardCalendarMarkerKind>{
    BoardCalendarMarkerKind.start,
    BoardCalendarMarkerKind.targetEnd,
    BoardCalendarMarkerKind.due,
  };
});

final boardCalendarShowUnscheduledProvider = StateProvider<bool>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return true;
});

final boardCalendarAnchorDateProvider = StateProvider<DateTime>((ref) {
  ref.watch(boardScopeUserIdProvider);
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final boardFlowVisibleTypesProvider = StateProvider<Set<WorkItemType>>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return const <WorkItemType>{WorkItemType.action};
});

final boardFlowMotionEnabledProvider = StateProvider<bool>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return true;
});

final boardFlowMotionSpeedProvider = StateProvider<double>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return boardFlowDefaultMotionSpeed;
});

final boardFlowSuppressedItemsProvider =
    StateProvider<Map<String, BoardFlowSuppressionEntry>>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return const <String, BoardFlowSuppressionEntry>{};
});
final boardFlowReviewedItemsProvider =
    StateProvider<Map<String, BoardFlowReviewedEntry>>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return const <String, BoardFlowReviewedEntry>{};
});

final boardItemStateFilterProvider =
    StateProvider<BoardItemStateFilter>((ref) => BoardItemStateFilter.any);

final boardTagFilterProvider = StateProvider<String>((ref) => '');

final selectedBoardItemIdsProvider = StateProvider<Set<String>>((ref) {
  // Reset selection when switching boards.
  ref.watch(currentBoardIdProvider);
  return <String>{};
});

final focusedItemIdProvider = StateProvider<String?>((ref) => null);
final selectedHierarchyItemIdProvider = StateProvider<String?>((ref) {
  ref.watch(boardPlanningViewProvider);
  return null;
});
final focusModeEnabledProvider = StateProvider<bool>((ref) => false);
final activeDraggedItemProvider = StateProvider<WorkItem?>((ref) => null);
final activeDraggedItemPositionProvider = StateProvider<Offset?>((ref) => null);
final boardTextQueryProvider = StateProvider<String>((ref) => '');
final workspaceSearchExpandedProvider = StateProvider<bool>((ref) => false);
final workspaceSelectedBoardIdsProvider = StateProvider<Set<String>>((ref) {
  // Empty means "all boards".
  return <String>{};
});
final boardWorkspaceSurfaceProvider =
    StateProvider<BoardWorkspaceSurface>((ref) => BoardWorkspaceSurface.board);
final boardCardDensityProvider =
    StateProvider<BoardCardDensity>((ref) => BoardCardDensity.compact);
final lastAutoFocusedDoingBoardIdProvider =
    StateProvider.autoDispose<String?>((ref) {
  ref.watch(currentBoardIdProvider);
  ref.watch(boardPlanningViewProvider);
  ref.watch(boardWorkspaceSurfaceProvider);
  return null;
});
final collapsedHierarchyItemIdsProvider = StateProvider<Set<String>>((ref) {
  ref.watch(boardPlanningViewProvider);
  return <String>{};
});
final showOverdueOnlyProvider = StateProvider<bool>((ref) => false);
final showDueSoonOnlyProvider = StateProvider<bool>((ref) => false);
final showArchivedOnlyProvider = StateProvider<bool>((ref) => false);
final pendingBoardUndoOperationProvider =
    StateProvider<BoardUndoOperation?>((ref) => null);
final dismissedReminderTopNoticeUntilProvider =
    StateProvider<Map<String, int>>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return <String, int>{};
});
final dismissedSystemNoticeKeysProvider = StateProvider<Set<String>>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return <String>{};
});
final workspaceFeedbackQueueProvider =
    StateProvider<List<WorkspaceFeedbackMessage>>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return const <WorkspaceFeedbackMessage>[];
});

final boardFilterPresetRepositoryProvider =
    Provider<BoardFilterPresetRepository>((ref) {
  final userId = ref.watch(boardScopeUserIdProvider);
  return storage_platform.createBoardFilterPresetRepository(
    database: ref.watch(boardDatabaseProvider),
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
});

final boardFilterPresetsProvider = FutureProvider<List<BoardFilterPreset>>((
  ref,
) {
  ref.watch(boardScopeUserIdProvider);
  return ref.watch(boardFilterPresetRepositoryProvider).listPresets();
});

final boardCalendarPreferencesRepositoryProvider =
    Provider<BoardCalendarPreferencesRepository>((ref) {
  final userId = ref.watch(boardScopeUserIdProvider);
  return storage_platform.createBoardCalendarPreferencesRepository(
    database: ref.watch(boardDatabaseProvider),
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
});

final boardCalendarPreferencesProvider =
    FutureProvider<BoardCalendarPreferences>((ref) async {
  ref.watch(boardScopeUserIdProvider);
  return ref.watch(boardCalendarPreferencesRepositoryProvider).load();
});

final boardFlowPreferencesRepositoryProvider =
    Provider<BoardFlowPreferencesRepository>((ref) {
  final userId = ref.watch(boardScopeUserIdProvider);
  return storage_platform.createBoardFlowPreferencesRepository(
    database: ref.watch(boardDatabaseProvider),
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
});

final boardFlowPreferencesProvider = FutureProvider<BoardFlowPreferences>((
  ref,
) async {
  ref.watch(boardScopeUserIdProvider);
  return ref.watch(boardFlowPreferencesRepositoryProvider).load();
});

final autofillSettingsRepositoryProvider = Provider<AutofillSettingsRepository>(
  (ref) {
    final userId = ref.watch(boardScopeUserIdProvider);
    return storage_platform.createAutofillSettingsRepository(
      database: ref.watch(boardDatabaseProvider),
      userId: userId,
      useInMemoryLocalStore: useInMemoryLocalStore,
    );
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
  return storage_platform.createNotificationPreferencesRepository(
    database: ref.watch(boardDatabaseProvider),
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
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
  final boardsAsync = ref.watch(boardsProvider);
  final selectedBoardIds = ref.watch(workspaceSelectedBoardIdsProvider);
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
  if (boardsAsync.hasError) {
    return AsyncValue<List<BoardReminderAlert>>.error(
      boardsAsync.error!,
      boardsAsync.stackTrace ?? StackTrace.current,
    );
  }

  final snapshot = boardAsync.valueOrNull;
  final boards = boardsAsync.valueOrNull;
  final preferences = preferencesAsync.valueOrNull;
  if (snapshot == null || preferences == null || boards == null) {
    return const AsyncValue<List<BoardReminderAlert>>.loading();
  }

  final allBoardIds = boards.isEmpty
      ? <String>{snapshot.board.boardId}
      : {for (final board in boards) board.boardId};
  final visibleBoardIds = selectedBoardIds.isEmpty
      ? allBoardIds
      : allBoardIds.intersection(selectedBoardIds);
  final resolvedVisibleBoardIds = visibleBoardIds.isEmpty
      ? <String>{snapshot.board.boardId}
      : visibleBoardIds;

  final snapshots = <BoardSnapshot>[];
  final boardNamesById = <String, String>{
    snapshot.board.boardId: snapshot.board.name
  };

  for (final boardId in resolvedVisibleBoardIds) {
    final boardSnapshotAsync = boardId == snapshot.board.boardId
        ? boardAsync
        : ref.watch(boardSnapshotProvider(boardId));
    if (boardSnapshotAsync.hasError) {
      return AsyncValue<List<BoardReminderAlert>>.error(
        boardSnapshotAsync.error!,
        boardSnapshotAsync.stackTrace ?? StackTrace.current,
      );
    }
    final boardSnapshot = boardSnapshotAsync.valueOrNull;
    if (boardSnapshot == null) {
      return const AsyncValue<List<BoardReminderAlert>>.loading();
    }
    snapshots.add(boardSnapshot);
    boardNamesById[boardSnapshot.board.boardId] = boardSnapshot.board.name;
  }

  final reminders = <BoardReminderAlert>[];
  for (final boardSnapshot in snapshots) {
    final columnsById = {
      for (final column in boardSnapshot.columns) column.columnId: column,
    };
    reminders.addAll(
      NotificationReminderPolicy.buildActiveReminders(
        items: boardSnapshot.items,
        columnsById: columnsById,
        preferences: preferences,
        now: now,
        boardNamesById: boardNamesById,
      ),
    );
  }
  reminders.sort(NotificationReminderPolicy.compareActiveReminders);
  return AsyncValue<List<BoardReminderAlert>>.data(reminders);
});

final boardFlowNowProvider = Provider<DateTime>((ref) {
  return ref.watch(reminderClockProvider).valueOrNull ?? DateTime.now();
});

final boardFlowSnapshotProvider =
    Provider<AsyncValue<BoardFlowSnapshot>>((ref) {
  final boardAsync = ref.watch(boardStreamProvider);
  final boardsAsync = ref.watch(boardsProvider);
  final remindersAsync = ref.watch(boardActiveRemindersProvider);
  final selectedBoardIds = ref.watch(workspaceSelectedBoardIdsProvider);
  final visibleTypes = ref.watch(boardFlowVisibleTypesProvider);
  final suppressedItems = ref.watch(boardFlowSuppressedItemsProvider);
  final reviewedItems = ref.watch(boardFlowReviewedItemsProvider);
  final now = ref.watch(boardFlowNowProvider);

  if (boardAsync.hasError) {
    return AsyncValue<BoardFlowSnapshot>.error(
      boardAsync.error!,
      boardAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (boardsAsync.hasError) {
    return AsyncValue<BoardFlowSnapshot>.error(
      boardsAsync.error!,
      boardsAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (remindersAsync.hasError) {
    return AsyncValue<BoardFlowSnapshot>.error(
      remindersAsync.error!,
      remindersAsync.stackTrace ?? StackTrace.current,
    );
  }

  final snapshot = boardAsync.valueOrNull;
  final boards = boardsAsync.valueOrNull;
  final reminders = remindersAsync.valueOrNull;
  if (snapshot == null || boards == null || reminders == null) {
    return const AsyncValue<BoardFlowSnapshot>.loading();
  }

  final allBoardIds = boards.isEmpty
      ? <String>{snapshot.board.boardId}
      : {for (final board in boards) board.boardId};
  final visibleBoardIds = selectedBoardIds.isEmpty
      ? allBoardIds
      : allBoardIds.intersection(selectedBoardIds);
  final resolvedVisibleBoardIds = visibleBoardIds.isEmpty
      ? <String>{snapshot.board.boardId}
      : visibleBoardIds;

  final visibleBoards = boards.isEmpty
      ? <Board>[snapshot.board]
      : boards
          .where((board) => resolvedVisibleBoardIds.contains(board.boardId))
          .toList(growable: false);

  final snapshots = <BoardSnapshot>[];
  final itemsByBoardId = <String, List<WorkItem>>{};
  final settingsByBoardId = <String, BoardValidationSettings>{};

  for (final boardId in resolvedVisibleBoardIds) {
    final boardSnapshotAsync = boardId == snapshot.board.boardId
        ? boardAsync
        : ref.watch(boardSnapshotProvider(boardId));
    if (boardSnapshotAsync.hasError) {
      return AsyncValue<BoardFlowSnapshot>.error(
        boardSnapshotAsync.error!,
        boardSnapshotAsync.stackTrace ?? StackTrace.current,
      );
    }
    final boardSnapshot = boardSnapshotAsync.valueOrNull;
    if (boardSnapshot == null) {
      return const AsyncValue<BoardFlowSnapshot>.loading();
    }
    snapshots.add(boardSnapshot);
    itemsByBoardId[boardId] = boardSnapshot.items;
    settingsByBoardId[boardId] = boardSnapshot.board.validationSettings;
  }

  final accentColorValuesByItemKey = resolveItemAccentColorValues(
    itemsByBoardId: itemsByBoardId,
    settingsByBoardId: settingsByBoardId,
  );

  final flowSnapshot = BoardFlowPolicy.build(
    boards: visibleBoards,
    snapshots: snapshots,
    reminders: reminders,
    visibleTypes: visibleTypes,
    suppressedItems: suppressedItems,
    reviewedItems: reviewedItems,
    now: now,
    accentColorValuesByItemKey: accentColorValuesByItemKey,
  );
  return AsyncValue<BoardFlowSnapshot>.data(flowSnapshot);
});

final workspaceVisibleReminderTopNoticeProvider =
    Provider<AsyncValue<BoardReminderAlert?>>((ref) {
  final remindersAsync = ref.watch(boardActiveRemindersProvider);
  final dismissed = ref.watch(dismissedReminderTopNoticeUntilProvider);
  final now = ref.watch(reminderClockProvider).valueOrNull ?? DateTime.now();

  return remindersAsync.whenData((reminders) {
    for (final reminder in reminders) {
      final dismissedUntilMillis = dismissed[reminder.reminderId];
      if (dismissedUntilMillis == null) return reminder;
      final dismissedUntil =
          DateTime.fromMillisecondsSinceEpoch(dismissedUntilMillis);
      if (!dismissedUntil.isAfter(now)) return reminder;
    }
    return null;
  });
});

final workspaceSystemNoticesProvider = Provider<List<WorkspaceSystemNotice>>((
  ref,
) {
  final syncUiState = ref.watch(syncUiStateProvider);
  final outboxStatus = ref.watch(outboxStatusProvider).valueOrNull;
  final pendingCount = ref.watch(pendingOutboxCountProvider).valueOrNull ?? 0;
  final notices = <WorkspaceSystemNotice>[];
  final lastReport = syncUiState.lastReport;

  if ((lastReport?.permissionDenied ?? 0) > 0) {
    notices.add(
      WorkspaceSystemNotice(
        noticeId: 'sync-permission-denied',
        kind: WorkspaceSystemNoticeKind.permissionDenied,
        title: 'Some changes were denied',
        message:
            '${lastReport!.permissionDenied} change(s) were dropped because of board access or permissions.',
        severity: WorkspaceAttentionSeverity.critical,
        stateToken:
            '${lastReport.permissionDenied}|${lastReport.permissionDeniedOperationIds.join(",")}',
        primaryAction: const WorkspaceNoticeAction(
          kind: WorkspaceNoticeActionKind.reviewSync,
          label: 'Review',
        ),
      ),
    );
  }

  final syncFailureMessage = syncUiState.lastError ?? outboxStatus?.latestError;
  if (!syncUiState.isSyncing && syncFailureMessage != null) {
    notices.add(
      WorkspaceSystemNotice(
        noticeId: 'sync-failed',
        kind: WorkspaceSystemNoticeKind.syncFailed,
        title: 'Sync failed',
        message:
            syncFailureMessage.replaceFirst(RegExp(r'^Sync failed:\\s*'), ''),
        severity: WorkspaceAttentionSeverity.critical,
        stateToken:
            '${syncUiState.lastFailureAt?.millisecondsSinceEpoch}|$syncFailureMessage|$pendingCount',
        primaryAction: const WorkspaceNoticeAction(
          kind: WorkspaceNoticeActionKind.retrySync,
          label: 'Retry now',
        ),
        secondaryAction: const WorkspaceNoticeAction(
          kind: WorkspaceNoticeActionKind.reviewSync,
          label: 'Details',
        ),
      ),
    );
  } else if (!syncUiState.isSyncing &&
      outboxStatus != null &&
      outboxStatus.retryScheduledCount > 0) {
    notices.add(
      WorkspaceSystemNotice(
        noticeId: 'sync-retry-scheduled',
        kind: WorkspaceSystemNoticeKind.retryScheduled,
        title: 'Sync needs attention',
        message: outboxStatus.nextRetryAt == null
            ? '$pendingCount pending change(s). Auto-retry is scheduled soon.'
            : '$pendingCount pending change(s). Auto-retry is scheduled soon.',
        severity: WorkspaceAttentionSeverity.warning,
        stateToken:
            '${outboxStatus.retryScheduledCount}|${outboxStatus.failedCount}|${outboxStatus.nextRetryAt?.millisecondsSinceEpoch}|${outboxStatus.latestError ?? ""}',
        primaryAction: const WorkspaceNoticeAction(
          kind: WorkspaceNoticeActionKind.retrySync,
          label: 'Retry now',
        ),
        secondaryAction: const WorkspaceNoticeAction(
          kind: WorkspaceNoticeActionKind.reviewSync,
          label: 'Details',
        ),
      ),
    );
  }

  return notices;
});

final workspaceVisibleSystemNoticesProvider =
    Provider<List<WorkspaceSystemNotice>>((ref) {
  final dismissedKeys = ref.watch(dismissedSystemNoticeKeysProvider);
  return ref
      .watch(workspaceSystemNoticesProvider)
      .where((notice) => !dismissedKeys.contains(notice.dismissalKey))
      .toList(growable: false);
});

final workspaceTopAttentionNoticeProvider =
    Provider<AsyncValue<WorkspaceAttentionNotice?>>((ref) {
  final systemNotices = ref.watch(workspaceVisibleSystemNoticesProvider);
  if (systemNotices.isNotEmpty) {
    return AsyncValue.data(
      WorkspaceAttentionNotice.fromSystem(systemNotices.first),
    );
  }

  final reminderNoticeAsync =
      ref.watch(workspaceVisibleReminderTopNoticeProvider);
  return reminderNoticeAsync.whenData(
    (reminder) => reminder == null
        ? null
        : WorkspaceAttentionNotice.fromReminder(reminder),
  );
});

final scheduledBoardRemindersProvider =
    FutureProvider<List<BoardScheduledReminder>>((ref) async {
  final schedulingEnabled =
      !useFirebaseAuth || ref.watch(activeUserIdProvider) != null;
  if (!schedulingEnabled) return const <BoardScheduledReminder>[];

  ref.watch(reminderClockProvider);
  ref.watch(boardsProvider);
  ref.watch(boardStreamProvider);
  final now = ref.watch(reminderClockProvider).valueOrNull ?? DateTime.now();
  final preferences = await ref.watch(notificationPreferencesProvider.future);
  final store = ref.watch(localBoardStoreProvider);
  final boards = await store.listBoards();
  final snapshots = <BoardSnapshot>[];
  for (final board in boards) {
    try {
      snapshots.add(await store.getBoard(board.boardId));
    } catch (_) {
      // Skip boards that disappeared between list/read.
    }
  }
  return NotificationReminderPolicy.buildScheduledReminders(
    snapshots: snapshots,
    preferences: preferences,
    now: now,
  );
});

final boardBackupsProvider = FutureProvider<List<BoardBackupFile>>((ref) {
  ref.watch(boardScopeUserIdProvider);
  return ref.watch(boardBackupRepositoryProvider).listBackups();
});

final workItemActivityTimelineProvider = FutureProvider.family
    .autoDispose<List<WorkItemActivityEvent>, String>((ref, itemId) {
  final boardId = ref.watch(currentBoardIdProvider);
  return ref.watch(workItemActivityRepositoryProvider).listForItem(
        boardId: boardId,
        itemId: itemId,
      );
});

final selectedBoardInsightsRangeProvider =
    StateProvider<BoardInsightsRange>((ref) => BoardInsightsRange.sevenDays);

final boardInsightsNowProvider = Provider<DateTime>((ref) {
  return ref.watch(reminderClockProvider).valueOrNull ?? DateTime.now();
});

final boardInsightsProvider =
    FutureProvider<BoardInsightsSnapshot>((ref) async {
  final snapshot = await ref.watch(boardStreamProvider.future);
  final range = ref.watch(selectedBoardInsightsRangeProvider);
  final now = ref.watch(boardInsightsNowProvider);
  final activitySince = switch (range) {
    BoardInsightsRange.sevenDays =>
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
    BoardInsightsRange.thirtyDays =>
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
    BoardInsightsRange.ninetyDays =>
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 89)),
    BoardInsightsRange.allTime => null,
  };
  final boardActivity =
      await ref.watch(workItemActivityRepositoryProvider).listForBoard(
            boardId: snapshot.board.boardId,
            since: activitySince,
            limit: 5000,
          );
  return BoardInsightsPolicy.build(
    snapshot: snapshot,
    boardActivity: boardActivity,
    range: range,
    now: now,
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

  void _invalidateReminderDerivedState() {
    _ref.invalidate(boardActiveRemindersProvider);
    _ref.invalidate(scheduledBoardRemindersProvider);
  }

  void switchBoard(String boardId) {
    _ref.read(currentBoardIdProvider.notifier).state = boardId;
  }

  void clearFocusedItem() {
    _ref.read(focusedItemIdProvider.notifier).state = null;
    _ref.read(selectedHierarchyItemIdProvider.notifier).state = null;
    _ref.read(focusModeEnabledProvider.notifier).state = false;
  }

  void setPlanningView(BoardPlanningView view) {
    _ref.read(boardPlanningViewProvider.notifier).state = view;
    _ref.read(selectedHierarchyItemIdProvider.notifier).state = null;
    if (view != BoardPlanningView.hierarchy) return;

    _ref.read(boardVisibilityFilterProvider.notifier).state = <WorkItemType>{};
    _ref.read(boardItemStateFilterProvider.notifier).state =
        BoardItemStateFilter.any;
    _ref.read(boardTagFilterProvider.notifier).state = '';
    _ref.read(boardTextQueryProvider.notifier).state = '';
    _ref.read(workspaceSearchExpandedProvider.notifier).state = false;
    _ref.read(focusModeEnabledProvider.notifier).state = false;
    _ref.read(focusedItemIdProvider.notifier).state = null;
    _ref.read(showOverdueOnlyProvider.notifier).state = false;
    _ref.read(showDueSoonOnlyProvider.notifier).state = false;
    _ref.read(showArchivedOnlyProvider.notifier).state = false;
    _ref.read(collapsedHierarchyItemIdsProvider.notifier).state = <String>{};
  }

  Future<void> createBoard(String name) async {
    final board = await _repository.createBoard(name);
    _ref.invalidate(boardsProvider);
    _ref.invalidate(boardBackupsProvider);
    _invalidateReminderDerivedState();
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
    _ref.invalidate(boardBackupsProvider);
    _invalidateReminderDerivedState();

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
    BoardValidationSettings settings, {
    String? boardId,
  }) async {
    final resolvedBoardId =
        boardId ?? _ref.read(currentBoardIdProvider.notifier).state;
    await _repository.updateBoardValidationSettings(
      boardId: resolvedBoardId,
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
  }) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.createTask(
      boardId: boardId,
      title: title,
      toColumnId: toColumnId,
    );
    _invalidateReminderDerivedState();
  }

  Future<WorkItem> createItem({
    required String title,
    required WorkItemType type,
    required String toColumnId,
    String? boardId,
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
    final resolvedBoardId =
        boardId ?? _ref.read(currentBoardIdProvider.notifier).state;
    final created = await _repository.createItem(
      boardId: resolvedBoardId,
      title: title,
      type: type,
      toColumnId: toColumnId,
      parentId: parentId,
      description: description,
      startAt: startAt,
      targetEndAt: targetEndAt,
      dueAt: dueAt,
      tags: tags,
      estimatedEffortMinutes: estimatedEffortMinutes,
      actualEffortMinutes: actualEffortMinutes,
      recurrence: recurrence,
    );
    _invalidateReminderDerivedState();
    return created;
  }

  Future<void> createInboxCapture({
    required String title,
    List<String> tags = const [],
  }) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.createInboxCapture(
      boardId: boardId,
      title: title,
      tags: tags,
    );
    _invalidateReminderDerivedState();
  }

  Future<void> triageInboxItem({
    required String itemId,
    required String toBoardId,
    required String toColumnId,
    required WorkItemType type,
    String? parentId,
  }) async {
    final fromBoardId = _ref.read(currentBoardIdProvider);
    await _repository.triageInboxItem(
      fromBoardId: fromBoardId,
      itemId: itemId,
      toBoardId: toBoardId,
      toColumnId: toColumnId,
      type: type,
      parentId: parentId,
    );
    _invalidateReminderDerivedState();
  }

  Future<void> moveItem({
    required String itemId,
    required String toColumnId,
    String? boardId,
  }) async {
    final resolvedBoardId =
        boardId ?? _ref.read(currentBoardIdProvider.notifier).state;
    await _repository.moveItem(
      boardId: resolvedBoardId,
      itemId: itemId,
      toColumnId: toColumnId,
    );
    _invalidateReminderDerivedState();
  }

  Future<void> reorderItem({
    required String itemId,
    String? boardId,
    String? toColumnId,
    String? parentId,
    bool clearParent = false,
    String? beforeItemId,
    String? afterItemId,
  }) async {
    final resolvedBoardId =
        boardId ?? _ref.read(currentBoardIdProvider.notifier).state;
    await _repository.reorderItem(
      boardId: resolvedBoardId,
      itemId: itemId,
      toColumnId: toColumnId,
      parentId: parentId,
      clearParent: clearParent,
      beforeItemId: beforeItemId,
      afterItemId: afterItemId,
    );
    _invalidateReminderDerivedState();
  }

  Future<void> moveItemToBoard({
    required String itemId,
    required String toBoardId,
    required String toColumnId,
  }) async {
    final fromBoardId = _ref.read(currentBoardIdProvider);
    await _repository.moveItemToBoard(
      fromBoardId: fromBoardId,
      itemId: itemId,
      toBoardId: toBoardId,
      toColumnId: toColumnId,
    );
    _invalidateReminderDerivedState();
  }

  Future<void> updateItem({
    required String itemId,
    String? boardId,
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
    final resolvedBoardId =
        boardId ?? _ref.read(currentBoardIdProvider.notifier).state;
    await _repository.updateItem(
      boardId: resolvedBoardId,
      itemId: itemId,
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
    );
    _invalidateReminderDerivedState();
  }

  Future<void> reparentItem({
    required String itemId,
    String? boardId,
    String? parentId,
    bool clearParent = false,
  }) async {
    final resolvedBoardId =
        boardId ?? _ref.read(currentBoardIdProvider.notifier).state;
    await _repository.reparentItem(
      boardId: resolvedBoardId,
      itemId: itemId,
      parentId: parentId,
      clearParent: clearParent,
    );
    _invalidateReminderDerivedState();
  }

  Future<void> deleteItem({
    required String itemId,
    String? boardId,
  }) async {
    final resolvedBoardId =
        boardId ?? _ref.read(currentBoardIdProvider.notifier).state;
    await _repository.deleteItem(boardId: resolvedBoardId, itemId: itemId);
    _invalidateReminderDerivedState();
  }

  void clearPendingUndo({String? operationId}) {
    final pending = _ref.read(pendingBoardUndoOperationProvider);
    if (pending == null) return;
    if (operationId != null && pending.operationId != operationId) return;
    _ref.read(pendingBoardUndoOperationProvider.notifier).state = null;
  }

  void dismissReminderTopNotice({
    required String reminderId,
    Duration duration = const Duration(minutes: 60),
  }) {
    final next = Map<String, int>.from(
      _ref.read(dismissedReminderTopNoticeUntilProvider),
    );
    next[reminderId] = DateTime.now().add(duration).millisecondsSinceEpoch;
    _ref.read(dismissedReminderTopNoticeUntilProvider.notifier).state = next;
  }

  void dismissSystemNotice({
    required String noticeId,
    required String stateToken,
  }) {
    final next = Set<String>.from(_ref.read(dismissedSystemNoticeKeysProvider));
    next.add('$noticeId|$stateToken');
    _ref.read(dismissedSystemNoticeKeysProvider.notifier).state = next;
  }

  void enqueueWorkspaceFeedback(
    String message, {
    WorkspaceFeedbackSeverity severity = WorkspaceFeedbackSeverity.error,
    Duration? duration,
  }) {
    final now = DateTime.now();
    final effectiveDuration = duration ??
        switch (severity) {
          WorkspaceFeedbackSeverity.info => const Duration(milliseconds: 2500),
          WorkspaceFeedbackSeverity.success =>
            const Duration(milliseconds: 2500),
          WorkspaceFeedbackSeverity.error => const Duration(milliseconds: 4000),
        };
    final feedback = WorkspaceFeedbackMessage(
      feedbackId: 'feedback-${now.microsecondsSinceEpoch}',
      message: message,
      severity: severity,
      createdAt: now,
      expiresAt: now.add(effectiveDuration),
    );
    final next = [..._ref.read(workspaceFeedbackQueueProvider), feedback];
    _ref.read(workspaceFeedbackQueueProvider.notifier).state = next;
  }

  void dismissWorkspaceFeedback(String feedbackId) {
    _ref.read(workspaceFeedbackQueueProvider.notifier).state = _ref
        .read(workspaceFeedbackQueueProvider)
        .where((message) => message.feedbackId != feedbackId)
        .toList(growable: false);
  }

  BoardUndoOperation stageMoveUndo({
    required WorkItem item,
    required String fromBoardId,
    required String fromColumnId,
    required String toBoardId,
    required String toColumnId,
    String? message,
  }) {
    final now = DateTime.now();
    final op = BoardUndoOperation(
      operationId: 'undo-${now.microsecondsSinceEpoch}',
      kind: BoardUndoOperationKind.move,
      itemId: item.itemId,
      message: message ?? 'Item moved',
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

  BoardUndoOperation stageDueDateUndo({
    required WorkItem item,
    required DateTime? fromDueAt,
    required DateTime? toDueAt,
  }) {
    final now = DateTime.now();
    final op = BoardUndoOperation(
      operationId: 'undo-${now.microsecondsSinceEpoch}',
      kind: BoardUndoOperationKind.rescheduleDueDate,
      itemId: item.itemId,
      message: fromDueAt == null ? 'Due date scheduled' : 'Due date updated',
      createdAt: now,
      expiresAt: now.add(undoWindow),
      fromBoardId: item.boardId,
      toBoardId: item.boardId,
      fromDueAt: fromDueAt,
      toDueAt: toDueAt,
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
      case BoardUndoOperationKind.rescheduleDueDate:
        final String boardId =
            pending.fromBoardId ?? _ref.read(currentBoardIdProvider);
        await _repository.updateItem(
          boardId: boardId,
          itemId: pending.itemId,
          dueAt: pending.fromDueAt,
          clearDueAt: pending.fromDueAt == null,
        );
        break;
    }

    clearPendingUndo(operationId: pending.operationId);
    return true;
  }

  Future<void> bulkUpdateItems({
    required List<String> itemIds,
    String? boardId,
    String? toColumnId,
    bool? archived,
    List<String> addTags = const [],
    List<String> removeTags = const [],
  }) async {
    final resolvedBoardId =
        boardId ?? _ref.read(currentBoardIdProvider.notifier).state;
    await _repository.bulkUpdateItems(
      boardId: resolvedBoardId,
      itemIds: itemIds,
      toColumnId: toColumnId,
      archived: archived,
      addTags: addTags,
      removeTags: removeTags,
    );
    _invalidateReminderDerivedState();
  }

  Future<BoardBackupFile> exportCurrentBoardBackup() async {
    final boardId = _ref.read(currentBoardIdProvider);
    final backup = await _ref.read(boardBackupRepositoryProvider).exportBoard(
          boardId: boardId,
        );
    _ref.invalidate(boardBackupsProvider);
    return backup;
  }

  Future<Board> importBoardBackup({
    required String backupPath,
  }) async {
    final board = await _ref.read(boardBackupRepositoryProvider).importBackup(
          backupPath: backupPath,
        );
    _ref.invalidate(boardsProvider);
    _ref.invalidate(boardBackupsProvider);
    _invalidateReminderDerivedState();
    _ref.read(currentBoardIdProvider.notifier).state = board.boardId;
    return board;
  }

  Future<void> deleteBoardBackup({
    required String backupPath,
  }) async {
    await _ref.read(boardBackupRepositoryProvider).deleteBackup(
          backupPath: backupPath,
        );
    _ref.invalidate(boardBackupsProvider);
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

    final selectedTypes = _ref.read(boardVisibilityFilterProvider).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final calendarVisibleDateKinds = _ref
        .read(boardCalendarVisibleDateKindsProvider)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final normalizedName = name.trim();
    final next = BoardFilterPreset(
      presetId:
          presetId ?? 'preset-${now.microsecondsSinceEpoch}-${now.second}',
      name: normalizedName,
      visibilityFilter: _legacyVisibilityFilterName(selectedTypes.toSet()),
      selectedTypes: selectedTypes.map((type) => type.name).toList(),
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
      calendarSubview: _ref.read(boardCalendarSubviewProvider).name,
      calendarVisibleDateKinds:
          calendarVisibleDateKinds.map((kind) => kind.name).toList(),
      showCalendarUnscheduled: _ref.read(boardCalendarShowUnscheduledProvider),
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
        preset.resolvedSelectedTypes();
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
    _ref.read(boardCalendarSubviewProvider.notifier).state =
        BoardCalendarSubview.values.firstWhere(
      (entry) => entry.name == preset.calendarSubview,
      orElse: () => BoardCalendarSubview.month,
    );
    _ref.read(boardCalendarVisibleDateKindsProvider.notifier).state =
        preset.calendarVisibleDateKinds
            .map(
              (name) => BoardCalendarMarkerKind.values.where(
                (entry) => entry.name == name,
              ),
            )
            .where((matches) => matches.isNotEmpty)
            .map((matches) => matches.first)
            .toSet();
    _ref.read(boardCalendarShowUnscheduledProvider.notifier).state =
        preset.showCalendarUnscheduled;
    setPlanningView(
      BoardPlanningView.values.firstWhere(
        (entry) => entry.name == preset.planningView,
        orElse: () => BoardPlanningView.kanban,
      ),
    );
    _ref.read(boardWorkspaceSurfaceProvider.notifier).state =
        BoardWorkspaceSurface.values.firstWhere(
      (entry) => entry.name == preset.workspaceSurface,
      orElse: () => BoardWorkspaceSurface.board,
    );
  }

  String _legacyVisibilityFilterName(Set<WorkItemType> types) {
    if (types.length != 1) return BoardVisibilityFilter.allItems.name;
    return switch (types.first) {
      WorkItemType.goal => BoardVisibilityFilter.goalsOnly.name,
      WorkItemType.project => BoardVisibilityFilter.projectsOnly.name,
      WorkItemType.task => BoardVisibilityFilter.tasksOnly.name,
      WorkItemType.action => BoardVisibilityFilter.actionsOnly.name,
    };
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

  Future<BoardCalendarPreferences> updateCalendarPreferences(
    BoardCalendarPreferences preferences,
  ) async {
    final saved = await _ref
        .read(boardCalendarPreferencesRepositoryProvider)
        .save(preferences);
    _ref.invalidate(boardCalendarPreferencesProvider);
    return saved;
  }

  Future<void> setCalendarSubview(BoardCalendarSubview subview) async {
    _ref.read(boardCalendarSubviewProvider.notifier).state = subview;
    final current = await _ref.read(boardCalendarPreferencesProvider.future);
    await updateCalendarPreferences(current.copyWith(lastSubview: subview));
  }

  Future<void> setCalendarVisibleDateKinds(
    Set<BoardCalendarMarkerKind> kinds,
  ) async {
    _ref.read(boardCalendarVisibleDateKindsProvider.notifier).state = kinds;
    final current = await _ref.read(boardCalendarPreferencesProvider.future);
    await updateCalendarPreferences(current.copyWith(visibleDateKinds: kinds));
  }

  Future<void> setCalendarShowUnscheduled(bool showUnscheduled) async {
    _ref.read(boardCalendarShowUnscheduledProvider.notifier).state =
        showUnscheduled;
    final current = await _ref.read(boardCalendarPreferencesProvider.future);
    await updateCalendarPreferences(
      current.copyWith(showUnscheduled: showUnscheduled),
    );
  }

  void setCalendarAnchorDate(DateTime anchorDate) {
    _ref.read(boardCalendarAnchorDateProvider.notifier).state = DateTime(
      anchorDate.year,
      anchorDate.month,
      anchorDate.day,
    );
  }

  Future<BoardFlowPreferences> updateFlowPreferences(
    BoardFlowPreferences preferences,
  ) async {
    final saved = await _ref
        .read(boardFlowPreferencesRepositoryProvider)
        .save(preferences);
    _ref.invalidate(boardFlowPreferencesProvider);
    return saved;
  }

  Future<void> setFlowVisibleTypes(Set<WorkItemType> visibleTypes) async {
    _ref.read(boardFlowVisibleTypesProvider.notifier).state = visibleTypes;
    final current = await _ref.read(boardFlowPreferencesProvider.future);
    await updateFlowPreferences(
      current.copyWith(visibleTypes: visibleTypes),
    );
  }

  Future<void> setFlowMotionEnabled(bool motionEnabled) async {
    _ref.read(boardFlowMotionEnabledProvider.notifier).state = motionEnabled;
    final current = await _ref.read(boardFlowPreferencesProvider.future);
    await updateFlowPreferences(
      current.copyWith(motionEnabled: motionEnabled),
    );
  }

  Future<void> setFlowMotionSpeed(double motionSpeed) async {
    final normalized = motionSpeed.clamp(
      boardFlowMinMotionSpeed,
      boardFlowMaxMotionSpeed,
    );
    _ref.read(boardFlowMotionSpeedProvider.notifier).state = normalized;
    final current = await _ref.read(boardFlowPreferencesProvider.future);
    await updateFlowPreferences(
      current.copyWith(motionSpeed: normalized),
    );
  }

  Future<void> suppressFlowItemUntilTomorrowMorning({
    required WorkItem item,
    required String stateToken,
  }) async {
    final current = await _ref.read(boardFlowPreferencesProvider.future);
    final nextSuppressed = Map<String, BoardFlowSuppressionEntry>.from(
      current.suppressedItems,
    )..['${item.boardId}::${item.itemId}'] = BoardFlowSuppressionEntry(
        untilEpochMillis:
            _nextLocalMorningAtEight(DateTime.now()).millisecondsSinceEpoch,
        stateToken: stateToken,
      );

    _ref.read(boardFlowSuppressedItemsProvider.notifier).state = nextSuppressed;
    await updateFlowPreferences(
      current.copyWith(suppressedItems: nextSuppressed),
    );
  }

  Future<void> markFlowItemReviewedToday({
    required WorkItem item,
    required String stateToken,
  }) async {
    final current = await _ref.read(boardFlowPreferencesProvider.future);
    final todayKey = boardFlowDayKey(DateTime.now());
    final nextReviewed = <String, BoardFlowReviewedEntry>{
      for (final entry in current.reviewedItems.entries)
        if (entry.value.dayKey == todayKey) entry.key: entry.value,
    }..['${item.boardId}::${item.itemId}'] = BoardFlowReviewedEntry(
        dayKey: todayKey,
        stateToken: stateToken,
      );

    _ref.read(boardFlowReviewedItemsProvider.notifier).state = nextReviewed;
    await updateFlowPreferences(
      current.copyWith(reviewedItems: nextReviewed),
    );
  }

  Future<NotificationPreferences> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final saved = await _ref
        .read(notificationPreferencesRepositoryProvider)
        .save(preferences);
    _ref.invalidate(notificationPreferencesProvider);
    _invalidateReminderDerivedState();
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

  Future<bool> completeReminderAsDone({
    required String boardId,
    required String itemId,
  }) async {
    final snapshot = await _ref.read(localBoardStoreProvider).getBoard(boardId);
    final item = snapshot.items
        .where((entry) => entry.itemId == itemId)
        .cast<WorkItem?>()
        .firstWhere((_) => true, orElse: () => null);
    if (item == null) return false;
    if (!NotificationReminderPolicy.supportsQuickComplete(item)) {
      return false;
    }
    final doneColumn = WorkflowSemanticsPolicy.doneColumn(snapshot.columns);
    if (doneColumn == null) return false;
    if (item.columnId == doneColumn.columnId && item.completedAt != null) {
      _invalidateReminderDerivedState();
      return true;
    }

    stageMoveUndo(
      item: item,
      fromBoardId: boardId,
      fromColumnId: item.columnId,
      toBoardId: boardId,
      toColumnId: doneColumn.columnId,
      message: 'Item completed',
    );
    await _repository.moveItem(
      boardId: boardId,
      itemId: itemId,
      toColumnId: doneColumn.columnId,
    );
    _invalidateReminderDerivedState();
    return true;
  }

  Future<SyncRunReport> syncNow({bool ignoreRetrySchedule = true}) async {
    final now = DateTime.now();
    _ref.read(syncUiStateProvider.notifier).state =
        _ref.read(syncUiStateProvider).copyWith(
              isSyncing: true,
              lastAttemptAt: now,
              clearLastError: true,
            );

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

DateTime _nextLocalMorningAtEight(DateTime now) {
  final todayAtEight = DateTime(now.year, now.month, now.day, 8);
  if (now.isBefore(todayAtEight)) {
    return todayAtEight;
  }
  final tomorrow = now.add(const Duration(days: 1));
  return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8);
}
