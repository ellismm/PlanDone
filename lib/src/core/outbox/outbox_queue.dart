import 'outbox_operation.dart';

abstract class OutboxQueue {
  Future<void> enqueue(OutboxOperation operation);
  Future<List<OutboxOperation>> listPending();
  Future<void> update(OutboxOperation operation);
  Future<void> markProcessed(String operationId);
}
