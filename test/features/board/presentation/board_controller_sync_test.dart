import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/core/outbox/outbox_operation.dart';
import 'package:plandone/src/core/sync/sync_remote_adapter.dart';
import 'package:plandone/src/features/board/data/local/in_memory_local_board_store.dart';
import 'package:plandone/src/features/board/presentation/board_controller.dart';

class _FakeRemoteAdapter implements SyncRemoteAdapter {
  _FakeRemoteAdapter({this.shouldFail = false});

  final bool shouldFail;
  final List<String> appliedOperationIds = <String>[];

  @override
  Future<void> applyOperation(OutboxOperation operation) async {
    if (shouldFail) {
      throw Exception('network unavailable');
    }
    appliedOperationIds.add(operation.id);
  }
}

void main() {
  test('syncNow updates sync UI state and clears processed outbox operations',
      () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final queue = InMemoryOutboxQueue();
    final remote = _FakeRemoteAdapter();
    final now = DateTime.now();
    await queue.enqueue(
      OutboxOperation(
        id: 'op-sync-success',
        type: OutboxOperationType.create,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'version': 1, 'boardId': 'board-1'},
        createdAt: now,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        localBoardStoreProvider.overrideWith((ref) => localStore),
        outboxQueueProvider.overrideWith((ref) => queue),
        syncRemoteAdapterProvider.overrideWith((ref) => remote),
      ],
    );
    addTearDown(container.dispose);

    final report = await container
        .read(boardControllerProvider)
        .syncNow(ignoreRetrySchedule: true);

    final pendingAfter = await queue.listPending();
    final uiState = container.read(syncUiStateProvider);
    expect(report.processed, 1);
    expect(report.failed, 0);
    expect(remote.appliedOperationIds, ['op-sync-success']);
    expect(pendingAfter, isEmpty);
    expect(uiState.isSyncing, isFalse);
    expect(uiState.lastSuccessAt, isNotNull);
    expect(uiState.lastError, isNull);
  });

  test('outbox status provider summarizes retry scheduling metadata', () async {
    final localStore = InMemoryLocalBoardStore(currentUserId: 'user-1');
    final queue = InMemoryOutboxQueue();
    final now = DateTime.now();
    await queue.enqueue(
      OutboxOperation(
        id: 'op-retryable',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: 'w-2',
        payload: const {'version': 1, 'boardId': 'board-1'},
        createdAt: now.subtract(const Duration(seconds: 30)),
        attemptCount: 2,
        lastError: 'network timeout',
        nextAttemptAt: now.add(const Duration(minutes: 2)),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        localBoardStoreProvider.overrideWith((ref) => localStore),
        outboxQueueProvider.overrideWith((ref) => queue),
      ],
    );
    addTearDown(container.dispose);

    final status = await container.read(outboxStatusProvider.future);
    expect(status.pendingCount, 1);
    expect(status.retryScheduledCount, 1);
    expect(status.failedCount, 1);
    expect(status.nextRetryAt, isNotNull);
    expect(status.latestError, 'network timeout');
  });
}
