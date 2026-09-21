import '../../board/domain/models/board_snapshot.dart';
import '../../board/domain/models/column.dart';
import '../../board/domain/models/work_item.dart';
import '../../board/domain/models/work_item_type.dart';
import '../../board/domain/repositories/board_repository.dart';
import '../domain/ai_planning_draft.dart';
import '../domain/ai_planning_draft_parser.dart';

class AiPlanningCommitResult {
  const AiPlanningCommitResult({
    required this.createdItems,
    required this.columnId,
  });

  final List<WorkItem> createdItems;
  final String columnId;
}

class AiPlanningCommitService {
  AiPlanningCommitService({
    required BoardRepository repository,
    AiPlanningDraftParser parser = const AiPlanningDraftParser(),
  })  : _repository = repository,
        _parser = parser;

  final BoardRepository _repository;
  final AiPlanningDraftParser _parser;

  Future<AiPlanningCommitResult> commit({
    required AiPlanningDraft draft,
    required BoardSnapshot snapshot,
  }) async {
    _parser.validateDraft(draft, maxItems: 64);
    final existingParent = _existingParent(draft, snapshot);
    _validateBoardCompatibility(draft, snapshot, existingParent);
    _validateNoExistingTitleDuplicates(draft, snapshot);
    final targetColumn = _targetColumn(snapshot.columns);
    final createdByDraftId = <String, WorkItem>{};
    final created = <WorkItem>[];

    for (final draftItem in _parser.topologicalItems(draft)) {
      try {
        final item = await _repository.createItem(
          boardId: snapshot.board.boardId,
          title: draftItem.title.trim(),
          type: draftItem.type,
          toColumnId: targetColumn.columnId,
          parentId: draftItem.parentDraftId == null
              ? existingParent?.itemId
              : createdByDraftId[draftItem.parentDraftId]!.itemId,
          description: draftItem.description,
          tags: {...draftItem.tags, 'ai-assisted'}.toList(),
          estimatedEffortMinutes: draftItem.estimatedEffortMinutes,
        );
        createdByDraftId[draftItem.draftId] = item;
        created.add(item);
      } catch (error) {
        if (created.isNotEmpty) {
          throw AiPlanningException(
            'The approved plan stopped after creating ${created.length} item(s). Review the board before retrying. Details: $error',
          );
        }
        rethrow;
      }
    }

    return AiPlanningCommitResult(
      createdItems: List.unmodifiable(created),
      columnId: targetColumn.columnId,
    );
  }

  static BoardColumn _targetColumn(List<BoardColumn> columns) {
    final enabled = columns.where((column) => column.isEnabled).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    if (enabled.isEmpty) {
      throw const AiPlanningException(
        'This board has no enabled column for approved items.',
      );
    }
    const preferred = {
      BoardColumnKind.planning,
      BoardColumnKind.backlog,
      BoardColumnKind.ready,
    };
    return enabled.firstWhere(
      (column) => preferred.contains(column.kind),
      orElse: () => enabled.firstWhere(
        (column) =>
            !column.isDoneState &&
            !column.isCancelledState &&
            !column.isBlockedState,
        orElse: () => enabled.first,
      ),
    );
  }

  static void _validateBoardCompatibility(
    AiPlanningDraft draft,
    BoardSnapshot snapshot,
    WorkItem? existingParent,
  ) {
    final settings = snapshot.board.validationSettings;
    if (settings.requireStartDate ||
        settings.requireTargetEndDate ||
        settings.requireDueDate) {
      throw const AiPlanningException(
        'This board requires dates. Phase 9 drafts do not invent dates; relax the requirement or create the items manually.',
      );
    }
    if (settings.requireEstimatedEffort &&
        draft.items.any((item) => item.estimatedEffortMinutes == null)) {
      throw const AiPlanningException(
        'This board requires estimated effort for every item. Add estimates to the draft before approval.',
      );
    }

    bool requiresParent(WorkItemType type) => switch (type) {
          WorkItemType.goal => false,
          WorkItemType.project => settings.requireParentForProjects,
          WorkItemType.task => settings.requireParentForTasks,
          WorkItemType.action => settings.requireParentForActions,
        };
    final missingParent = draft.items
        .where((item) =>
            requiresParent(item.type) &&
            item.parentDraftId == null &&
            existingParent == null)
        .toList();
    if (missingParent.isNotEmpty) {
      throw AiPlanningException(
        'Board rules require a parent for "${missingParent.first.title}".',
      );
    }
  }

  static WorkItem? _existingParent(
    AiPlanningDraft draft,
    BoardSnapshot snapshot,
  ) {
    final parentId = draft.existingParentItemId;
    if (parentId == null) return null;
    final matches = snapshot.items.where((item) => item.itemId == parentId);
    if (matches.isEmpty) {
      throw const AiPlanningException(
        'The selected existing parent is no longer on this board.',
      );
    }
    final parent = matches.first;
    if (parent.archived || parent.isInbox) {
      throw const AiPlanningException(
        'The selected existing parent is not available for new children.',
      );
    }
    if (parent.type == WorkItemType.action) {
      throw const AiPlanningException(
        'Actions cannot contain generated children.',
      );
    }
    for (final root
        in draft.items.where((item) => item.parentDraftId == null)) {
      if (WorkItemType.values.indexOf(parent.type) >=
          WorkItemType.values.indexOf(root.type)) {
        throw AiPlanningException(
          '"${root.title}" must be below the selected ${parent.type.name} "${parent.title}".',
        );
      }
    }
    return parent;
  }

  static void _validateNoExistingTitleDuplicates(
    AiPlanningDraft draft,
    BoardSnapshot snapshot,
  ) {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    final existingTitles = snapshot.items
        .where((item) => !item.archived && !item.isInbox)
        .map((item) => normalize(item.title))
        .toSet();
    final duplicate = draft.items
        .where((item) => existingTitles.contains(normalize(item.title)))
        .cast<AiPlanningDraftItem?>()
        .firstWhere((_) => true, orElse: () => null);
    if (duplicate != null) {
      throw AiPlanningException(
        '"${duplicate.title}" already exists on this board. Remove or rename the duplicate before approval.',
      );
    }
  }
}
