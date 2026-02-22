import '../outbox/outbox_operation.dart';
import 'sync_remote_adapter.dart';

class InMemorySyncRemoteAdapter implements SyncRemoteAdapter {
  final Set<String> _appliedOperationIds = <String>{};

  @override
  Future<void> applyOperation(OutboxOperation operation) async {
    // Idempotent behavior for local development/testing.
    _appliedOperationIds.add(operation.id);
  }

  bool hasApplied(String operationId) => _appliedOperationIds.contains(operationId);
}
