import '../outbox/outbox_operation.dart';

abstract class SyncRemoteAdapter {
  Future<void> applyOperation(OutboxOperation operation);
}
