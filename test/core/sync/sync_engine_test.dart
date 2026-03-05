import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/core/outbox/outbox_operation.dart';
import 'package:plandone/src/core/sync/sync_engine.dart';
import 'package:plandone/src/core/sync/sync_remote_adapter.dart';

class _FakeRemoteAdapter implements SyncRemoteAdapter {
  _FakeRemoteAdapter({
    this.failOperationIds = const <String>{},
    this.permissionDeniedOperationIds = const <String>{},
  });

  final Set<String> failOperationIds;
  final Set<String> permissionDeniedOperationIds;
  final List<String> applied = [];

  @override
  Future<void> applyOperation(OutboxOperation operation) async {
    if (permissionDeniedOperationIds.contains(operation.id)) {
      throw SyncRemotePermissionDeniedException('permission denied');
    }
    if (failOperationIds.contains(operation.id)) {
      throw StateError('Simulated remote failure');
    }
    applied.add(operation.id);
  }
}

void main() {
  test('sync engine processes pending operations and removes successful ones',
      () async {
    final queue = InMemoryOutboxQueue();
    final remote = _FakeRemoteAdapter();
    final engine = SyncEngine(outboxQueue: queue, remoteAdapter: remote);

    await queue.enqueue(
      OutboxOperation(
        id: 'op-1',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'title': 'A'},
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await queue.enqueue(
      OutboxOperation(
        id: 'op-2',
        type: OutboxOperationType.move,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'toColumnId': 'c-done'},
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    );

    final report = await engine.syncPending();

    expect(report.processed, 2);
    expect(report.failed, 0);
    expect(report.permissionDenied, 0);
    expect(await queue.listPending(), isEmpty);
    expect(remote.applied, ['op-1', 'op-2']);
  });

  test('sync engine keeps failed operations in queue and reports failures',
      () async {
    final queue = InMemoryOutboxQueue();
    final remote = _FakeRemoteAdapter(failOperationIds: const {'op-2'});
    final engine = SyncEngine(outboxQueue: queue, remoteAdapter: remote);

    await queue.enqueue(
      OutboxOperation(
        id: 'op-1',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'title': 'A'},
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await queue.enqueue(
      OutboxOperation(
        id: 'op-2',
        type: OutboxOperationType.move,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'toColumnId': 'c-done'},
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    );

    final report = await engine.syncPending();

    expect(report.processed, 1);
    expect(report.failed, 1);
    expect(report.permissionDenied, 0);
    expect(report.failedOperationIds, ['op-2']);

    final pending = await queue.listPending();
    expect(pending.map((e) => e.id), ['op-2']);
    expect(pending.first.attemptCount, 1);
    expect(pending.first.lastError, contains('Simulated remote failure'));
    expect(pending.first.nextAttemptAt, isNotNull);
    expect(pending.first.lastAttemptAt, isNotNull);
  });

  test('sync engine applies exponential backoff and respects max retry delay',
      () async {
    final queue = InMemoryOutboxQueue();
    final remote = _FakeRemoteAdapter(failOperationIds: const {'op-retry'});
    final engine = SyncEngine(
      outboxQueue: queue,
      remoteAdapter: remote,
      baseRetryDelay: const Duration(seconds: 1),
      maxRetryDelay: const Duration(seconds: 2),
    );

    await queue.enqueue(
      OutboxOperation(
        id: 'op-retry',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'title': 'A'},
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    final first = await engine.syncPending(ignoreRetrySchedule: true);
    expect(first.failed, 1);

    final afterFirst = (await queue.listPending()).single;
    final firstDelay =
        afterFirst.nextAttemptAt!.difference(afterFirst.lastAttemptAt!);
    expect(firstDelay, const Duration(seconds: 1));

    final second = await engine.syncPending(ignoreRetrySchedule: true);
    expect(second.failed, 1);

    final afterSecond = (await queue.listPending()).single;
    final secondDelay =
        afterSecond.nextAttemptAt!.difference(afterSecond.lastAttemptAt!);
    expect(secondDelay, const Duration(seconds: 2));

    final third = await engine.syncPending(ignoreRetrySchedule: true);
    expect(third.failed, 1);

    final afterThird = (await queue.listPending()).single;
    final thirdDelay =
        afterThird.nextAttemptAt!.difference(afterThird.lastAttemptAt!);
    expect(thirdDelay, const Duration(seconds: 2));
  });

  test('sync engine skips operations scheduled for future retry', () async {
    final queue = InMemoryOutboxQueue();
    final remote = _FakeRemoteAdapter();
    final engine = SyncEngine(outboxQueue: queue, remoteAdapter: remote);

    await queue.enqueue(
      OutboxOperation(
        id: 'op-future',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'title': 'A'},
        createdAt: DateTime(2026, 1, 1),
        nextAttemptAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );

    final report = await engine.syncPending();

    expect(report.processed, 0);
    expect(report.failed, 0);
    expect(remote.applied, isEmpty);

    final pending = await queue.listPending();
    expect(pending, hasLength(1));
    expect(pending.first.id, 'op-future');
  });

  test('sync engine can force retry immediately when requested', () async {
    final queue = InMemoryOutboxQueue();
    final remote = _FakeRemoteAdapter();
    final engine = SyncEngine(outboxQueue: queue, remoteAdapter: remote);

    await queue.enqueue(
      OutboxOperation(
        id: 'op-future',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'title': 'A'},
        createdAt: DateTime(2026, 1, 1),
        nextAttemptAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );

    final report = await engine.syncPending(ignoreRetrySchedule: true);

    expect(report.processed, 1);
    expect(report.failed, 0);
    expect(remote.applied, ['op-future']);
    expect(await queue.listPending(), isEmpty);
  });

  test('sync engine drops permission-denied operations from retry queue',
      () async {
    final queue = InMemoryOutboxQueue();
    final remote =
        _FakeRemoteAdapter(permissionDeniedOperationIds: const {'op-denied'});
    final engine = SyncEngine(outboxQueue: queue, remoteAdapter: remote);

    await queue.enqueue(
      OutboxOperation(
        id: 'op-denied',
        type: OutboxOperationType.update,
        entity: 'workItem',
        entityId: 'w-1',
        payload: const {'title': 'A'},
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    final report = await engine.syncPending(ignoreRetrySchedule: true);

    expect(report.processed, 0);
    expect(report.failed, 0);
    expect(report.permissionDenied, 1);
    expect(report.permissionDeniedOperationIds, ['op-denied']);
    expect(await queue.listPending(), isEmpty);
  });
}
