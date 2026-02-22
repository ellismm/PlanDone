import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/outbox/drift_outbox_queue.dart';
import 'package:plandone/src/core/outbox/outbox_operation.dart';
import 'package:plandone/src/features/board/data/local/drift/board_database.dart';

void main() {
  test('drift outbox queue persists enqueue/list/markProcessed', () async {
    final db = BoardDatabase.forTesting(NativeDatabase.memory());
    final queue = DriftOutboxQueue(db);

    final op = OutboxOperation(
      id: 'op-1',
      type: OutboxOperationType.move,
      entity: 'workItem',
      entityId: 'a-1',
      payload: const {'toColumnId': 'c-done'},
      createdAt: DateTime(2026, 1, 1),
    );

    await queue.enqueue(op);
    final pending = await queue.listPending();

    expect(pending, hasLength(1));
    expect(pending.first.id, 'op-1');
    expect(pending.first.payload['toColumnId'], 'c-done');

    await queue.markProcessed('op-1');
    final after = await queue.listPending();
    expect(after, isEmpty);

    await db.close();
  });

  test('drift outbox queue persists retry metadata updates', () async {
    final db = BoardDatabase.forTesting(NativeDatabase.memory());
    final queue = DriftOutboxQueue(db);

    final op = OutboxOperation(
      id: 'op-retry',
      type: OutboxOperationType.update,
      entity: 'workItem',
      entityId: 'a-1',
      payload: const {'title': 'Retry me'},
      createdAt: DateTime(2026, 1, 1),
    );

    await queue.enqueue(op);
    await queue.update(
      op.copyWith(
        attemptCount: 3,
        lastError: '503 service unavailable',
        nextAttemptAt: DateTime(2026, 1, 1, 0, 5),
      ),
    );

    final pending = await queue.listPending();
    expect(pending, hasLength(1));
    expect(pending.first.id, 'op-retry');
    expect(pending.first.attemptCount, 3);
    expect(pending.first.lastError, '503 service unavailable');
    expect(pending.first.nextAttemptAt, DateTime(2026, 1, 1, 0, 5));

    await db.close();
  });
}
