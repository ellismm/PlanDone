import '../models/autofill_settings.dart';
import '../models/board_snapshot.dart';
import '../models/column.dart';
import '../models/work_item.dart';
import '../models/work_item_type.dart';
import 'autofill_suggestion_policy.dart';
import 'workflow_semantics_policy.dart';

class CreateItemDefaultsDraft {
  const CreateItemDefaultsDraft({
    required this.type,
    required this.columnId,
    this.parentId,
    this.tags = const <String>[],
    this.estimatedEffortMinutes,
  });

  final WorkItemType type;
  final String columnId;
  final String? parentId;
  final List<String> tags;
  final int? estimatedEffortMinutes;
}

class CreateItemDefaultsPolicy {
  static CreateItemDefaultsDraft resolve({
    required BoardSnapshot snapshot,
    required AutofillSettings settings,
    WorkItem? focusedItem,
    WorkItemType? selectedType,
  }) {
    final effectiveType =
        selectedType ?? _defaultTypeForFocusedItem(focusedItem);
    final autofill = AutofillSuggestionPolicy.forCreateItem(
      snapshot: snapshot,
      settings: settings,
      selectedType: effectiveType,
    );

    return CreateItemDefaultsDraft(
      type: effectiveType,
      columnId: _defaultPlanningColumnId(snapshot.columns),
      parentId: _defaultParentId(
        focusedItem: focusedItem,
        selectedType: effectiveType,
        allItems: snapshot.items,
      ),
      tags: autofill.tags,
      estimatedEffortMinutes: autofill.estimatedEffortMinutes,
    );
  }

  static WorkItemType _defaultTypeForFocusedItem(WorkItem? focusedItem) {
    return switch (focusedItem?.type) {
      null => WorkItemType.goal,
      WorkItemType.goal => WorkItemType.project,
      WorkItemType.project => WorkItemType.task,
      WorkItemType.task => WorkItemType.action,
      WorkItemType.action => WorkItemType.action,
    };
  }

  static String _defaultPlanningColumnId(List<BoardColumn> columns) {
    final normalized = WorkflowSemanticsPolicy.normalizeColumns(columns)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (normalized.isEmpty) {
      throw StateError('Cannot resolve create defaults without board columns.');
    }

    BoardColumn? firstEnabledByKind(BoardColumnKind kind) {
      return normalized
          .where((column) => column.isEnabled && column.kind == kind)
          .cast<BoardColumn?>()
          .firstWhere((_) => true, orElse: () => null);
    }

    final preferred = [
      firstEnabledByKind(BoardColumnKind.planning),
      firstEnabledByKind(BoardColumnKind.backlog),
      firstEnabledByKind(BoardColumnKind.ready),
    ].whereType<BoardColumn>().firstWhere(
          (_) => true,
          orElse: () => const BoardColumn(
            columnId: '',
            boardId: '',
            name: '',
            orderIndex: 0,
          ),
        );

    if (preferred.columnId.isNotEmpty) {
      return preferred.columnId;
    }

    final activeFallback = normalized
        .where(
          (column) =>
              column.isEnabled &&
              !column.isDoneState &&
              !column.isCancelledState,
        )
        .cast<BoardColumn?>()
        .firstWhere((_) => true, orElse: () => null);
    return activeFallback?.columnId ?? normalized.first.columnId;
  }

  static String? _defaultParentId({
    required WorkItem? focusedItem,
    required WorkItemType selectedType,
    required List<WorkItem> allItems,
  }) {
    if (selectedType == WorkItemType.goal || focusedItem == null) {
      return null;
    }

    if (focusedItem.type == WorkItemType.action &&
        selectedType == WorkItemType.action) {
      return _containsItem(allItems, focusedItem.parentId)
          ? focusedItem.parentId
          : null;
    }

    if (_typeRank(focusedItem.type) < _typeRank(selectedType)) {
      return _containsItem(allItems, focusedItem.itemId)
          ? focusedItem.itemId
          : null;
    }

    return null;
  }

  static bool _containsItem(List<WorkItem> items, String? itemId) {
    if (itemId == null) return false;
    return items.any((item) => item.itemId == itemId);
  }

  static int _typeRank(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 0,
      WorkItemType.project => 1,
      WorkItemType.task => 2,
      WorkItemType.action => 3,
    };
  }
}
