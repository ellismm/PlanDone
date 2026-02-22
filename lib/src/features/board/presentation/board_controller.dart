import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/outbox/in_memory_outbox_queue.dart';
import '../../../core/outbox/drift_outbox_queue.dart';
import '../../../core/outbox/outbox_queue.dart';
import '../../../core/sync/in_memory_sync_remote_adapter.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_remote_adapter.dart';
import '../data/local/drift/board_database.dart' as drift_db;
import '../data/local/drift/drift_local_board_store.dart';
import '../data/local/in_memory_local_board_store.dart';
import '../data/local/local_board_store.dart';
import '../data/repositories/board_repository_impl.dart';
import '../domain/models/board.dart';
import '../domain/models/board_snapshot.dart';
import '../domain/models/work_item.dart';
import '../domain/models/work_item_type.dart';
import '../domain/repositories/board_repository.dart';

const defaultBoardId = 'board-1';
const currentUserId = 'user-1';

enum BoardVisibilityFilter { tasksOnly, goalsOnly, projectsOnly, actionsOnly, allItems }

final boardDatabaseProvider = Provider<drift_db.BoardDatabase>((ref) {
  final db = drift_db.BoardDatabase();
  ref.onDispose(db.close);
  return db;
});

final localBoardStoreProvider = Provider<LocalBoardStore>((ref) {
  const useDrift = bool.fromEnvironment('USE_DRIFT_LOCAL_STORE', defaultValue: false);
  if (useDrift) {
    return DriftLocalBoardStore(database: ref.watch(boardDatabaseProvider));
  }
  return InMemoryLocalBoardStore();
});

final outboxQueueProvider = Provider<OutboxQueue>((ref) {
  const useDrift = bool.fromEnvironment('USE_DRIFT_LOCAL_STORE', defaultValue: false);
  if (useDrift) {
    return DriftOutboxQueue(ref.watch(boardDatabaseProvider));
  }
  return InMemoryOutboxQueue();
});

final boardRepositoryProvider = Provider<BoardRepository>((ref) {
  return BoardRepositoryImpl(
    localStore: ref.watch(localBoardStoreProvider),
    outboxQueue: ref.watch(outboxQueueProvider),
    currentUserId: currentUserId,
  );
});

final syncRemoteAdapterProvider = Provider<SyncRemoteAdapter>((ref) {
  return InMemorySyncRemoteAdapter();
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    outboxQueue: ref.watch(outboxQueueProvider),
    remoteAdapter: ref.watch(syncRemoteAdapterProvider),
  );
});

final lastSyncReportProvider = StateProvider<SyncRunReport?>((ref) => null);

final currentBoardIdProvider = StateProvider<String>((ref) => defaultBoardId);

final boardsProvider = FutureProvider<List<Board>>((ref) {
  return ref.watch(boardRepositoryProvider).listBoards();
});

final boardStreamProvider = StreamProvider<BoardSnapshot>((ref) {
  final boardId = ref.watch(currentBoardIdProvider);
  return ref.watch(boardRepositoryProvider).watchBoard(boardId);
});

final pendingOutboxCountProvider = FutureProvider<int>((ref) async {
  // Recompute when board data changes so count updates after local operations.
  ref.watch(boardStreamProvider);
  final pending = await ref.watch(outboxQueueProvider).listPending();
  return pending.length;
});

final boardVisibilityFilterProvider = StateProvider<BoardVisibilityFilter>((ref) {
  // Spec default board filter: show tasks first.
  return BoardVisibilityFilter.tasksOnly;
});

final focusedItemIdProvider = StateProvider<String?>((ref) => null);
final focusModeEnabledProvider = StateProvider<bool>((ref) => false);
final activeDraggedItemProvider = StateProvider<WorkItem?>((ref) => null);
final boardTextQueryProvider = StateProvider<String>((ref) => '');
final showOverdueOnlyProvider = StateProvider<bool>((ref) => false);
final showDueSoonOnlyProvider = StateProvider<bool>((ref) => false);
final showArchivedOnlyProvider = StateProvider<bool>((ref) => false);

final boardControllerProvider = Provider<BoardController>((ref) {
  return BoardController(ref, ref.watch(boardRepositoryProvider));
});

class BoardController {
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

  Future<void> createColumn(String name) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.createColumn(boardId: boardId, name: name);
  }

  Future<void> renameColumn({
    required String columnId,
    required String name,
  }) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.renameColumn(boardId: boardId, columnId: columnId, name: name);
  }

  Future<void> deleteColumn(String columnId) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.deleteColumn(boardId: boardId, columnId: columnId);
  }

  Future<void> reorderColumns(List<String> orderedColumnIds) async {
    final boardId = _ref.read(currentBoardIdProvider);
    await _repository.reorderColumns(boardId: boardId, orderedColumnIds: orderedColumnIds);
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

  Future<void> createItem({
    required String title,
    required WorkItemType type,
    required String toColumnId,
    String? parentId,
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.createItem(
      boardId: boardId,
      title: title,
      type: type,
      toColumnId: toColumnId,
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
    DateTime? dueAt,
    List<String>? tags,
    bool? archived,
    bool clearParent = false,
    bool clearDescription = false,
    bool clearDueAt = false,
  }) {
    final boardId = _ref.read(currentBoardIdProvider);
    return _repository.updateItem(
      boardId: boardId,
      itemId: itemId,
      title: title,
      description: description,
      parentId: parentId,
      dueAt: dueAt,
      tags: tags,
      archived: archived,
      clearParent: clearParent,
      clearDescription: clearDescription,
      clearDueAt: clearDueAt,
    );
  }

  Future<SyncRunReport> syncNow() async {
    final report = await _ref.read(syncEngineProvider).syncPending(ignoreRetrySchedule: true);
    _ref.read(lastSyncReportProvider.notifier).state = report;
    _ref.invalidate(pendingOutboxCountProvider);
    return report;
  }
}
