import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/in_memory_outbox_queue.dart';
import 'package:plandone/src/core/outbox/outbox_operation.dart';

void main() {
  test('enqueue + listPending + markProcessed work as expected', () async {
    final queue = InMemoryOutboxQueue();
    final op1 = OutboxOperation(
      id: 'op-1',
      type: OutboxOperationType.create,
      entity: 'workItem',
      entityId: 'w-1',
      payload: const {'title': 'Task A'},
      createdAt: DateTime(2026, 1, 1),
    );
    final op2 = OutboxOperation(
      id: 'op-2',
      type: OutboxOperationType.move,
      entity: 'workItem',
      entityId: 'w-1',
      payload: const {'toColumnId': 'c-done'},
      createdAt: DateTime(2026, 1, 1, 0, 0, 1),
    );

    await queue.enqueue(op1);
    await queue.enqueue(op2);

    final pendingBefore = await queue.listPending();
    expect(pendingBefore.map((op) => op.id), ['op-1', 'op-2']);

    await queue.markProcessed('op-1');

    final pendingAfter = await queue.listPending();
    expect(pendingAfter.map((op) => op.id), ['op-2']);
  });

  test('update replaces operation metadata by id', () async {
    final queue = InMemoryOutboxQueue();
    final op = OutboxOperation(
      id: 'op-1',
      type: OutboxOperationType.update,
      entity: 'workItem',
      entityId: 'w-1',
      payload: const {'title': 'Task A'},
      createdAt: DateTime(2026, 1, 1),
    );

    await queue.enqueue(op);
    await queue.update(
      op.copyWith(
        attemptCount: 2,
        lastError: 'network timeout',
        nextAttemptAt: DateTime(2026, 1, 1, 0, 2),
      ),
    );

    final pending = await queue.listPending();
    expect(pending, hasLength(1));
    expect(pending.first.attemptCount, 2);
    expect(pending.first.lastError, 'network timeout');
    expect(pending.first.nextAttemptAt, DateTime(2026, 1, 1, 0, 2));
  });
}
