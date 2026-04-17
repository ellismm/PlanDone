import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/domain/policies/hierarchy_context_policy.dart';

void main() {
  WorkItem buildItem({
    required String id,
    required String title,
    required WorkItemType type,
    String? parentId,
  }) {
    return WorkItem(
      itemId: id,
      boardId: 'board-1',
      title: title,
      type: type,
      parentId: parentId,
      columnId: 'c-todo',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
  }

  test('expands a matched item to include ancestors and descendants', () {
    final root = buildItem(
      id: 'goal-1',
      title: 'Goal',
      type: WorkItemType.goal,
    );
    final task = buildItem(
      id: 'task-1',
      title: 'Task',
      type: WorkItemType.task,
      parentId: root.itemId,
    );
    final action = buildItem(
      id: 'action-1',
      title: 'Action',
      type: WorkItemType.action,
      parentId: task.itemId,
    );
    final unrelated = buildItem(
      id: 'goal-2',
      title: 'Unrelated',
      type: WorkItemType.goal,
    );

    final expanded = HierarchyContextPolicy.expandMatchedItems(
      allItems: [root, task, action, unrelated],
      matchedItems: [task],
    );

    expect(
        expanded.map((item) => item.itemId), ['goal-1', 'task-1', 'action-1']);
  });

  test('matched root branch does not pull in unrelated branches', () {
    final root = buildItem(
      id: 'goal-1',
      title: 'Goal',
      type: WorkItemType.goal,
    );
    final child = buildItem(
      id: 'task-1',
      title: 'Task',
      type: WorkItemType.task,
      parentId: root.itemId,
    );
    final otherRoot = buildItem(
      id: 'goal-2',
      title: 'Other goal',
      type: WorkItemType.goal,
    );
    final otherChild = buildItem(
      id: 'task-2',
      title: 'Other task',
      type: WorkItemType.task,
      parentId: otherRoot.itemId,
    );

    final expanded = HierarchyContextPolicy.expandMatchedItems(
      allItems: [root, child, otherRoot, otherChild],
      matchedItems: [root],
    );

    expect(expanded.map((item) => item.itemId), ['goal-1', 'task-1']);
  });

  test('handles legacy hierarchy cycles without looping forever', () {
    final itemA = buildItem(
      id: 'task-a',
      title: 'Task A',
      type: WorkItemType.task,
      parentId: 'task-b',
    );
    final itemB = buildItem(
      id: 'task-b',
      title: 'Task B',
      type: WorkItemType.task,
      parentId: 'task-a',
    );

    final expanded = HierarchyContextPolicy.expandMatchedItems(
      allItems: [itemA, itemB],
      matchedItems: [itemA],
    );

    expect(expanded.map((item) => item.itemId), ['task-a', 'task-b']);
  });

  test('findUnreachableItemIds returns empty for a valid rooted hierarchy', () {
    final goal = buildItem(
      id: 'goal-1',
      title: 'Goal',
      type: WorkItemType.goal,
    );
    final project = buildItem(
      id: 'project-1',
      title: 'Project',
      type: WorkItemType.project,
      parentId: goal.itemId,
    );
    final task = buildItem(
      id: 'task-1',
      title: 'Task',
      type: WorkItemType.task,
      parentId: project.itemId,
    );

    final unreachable = HierarchyContextPolicy.findUnreachableItemIds(
      items: [goal, project, task],
    );

    expect(unreachable, isEmpty);
  });

  test('findUnreachableItemIds identifies items trapped in a cycle', () {
    final itemA = buildItem(
      id: 'task-a',
      title: 'Task A',
      type: WorkItemType.task,
      parentId: 'task-b',
    );
    final itemB = buildItem(
      id: 'task-b',
      title: 'Task B',
      type: WorkItemType.task,
      parentId: 'task-a',
    );
    final rooted = buildItem(
      id: 'goal-1',
      title: 'Goal',
      type: WorkItemType.goal,
    );

    final unreachable = HierarchyContextPolicy.findUnreachableItemIds(
      items: [rooted, itemA, itemB],
    );

    expect(unreachable, {'task-a', 'task-b'});
  });
}
