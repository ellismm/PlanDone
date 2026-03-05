import '../outbox/outbox_operation.dart';

class SyncRemoteException implements Exception {
  SyncRemoteException(this.message);

  final String message;

  @override
  String toString() => 'SyncRemoteException: $message';
}

class SyncRemotePermissionDeniedException extends SyncRemoteException {
  SyncRemotePermissionDeniedException(super.message);

  @override
  String toString() => 'SyncRemotePermissionDeniedException: $message';
}

abstract class SyncRemoteAdapter {
  Future<void> applyOperation(OutboxOperation operation);
}
