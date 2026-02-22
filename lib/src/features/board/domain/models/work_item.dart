import 'work_item_type.dart';

class WorkItem {
  const WorkItem({
    required this.itemId,
    required this.boardId,
    required this.title,
    required this.type,
    required this.columnId,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.description,
    this.assigneeIds = const [],
    this.startAt,
    this.dueAt,
    this.completedAt,
    this.tags = const [],
    this.archived = false,
  });

  final String itemId;
  final String boardId;
  final String title;
  final WorkItemType type;
  final String? parentId;
  final String columnId;
  final String? description;
  final List<String> assigneeIds;
  final DateTime? startAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final List<String> tags;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkItem copyWith({
    String? title,
    String? parentId,
    String? columnId,
    String? description,
    DateTime? dueAt,
    List<String>? tags,
    bool? archived,
    bool clearParent = false,
    bool clearDescription = false,
    bool clearDueAt = false,
    DateTime? completedAt,
    DateTime? updatedAt,
  }) {
    return WorkItem(
      itemId: itemId,
      boardId: boardId,
      title: title ?? this.title,
      type: type,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      columnId: columnId ?? this.columnId,
      description: clearDescription ? null : (description ?? this.description),
      assigneeIds: assigneeIds,
      startAt: startAt,
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      completedAt: completedAt,
      tags: tags ?? this.tags,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
