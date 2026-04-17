import 'package:flutter_test/flutter_test.dart';

import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/domain/policies/board_validation_policy.dart';

void main() {
  WorkItem item({
    required String id,
    required WorkItemType type,
    String? parentId,
    bool archived = false,
    bool isInbox = false,
  }) {
    return WorkItem(
      itemId: id,
      boardId: 'board-1',
      title: id,
      type: type,
      parentId: parentId,
      archived: archived,
      isInbox: isInbox,
      columnId: 'c-todo',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  test('allowedParentCandidates only returns higher-level item types', () {
    final goal = item(id: 'g-1', type: WorkItemType.goal);
    final project = item(
      id: 'p-1',
      type: WorkItemType.project,
      parentId: goal.itemId,
    );
    final task = item(
      id: 't-1',
      type: WorkItemType.task,
      parentId: project.itemId,
    );
    final action = item(
      id: 'a-1',
      type: WorkItemType.action,
      parentId: task.itemId,
    );
    final inboxTask = item(
      id: 't-inbox',
      type: WorkItemType.task,
      isInbox: true,
    );
    final archivedGoal = item(
      id: 'g-archived',
      type: WorkItemType.goal,
      archived: true,
    );
    final allItems = [goal, project, task, action, inboxTask, archivedGoal];

    expect(
      BoardValidationPolicy.allowedParentCandidates(
        childType: WorkItemType.goal,
        allItems: allItems,
      ),
      isEmpty,
    );
    expect(
      BoardValidationPolicy.allowedParentCandidates(
        childType: WorkItemType.project,
        allItems: allItems,
      ).map((entry) => entry.itemId),
      ['g-1'],
    );
    expect(
      BoardValidationPolicy.allowedParentCandidates(
        childType: WorkItemType.task,
        allItems: allItems,
      ).map((entry) => entry.itemId),
      ['g-1', 'p-1'],
    );
    expect(
      BoardValidationPolicy.allowedParentCandidates(
        childType: WorkItemType.action,
        allItems: allItems,
      ).map((entry) => entry.itemId),
      ['g-1', 'p-1', 't-1'],
    );
  });

  test('allowedParentCandidates excludes the item itself and descendants', () {
    final goal = item(id: 'g-1', type: WorkItemType.goal);
    final project = item(
      id: 'p-1',
      type: WorkItemType.project,
      parentId: goal.itemId,
    );
    final task = item(
      id: 't-1',
      type: WorkItemType.task,
      parentId: project.itemId,
    );
    final action = item(
      id: 'a-1',
      type: WorkItemType.action,
      parentId: task.itemId,
    );

    final candidates = BoardValidationPolicy.allowedParentCandidates(
      childType: WorkItemType.project,
      allItems: [goal, project, task, action],
      itemId: project.itemId,
    );

    expect(candidates.map((entry) => entry.itemId), ['g-1']);
  });
}
