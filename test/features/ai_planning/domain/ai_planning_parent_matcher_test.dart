import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_draft.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_parent_matcher.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  const items = <AiPlanningExistingItem>[
    AiPlanningExistingItem(
      itemId: 'home',
      title: 'Home',
      type: WorkItemType.goal,
    ),
    AiPlanningExistingItem(
      itemId: 'home-maintenance',
      title: 'Home Maintenance Goal',
      type: WorkItemType.goal,
    ),
    AiPlanningExistingItem(
      itemId: 'garage',
      title: 'Garage organization',
      type: WorkItemType.project,
      parentItemId: 'home-maintenance',
    ),
    AiPlanningExistingItem(
      itemId: 'action',
      title: 'Epoxy garage floor',
      type: WorkItemType.action,
      parentItemId: 'garage',
    ),
  ];

  test('matches a naturally named existing goal and prefers specificity', () {
    final match = AiPlanningParentMatcher.bestParentId(
      prompt:
          'Within the house maintenance goal, create a plan to epoxy the garage floor.',
      items: items,
    );

    expect(match, 'home-maintenance');
  });

  test('does not require the type suffix from an existing title', () {
    final match = AiPlanningParentMatcher.bestParentId(
      prompt: 'Add seasonal work under home maintenance.',
      items: items,
    );

    expect(match, 'home-maintenance');
  });

  test('does not guess an unrelated parent from weak overlap', () {
    final match = AiPlanningParentMatcher.bestParentId(
      prompt: 'Create a professional development plan for this year.',
      items: items,
    );

    expect(match, isNull);
  });

  test('never selects an action as a generated-plan parent', () {
    final match = AiPlanningParentMatcher.bestParentId(
      prompt: 'Continue the epoxy garage floor work.',
      items: items,
    );

    expect(match, isNull);
  });
}
