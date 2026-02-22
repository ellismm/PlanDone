import 'outbox_operation.dart';
import 'outbox_queue.dart';

class InMemoryOutboxQueue implements OutboxQueue {
  final List<OutboxOperation> _pending = [];

  @override
  Future<void> enqueue(OutboxOperation operation) async {
    _pending.add(operation);
  }

  @override
  Future<List<OutboxOperation>> listPending() async => List.unmodifiable(_pending);

  @override
  Future<void> update(OutboxOperation operation) async {
    final index = _pending.indexWhere((op) => op.id == operation.id);
    if (index < 0) return;
    _pending[index] = operation;
  }

  @override
  Future<void> markProcessed(String operationId) async {
    _pending.removeWhere((op) => op.id == operationId);
  }
}
