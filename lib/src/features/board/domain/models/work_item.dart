import 'work_item_type.dart';
import 'work_item_recurrence.dart';

class WorkItem {
  const WorkItem({
    required this.itemId,
    required this.boardId,
    required this.title,
    required this.type,
    required this.columnId,
    required this.createdAt,
    required this.updatedAt,
    this.sortOrder = 0,
    this.parentId,
    this.description,
    this.assigneeIds = const [],
    this.startAt,
    this.targetEndAt,
    this.dueAt,
    this.completedAt,
    this.estimatedEffortMinutes,
    this.actualEffortMinutes,
    this.tags = const [],
    this.archived = false,
    this.isInbox = false,
    this.recurrence,
  });

  final String itemId;
  final String boardId;
  final String title;
  final WorkItemType type;
  final double sortOrder;
  final String? parentId;
  final String columnId;
  final String? description;
  final List<String> assigneeIds;
  final DateTime? startAt;
  final DateTime? targetEndAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final int? estimatedEffortMinutes;
  final int? actualEffortMinutes;
  final List<String> tags;
  final bool archived;
  final bool isInbox;
  final WorkItemRecurrence? recurrence;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkItem copyWith({
    String? title,
    double? sortOrder,
    String? parentId,
    String? columnId,
    String? description,
    DateTime? startAt,
    DateTime? targetEndAt,
    DateTime? dueAt,
    int? estimatedEffortMinutes,
    int? actualEffortMinutes,
    List<String>? tags,
    bool? archived,
    bool? isInbox,
    WorkItemRecurrence? recurrence,
    bool clearParent = false,
    bool clearDescription = false,
    bool clearStartAt = false,
    bool clearTargetEndAt = false,
    bool clearDueAt = false,
    bool clearEstimatedEffort = false,
    bool clearActualEffort = false,
    bool clearRecurrence = false,
    DateTime? completedAt,
    DateTime? updatedAt,
  }) {
    return WorkItem(
      itemId: itemId,
      boardId: boardId,
      title: title ?? this.title,
      type: type,
      sortOrder: sortOrder ?? this.sortOrder,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      columnId: columnId ?? this.columnId,
      description: clearDescription ? null : (description ?? this.description),
      assigneeIds: assigneeIds,
      startAt: clearStartAt ? null : (startAt ?? this.startAt),
      targetEndAt: clearTargetEndAt ? null : (targetEndAt ?? this.targetEndAt),
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      completedAt: completedAt,
      estimatedEffortMinutes: clearEstimatedEffort
          ? null
          : (estimatedEffortMinutes ?? this.estimatedEffortMinutes),
      actualEffortMinutes: clearActualEffort
          ? null
          : (actualEffortMinutes ?? this.actualEffortMinutes),
      tags: tags ?? this.tags,
      archived: archived ?? this.archived,
      isInbox: isInbox ?? this.isInbox,
      recurrence: clearRecurrence ? null : (recurrence ?? this.recurrence),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
