import 'package:flutter_test/flutter_test.dart';

import 'package:plandone/src/features/board/domain/models/autofill_settings.dart';
import 'package:plandone/src/features/board/domain/models/board.dart';
import 'package:plandone/src/features/board/domain/models/board_member.dart';
import 'package:plandone/src/features/board/domain/models/board_snapshot.dart';
import 'package:plandone/src/features/board/domain/models/column.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/domain/policies/create_item_defaults_policy.dart';
import 'package:plandone/src/features/board/domain/policies/workflow_semantics_policy.dart';

void main() {
  BoardSnapshot buildSnapshot({
    List<BoardColumn>? columns,
    List<WorkItem>? items,
  }) {
    return BoardSnapshot(
      board: Board(
        boardId: 'board-1',
        name: 'Board',
        ownerId: 'user-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      members: [
        BoardMember(
          boardId: 'board-1',
          userId: 'user-1',
          role: BoardRole.owner,
          joinedAt: DateTime(2026, 1, 1),
        ),
      ],
      columns:
          columns ?? WorkflowSemanticsPolicy.legacyDefaultColumns('board-1'),
      items: items ?? const [],
    );
  }

  final goal = WorkItem(
    itemId: 'g-1',
    boardId: 'board-1',
    title: 'Goal',
    type: WorkItemType.goal,
    columnId: 'c-todo',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
  final project = WorkItem(
    itemId: 'p-1',
    boardId: 'board-1',
    title: 'Project',
    type: WorkItemType.project,
    parentId: 'g-1',
    columnId: 'c-doing',
    tags: const ['roadmap'],
    estimatedEffortMinutes: 45,
    createdAt: DateTime(2026, 1, 2),
    updatedAt: DateTime(2026, 1, 2),
  );
  final task = WorkItem(
    itemId: 't-1',
    boardId: 'board-1',
    title: 'Task',
    type: WorkItemType.task,
    parentId: 'p-1',
    columnId: 'c-todo',
    createdAt: DateTime(2026, 1, 3),
    updatedAt: DateTime(2026, 1, 3),
  );
  final action = WorkItem(
    itemId: 'a-1',
    boardId: 'board-1',
    title: 'Action',
    type: WorkItemType.action,
    parentId: 't-1',
    columnId: 'c-doing',
    createdAt: DateTime(2026, 1, 4),
    updatedAt: DateTime(2026, 1, 4),
  );

  test('no focused item defaults to root goal in earliest planning-like column',
      () {
    final snapshot = buildSnapshot(items: [goal, project, task, action]);

    final defaults = CreateItemDefaultsPolicy.resolve(
      snapshot: snapshot,
      settings: const AutofillSettings(enabled: false),
    );

    expect(defaults.type, WorkItemType.goal);
    expect(defaults.parentId, isNull);
    expect(defaults.columnId, 'c-todo');
  });

  test('focused goal defaults to project child of goal', () {
    final snapshot = buildSnapshot(items: [goal, project, task, action]);

    final defaults = CreateItemDefaultsPolicy.resolve(
      snapshot: snapshot,
      settings: const AutofillSettings(enabled: false),
      focusedItem: goal,
    );

    expect(defaults.type, WorkItemType.project);
    expect(defaults.parentId, goal.itemId);
    expect(defaults.columnId, 'c-todo');
  });

  test('focused project defaults to task child of project', () {
    final snapshot = buildSnapshot(items: [goal, project, task, action]);

    final defaults = CreateItemDefaultsPolicy.resolve(
      snapshot: snapshot,
      settings: const AutofillSettings(enabled: false),
      focusedItem: project,
    );

    expect(defaults.type, WorkItemType.task);
    expect(defaults.parentId, project.itemId);
  });

  test('focused task defaults to action child of task', () {
    final snapshot = buildSnapshot(items: [goal, project, task, action]);

    final defaults = CreateItemDefaultsPolicy.resolve(
      snapshot: snapshot,
      settings: const AutofillSettings(enabled: false),
      focusedItem: task,
    );

    expect(defaults.type, WorkItemType.action);
    expect(defaults.parentId, task.itemId);
  });

  test('focused action defaults to sibling action using same parent', () {
    final snapshot = buildSnapshot(items: [goal, project, task, action]);

    final defaults = CreateItemDefaultsPolicy.resolve(
      snapshot: snapshot,
      settings: const AutofillSettings(enabled: false),
      focusedItem: action,
    );

    expect(defaults.type, WorkItemType.action);
    expect(defaults.parentId, task.itemId);
  });

  test('context defaults override autofill for type parent and column', () {
    final recentProject = WorkItem(
      itemId: 'p-2',
      boardId: 'board-1',
      title: 'Recent project',
      type: WorkItemType.project,
      parentId: 'g-1',
      columnId: 'c-doing',
      tags: const ['delivery', 'sync'],
      estimatedEffortMinutes: 30,
      createdAt: DateTime(2026, 1, 5),
      updatedAt: DateTime(2026, 1, 5),
    );
    final snapshot = buildSnapshot(
      items: [goal, project, recentProject, task, action],
    );

    final defaults = CreateItemDefaultsPolicy.resolve(
      snapshot: snapshot,
      settings: const AutofillSettings(),
      focusedItem: goal,
    );

    expect(defaults.type, WorkItemType.project);
    expect(defaults.parentId, goal.itemId);
    expect(defaults.columnId, 'c-todo');
    expect(defaults.tags, contains('delivery'));
    expect(defaults.estimatedEffortMinutes, 38);
  });

  test(
      'falls back to first active non-done column when planning-like kinds are absent',
      () {
    final snapshot = buildSnapshot(
      columns: const [
        BoardColumn(
          columnId: 'c-active',
          boardId: 'board-1',
          name: 'Active',
          orderIndex: 0,
          kind: BoardColumnKind.custom,
        ),
        BoardColumn(
          columnId: 'c-done',
          boardId: 'board-1',
          name: 'Done',
          orderIndex: 1,
          kind: BoardColumnKind.done,
          isDoneState: true,
        ),
      ],
      items: [goal],
    );

    final defaults = CreateItemDefaultsPolicy.resolve(
      snapshot: snapshot,
      settings: const AutofillSettings(enabled: false),
    );

    expect(defaults.columnId, 'c-active');
  });
}
