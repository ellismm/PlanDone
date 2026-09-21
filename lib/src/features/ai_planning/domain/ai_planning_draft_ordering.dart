import 'ai_planning_draft.dart';

class AiPlanningDraftOrdering {
  const AiPlanningDraftOrdering._();

  static bool canMoveUp(AiPlanningDraft draft, String draftId) =>
      _siblingIndex(draft, draftId) > 0;

  static bool canMoveDown(AiPlanningDraft draft, String draftId) {
    final item = _item(draft, draftId);
    if (item == null) return false;
    final siblings = draft.items
        .where((candidate) => candidate.parentDraftId == item.parentDraftId)
        .toList(growable: false);
    final index =
        siblings.indexWhere((candidate) => candidate.draftId == draftId);
    return index >= 0 && index < siblings.length - 1;
  }

  static AiPlanningDraft moveUp(AiPlanningDraft draft, String draftId) =>
      _move(draft, draftId, -1);

  static AiPlanningDraft moveDown(AiPlanningDraft draft, String draftId) =>
      _move(draft, draftId, 1);

  static AiPlanningDraft _move(
    AiPlanningDraft draft,
    String draftId,
    int siblingOffset,
  ) {
    final item = _item(draft, draftId);
    if (item == null) return draft;

    final childrenByParent = <String?, List<AiPlanningDraftItem>>{};
    for (final candidate in draft.items) {
      childrenByParent
          .putIfAbsent(candidate.parentDraftId, () => <AiPlanningDraftItem>[])
          .add(candidate);
    }

    final siblings = childrenByParent[item.parentDraftId]!;
    final oldIndex = siblings.indexWhere(
      (candidate) => candidate.draftId == draftId,
    );
    final newIndex = oldIndex + siblingOffset;
    if (oldIndex < 0 || newIndex < 0 || newIndex >= siblings.length) {
      return draft;
    }

    siblings.insert(newIndex, siblings.removeAt(oldIndex));

    final ordered = <AiPlanningDraftItem>[];
    void addBranch(AiPlanningDraftItem branch) {
      ordered.add(branch);
      for (final child in childrenByParent[branch.draftId] ?? const []) {
        addBranch(child);
      }
    }

    for (final root in childrenByParent[null] ?? const []) {
      addBranch(root);
    }

    return draft.copyWith(items: List.unmodifiable(ordered));
  }

  static int _siblingIndex(AiPlanningDraft draft, String draftId) {
    final item = _item(draft, draftId);
    if (item == null) return -1;
    return draft.items
        .where((candidate) => candidate.parentDraftId == item.parentDraftId)
        .toList(growable: false)
        .indexWhere((candidate) => candidate.draftId == draftId);
  }

  static AiPlanningDraftItem? _item(AiPlanningDraft draft, String draftId) {
    for (final item in draft.items) {
      if (item.draftId == draftId) return item;
    }
    return null;
  }
}
