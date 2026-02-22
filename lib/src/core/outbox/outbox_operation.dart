enum OutboxOperationType {
  create,
  update,
  delete,
  move,
  reorder,
}

class OutboxOperation {
  const OutboxOperation({
    required this.id,
    required this.type,
    required this.entity,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastError,
    this.nextAttemptAt,
  });

  final String id;
  final OutboxOperationType type;
  final String entity;
  final String entityId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final int attemptCount;
  final String? lastError;
  final DateTime? nextAttemptAt;

  OutboxOperation copyWith({
    int? attemptCount,
    String? lastError,
    bool clearLastError = false,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
  }) {
    return OutboxOperation(
      id: id,
      type: type,
      entity: entity,
      entityId: entityId,
      payload: payload,
      createdAt: createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      nextAttemptAt: clearNextAttemptAt ? null : (nextAttemptAt ?? this.nextAttemptAt),
    );
  }
}
