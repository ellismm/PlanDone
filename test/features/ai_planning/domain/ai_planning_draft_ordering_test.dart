import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_draft.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_draft_ordering.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  AiPlanningDraft draft(List<AiPlanningDraftItem> items) => AiPlanningDraft(
        prompt: 'Create a safe hierarchy with multiple ordered branches.',
        summary: 'Ordering test.',
        items: items,
        providerName: 'test',
        createdAt: DateTime.utc(2026, 8, 29),
      );

  test('moving a root moves its complete branch before the prior root', () {
    final original = draft(const [
      AiPlanningDraftItem(
        draftId: 'goal-a',
        title: 'Goal A',
        type: WorkItemType.goal,
      ),
      AiPlanningDraftItem(
        draftId: 'task-a',
        title: 'Task A',
        type: WorkItemType.task,
        parentDraftId: 'goal-a',
      ),
      AiPlanningDraftItem(
        draftId: 'goal-b',
        title: 'Goal B',
        type: WorkItemType.goal,
      ),
      AiPlanningDraftItem(
        draftId: 'task-b',
        title: 'Task B',
        type: WorkItemType.task,
        parentDraftId: 'goal-b',
      ),
    ]);

    final reordered = AiPlanningDraftOrdering.moveUp(original, 'goal-b');

    expect(
      reordered.items.map((item) => item.draftId),
      ['goal-b', 'task-b', 'goal-a', 'task-a'],
    );
    expect(AiPlanningDraftOrdering.canMoveUp(reordered, 'goal-b'), isFalse);
    expect(AiPlanningDraftOrdering.canMoveDown(reordered, 'goal-b'), isTrue);
  });

  test('moving a child only changes order among siblings', () {
    final original = draft(const [
      AiPlanningDraftItem(
        draftId: 'goal',
        title: 'Goal',
        type: WorkItemType.goal,
      ),
      AiPlanningDraftItem(
        draftId: 'task-a',
        title: 'Task A',
        type: WorkItemType.task,
        parentDraftId: 'goal',
      ),
      AiPlanningDraftItem(
        draftId: 'action-a',
        title: 'Action A',
        type: WorkItemType.action,
        parentDraftId: 'task-a',
      ),
      AiPlanningDraftItem(
        draftId: 'task-b',
        title: 'Task B',
        type: WorkItemType.task,
        parentDraftId: 'goal',
      ),
    ]);

    final reordered = AiPlanningDraftOrdering.moveUp(original, 'task-b');

    expect(
      reordered.items.map((item) => item.draftId),
      ['goal', 'task-b', 'task-a', 'action-a'],
    );
    expect(
      reordered.items
          .firstWhere((item) => item.draftId == 'action-a')
          .parentDraftId,
      'task-a',
    );
  });

  test('boundary and unknown moves leave the same draft unchanged', () {
    final original = draft(const [
      AiPlanningDraftItem(
        draftId: 'goal',
        title: 'Goal',
        type: WorkItemType.goal,
      ),
    ]);

    expect(
        identical(AiPlanningDraftOrdering.moveUp(original, 'goal'), original),
        isTrue);
    expect(
      identical(
          AiPlanningDraftOrdering.moveDown(original, 'missing'), original),
      isTrue,
    );
  });
}
