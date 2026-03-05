import '../models/board_validation_settings.dart';
import '../models/work_item.dart';
import '../models/work_item_type.dart';

class BoardValidationPolicy {
  static String? validateNewItem({
    required BoardValidationSettings settings,
    required WorkItemType type,
    required String title,
    required String? parentId,
    DateTime? startAt,
    DateTime? targetEndAt,
    DateTime? dueAt,
    int? estimatedEffortMinutes,
    required List<WorkItem> existingItems,
  }) {
    if (title.trim().isEmpty) {
      return 'Title is required.';
    }

    final requireParent = _requiresParent(settings: settings, type: type);
    if (requireParent && (parentId == null || parentId.trim().isEmpty)) {
      return 'A parent is required for ${type.name} items in this board.';
    }

    final metadataMessage = _validateRequiredMetadata(
      settings: settings,
      startAt: startAt,
      targetEndAt: targetEndAt,
      dueAt: dueAt,
      estimatedEffortMinutes: estimatedEffortMinutes,
    );
    if (metadataMessage != null) {
      return metadataMessage;
    }

    if (!settings.enforceParentTypeOrder || parentId == null) {
      return null;
    }

    final parent = existingItems
        .where((item) => item.itemId == parentId)
        .cast<WorkItem?>()
        .firstWhere(
          (_) => true,
          orElse: () => null,
        );
    if (parent == null) {
      return 'Parent item was not found.';
    }

    if (_typeRank(parent.type) >= _typeRank(type)) {
      return 'Parent type must be higher-level than child type.';
    }

    return null;
  }

  static String? validateItemUpdate({
    required BoardValidationSettings settings,
    required WorkItem existing,
    required String? nextTitle,
    required String? nextParentId,
    required DateTime? nextStartAt,
    required DateTime? nextTargetEndAt,
    required DateTime? nextDueAt,
    required int? nextEstimatedEffortMinutes,
    required List<WorkItem> allItems,
  }) {
    final title = nextTitle ?? existing.title;
    if (title.trim().isEmpty) {
      return 'Title is required.';
    }

    final requireParent =
        _requiresParent(settings: settings, type: existing.type);
    if (requireParent &&
        (nextParentId == null || nextParentId.trim().isEmpty)) {
      return 'A parent is required for ${existing.type.name} items in this board.';
    }

    final metadataMessage = _validateRequiredMetadata(
      settings: settings,
      startAt: nextStartAt,
      targetEndAt: nextTargetEndAt,
      dueAt: nextDueAt,
      estimatedEffortMinutes: nextEstimatedEffortMinutes,
    );
    if (metadataMessage != null) {
      return metadataMessage;
    }

    if (!settings.enforceParentTypeOrder || nextParentId == null) {
      return _validateNoHierarchyCycle(
        itemId: existing.itemId,
        nextParentId: nextParentId,
        allItems: allItems,
      );
    }

    final parent = allItems
        .where((item) => item.itemId == nextParentId)
        .cast<WorkItem?>()
        .firstWhere(
          (_) => true,
          orElse: () => null,
        );
    if (parent == null) {
      return 'Parent item was not found.';
    }

    if (_typeRank(parent.type) >= _typeRank(existing.type)) {
      return 'Parent type must be higher-level than child type.';
    }

    return _validateNoHierarchyCycle(
      itemId: existing.itemId,
      nextParentId: nextParentId,
      allItems: allItems,
    );
  }

  static String? _validateNoHierarchyCycle({
    required String itemId,
    required String? nextParentId,
    required List<WorkItem> allItems,
  }) {
    if (nextParentId == null) return null;
    if (nextParentId == itemId) {
      return 'Item cannot be its own parent.';
    }

    final byId = {for (final item in allItems) item.itemId: item};
    String? cursorId = nextParentId;
    while (cursorId != null) {
      if (cursorId == itemId) {
        return 'Re-parenting would create a hierarchy cycle.';
      }
      cursorId = byId[cursorId]?.parentId;
    }

    return null;
  }

  static bool _requiresParent({
    required BoardValidationSettings settings,
    required WorkItemType type,
  }) {
    return switch (type) {
      WorkItemType.goal => false,
      WorkItemType.project => settings.requireParentForProjects,
      WorkItemType.task => settings.requireParentForTasks,
      WorkItemType.action => settings.requireParentForActions,
    };
  }

  static int _typeRank(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 0,
      WorkItemType.project => 1,
      WorkItemType.task => 2,
      WorkItemType.action => 3,
    };
  }

  static String? _validateRequiredMetadata({
    required BoardValidationSettings settings,
    required DateTime? startAt,
    required DateTime? targetEndAt,
    required DateTime? dueAt,
    required int? estimatedEffortMinutes,
  }) {
    if (settings.requireStartDate && startAt == null) {
      return 'Start date is required by board settings.';
    }
    if (settings.requireTargetEndDate && targetEndAt == null) {
      return 'Target end date is required by board settings.';
    }
    if (settings.requireDueDate && dueAt == null) {
      return 'Due date is required by board settings.';
    }
    if (settings.requireEstimatedEffort &&
        (estimatedEffortMinutes == null || estimatedEffortMinutes <= 0)) {
      return 'Estimated effort is required by board settings.';
    }
    return null;
  }
}
