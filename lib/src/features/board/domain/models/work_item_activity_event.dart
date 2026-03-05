enum WorkItemActivityType {
  created,
  updated,
  moved,
  reparented,
  archived,
  unarchived,
  completed,
  reopened,
}

class WorkItemActivityEvent {
  const WorkItemActivityEvent({
    required this.eventId,
    required this.boardId,
    required this.itemId,
    required this.type,
    required this.actorUserId,
    required this.createdAt,
    this.payload = const {},
  });

  final String eventId;
  final String boardId;
  final String itemId;
  final WorkItemActivityType type;
  final String actorUserId;
  final DateTime createdAt;
  final Map<String, Object?> payload;

  WorkItemActivityEvent copyWith({
    String? eventId,
    String? boardId,
    String? itemId,
    WorkItemActivityType? type,
    String? actorUserId,
    DateTime? createdAt,
    Map<String, Object?>? payload,
  }) {
    return WorkItemActivityEvent(
      eventId: eventId ?? this.eventId,
      boardId: boardId ?? this.boardId,
      itemId: itemId ?? this.itemId,
      type: type ?? this.type,
      actorUserId: actorUserId ?? this.actorUserId,
      createdAt: createdAt ?? this.createdAt,
      payload: payload ?? this.payload,
    );
  }
}
