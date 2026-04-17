import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/board.dart';
import 'package:plandone/src/features/board/domain/models/board_flow.dart';
import 'package:plandone/src/features/board/domain/models/board_reminder_alert.dart';
import 'package:plandone/src/features/board/domain/models/board_snapshot.dart';
import 'package:plandone/src/features/board/domain/models/column.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/domain/policies/board_flow_policy.dart';

void main() {
  Board board(DateTime now) => Board(
        boardId: 'board-1',
        name: 'My Board',
        ownerId: 'user-1',
        createdAt: now,
        updatedAt: now,
      );

  const openColumns = [
    BoardColumn(
      columnId: 'todo',
      boardId: 'board-1',
      name: 'To Do',
      orderIndex: 0,
      kind: BoardColumnKind.backlog,
    ),
    BoardColumn(
      columnId: 'doing',
      boardId: 'board-1',
      name: 'Doing',
      orderIndex: 1,
      kind: BoardColumnKind.inProgress,
    ),
    BoardColumn(
      columnId: 'done',
      boardId: 'board-1',
      name: 'Done',
      orderIndex: 2,
      kind: BoardColumnKind.done,
      isDoneState: true,
    ),
  ];

  test(
      'flow policy includes all open actions and ranks overdue, today, reminder, future, then undated',
      () {
    final now = DateTime(2026, 3, 27, 9);
    final overdueAction = WorkItem(
      itemId: 'action-overdue',
      boardId: 'board-1',
      title: 'Overdue action',
      type: WorkItemType.action,
      columnId: 'todo',
      dueAt: DateTime(2026, 3, 24),
      createdAt: now,
      updatedAt: now.subtract(const Duration(days: 2)),
    );
    final todayAction = WorkItem(
      itemId: 'action-today',
      boardId: 'board-1',
      title: 'Today action',
      type: WorkItemType.action,
      columnId: 'doing',
      dueAt: DateTime(2026, 3, 27),
      createdAt: now,
      updatedAt: now.subtract(const Duration(hours: 6)),
    );
    final reminderAction = WorkItem(
      itemId: 'action-reminder',
      boardId: 'board-1',
      title: 'Reminder action',
      type: WorkItemType.action,
      columnId: 'todo',
      createdAt: now,
      updatedAt: now.subtract(const Duration(hours: 4)),
    );
    final futureAction = WorkItem(
      itemId: 'action-future',
      boardId: 'board-1',
      title: 'Future action',
      type: WorkItemType.action,
      columnId: 'todo',
      dueAt: DateTime(2026, 3, 30),
      createdAt: now,
      updatedAt: now.subtract(const Duration(hours: 2)),
    );
    final undatedAction = WorkItem(
      itemId: 'action-undated',
      boardId: 'board-1',
      title: 'Undated action',
      type: WorkItemType.action,
      columnId: 'todo',
      createdAt: now,
      updatedAt: now.subtract(const Duration(minutes: 5)),
    );
    final goal = WorkItem(
      itemId: 'goal-1',
      boardId: 'board-1',
      title: 'Goal',
      type: WorkItemType.goal,
      columnId: 'todo',
      createdAt: now,
      updatedAt: now,
    );
    final doneAction = WorkItem(
      itemId: 'action-done',
      boardId: 'board-1',
      title: 'Done action',
      type: WorkItemType.action,
      columnId: 'done',
      completedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final inboxAction = WorkItem(
      itemId: 'action-inbox',
      boardId: 'board-1',
      title: 'Inbox action',
      type: WorkItemType.action,
      columnId: 'todo',
      isInbox: true,
      createdAt: now,
      updatedAt: now,
    );

    final snapshot = BoardFlowPolicy.build(
      boards: [board(now)],
      snapshots: [
        BoardSnapshot(
          board: board(now),
          members: const [],
          columns: openColumns,
          items: [
            overdueAction,
            todayAction,
            reminderAction,
            futureAction,
            undatedAction,
            goal,
            doneAction,
            inboxAction,
          ],
        ),
      ],
      reminders: [
        BoardReminderAlert(
          reminderId: 'rem-1',
          kind: BoardReminderKind.start,
          item: reminderAction,
          boardName: 'My Board',
          triggerAt: now,
          referenceAt: now,
          title: reminderAction.title,
          message: 'Starts today',
          isOverdue: false,
        ),
      ],
      visibleTypes: const {WorkItemType.action},
      suppressedItems: const {},
      reviewedItems: const {},
      now: now,
      accentColorValuesByItemKey: const {},
    );

    expect(
      snapshot.candidates.map((entry) => entry.item.itemId).toList(),
      [
        'action-overdue',
        'action-today',
        'action-reminder',
        'action-future',
        'action-undated',
      ],
    );
    expect(snapshot.candidates.last.message, 'Ready anytime');
    expect(snapshot.remainingTodayCount, 5);
  });

  test('flow policy includes tasks only when the type filter enables them', () {
    final now = DateTime(2026, 3, 27, 9);
    final action = WorkItem(
      itemId: 'action-1',
      boardId: 'board-1',
      title: 'Action',
      type: WorkItemType.action,
      columnId: 'todo',
      createdAt: now,
      updatedAt: now,
    );
    final task = WorkItem(
      itemId: 'task-1',
      boardId: 'board-1',
      title: 'Task',
      type: WorkItemType.task,
      columnId: 'todo',
      createdAt: now,
      updatedAt: now,
    );

    final actionsOnly = BoardFlowPolicy.build(
      boards: [board(now)],
      snapshots: [
        BoardSnapshot(
          board: board(now),
          members: const [],
          columns: openColumns,
          items: [action, task],
        ),
      ],
      reminders: const [],
      visibleTypes: const {WorkItemType.action},
      suppressedItems: const {},
      reviewedItems: const {},
      now: now,
      accentColorValuesByItemKey: const {},
    );

    expect(actionsOnly.candidates.map((entry) => entry.item.itemId), ['action-1']);

    final tasksAndActions = BoardFlowPolicy.build(
      boards: [board(now)],
      snapshots: [
        BoardSnapshot(
          board: board(now),
          members: const [],
          columns: openColumns,
          items: [action, task],
        ),
      ],
      reminders: const [],
      visibleTypes: const {WorkItemType.action, WorkItemType.task},
      suppressedItems: const {},
      reviewedItems: const {},
      now: now,
      accentColorValuesByItemKey: const {},
    );

    expect(
      tasksAndActions.candidates.map((entry) => entry.item.itemId).toSet(),
      {'action-1', 'task-1'},
    );
  });

  test(
      'flow suppression hides matching state token and changed items resurface the same day',
      () {
    final now = DateTime(2026, 3, 27, 9);
    final item = WorkItem(
      itemId: 'action-1',
      boardId: 'board-1',
      title: 'Action',
      type: WorkItemType.action,
      columnId: 'todo',
      createdAt: now,
      updatedAt: now,
    );
    final stateToken = [
      item.updatedAt.millisecondsSinceEpoch,
      'none',
      item.columnId,
      item.archived,
      'open',
    ].join('|');

    final hidden = BoardFlowPolicy.build(
      boards: [board(now)],
      snapshots: [
        BoardSnapshot(
          board: board(now),
          members: const [],
          columns: openColumns,
          items: [item],
        ),
      ],
      reminders: const [],
      visibleTypes: const {WorkItemType.action},
      suppressedItems: {
        'board-1::action-1': BoardFlowSuppressionEntry(
          untilEpochMillis:
              now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
          stateToken: stateToken,
        ),
      },
      reviewedItems: const {},
      now: now,
      accentColorValuesByItemKey: const {},
    );

    expect(hidden.candidates, isEmpty);

    final changedItem =
        item.copyWith(updatedAt: now.add(const Duration(minutes: 5)));
    final resurfaced = BoardFlowPolicy.build(
      boards: [board(now)],
      snapshots: [
        BoardSnapshot(
          board: board(now),
          members: const [],
          columns: openColumns,
          items: [changedItem],
        ),
      ],
      reminders: const [],
      visibleTypes: const {WorkItemType.action},
      suppressedItems: {
        'board-1::action-1': BoardFlowSuppressionEntry(
          untilEpochMillis:
              now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
          stateToken: stateToken,
        ),
      },
      reviewedItems: const {},
      now: now,
      accentColorValuesByItemKey: const {},
    );

    expect(resurfaced.candidates, hasLength(1));
    expect(resurfaced.candidates.single.item.itemId, 'action-1');
  });

  test('flow reviewed items hide for the day and reset the next day', () {
    final now = DateTime(2026, 3, 27, 9);
    final item = WorkItem(
      itemId: 'action-1',
      boardId: 'board-1',
      title: 'Action',
      type: WorkItemType.action,
      columnId: 'todo',
      createdAt: now,
      updatedAt: now,
    );
    final stateToken = [
      item.updatedAt.millisecondsSinceEpoch,
      'none',
      item.columnId,
      item.archived,
      'open',
    ].join('|');

    final hiddenForToday = BoardFlowPolicy.build(
      boards: [board(now)],
      snapshots: [
        BoardSnapshot(
          board: board(now),
          members: const [],
          columns: openColumns,
          items: [item],
        ),
      ],
      reminders: const [],
      visibleTypes: const {WorkItemType.action},
      suppressedItems: const {},
      reviewedItems: {
        'board-1::action-1': BoardFlowReviewedEntry(
          dayKey: boardFlowDayKey(now),
          stateToken: stateToken,
        ),
      },
      now: now,
      accentColorValuesByItemKey: const {},
    );

    expect(hiddenForToday.candidates, isEmpty);
    expect(hiddenForToday.remainingTodayCount, 0);
    expect(hiddenForToday.reviewedTodayCount, 1);

    final resetTomorrow = BoardFlowPolicy.build(
      boards: [board(now)],
      snapshots: [
        BoardSnapshot(
          board: board(now),
          members: const [],
          columns: openColumns,
          items: [item],
        ),
      ],
      reminders: const [],
      visibleTypes: const {WorkItemType.action},
      suppressedItems: const {},
      reviewedItems: {
        'board-1::action-1': BoardFlowReviewedEntry(
          dayKey: boardFlowDayKey(now),
          stateToken: stateToken,
        ),
      },
      now: now.add(const Duration(days: 1)),
      accentColorValuesByItemKey: const {},
    );

    expect(resetTomorrow.candidates, hasLength(1));
    expect(resetTomorrow.remainingTodayCount, 1);
    expect(resetTomorrow.reviewedTodayCount, 0);
  });

  test('flow reviewed items can re-enter the same day after a material change', () {
    final now = DateTime(2026, 3, 27, 9);
    final item = WorkItem(
      itemId: 'action-1',
      boardId: 'board-1',
      title: 'Action',
      type: WorkItemType.action,
      columnId: 'todo',
      createdAt: now,
      updatedAt: now,
    );
    final originalStateToken = [
      item.updatedAt.millisecondsSinceEpoch,
      'none',
      item.columnId,
      item.archived,
      'open',
    ].join('|');
    final changedItem =
        item.copyWith(updatedAt: now.add(const Duration(minutes: 10)));

    final resurfaced = BoardFlowPolicy.build(
      boards: [board(now)],
      snapshots: [
        BoardSnapshot(
          board: board(now),
          members: const [],
          columns: openColumns,
          items: [changedItem],
        ),
      ],
      reminders: const [],
      visibleTypes: const {WorkItemType.action},
      suppressedItems: const {},
      reviewedItems: {
        'board-1::action-1': BoardFlowReviewedEntry(
          dayKey: boardFlowDayKey(now),
          stateToken: originalStateToken,
        ),
      },
      now: now,
      accentColorValuesByItemKey: const {},
    );

    expect(resurfaced.candidates, hasLength(1));
    expect(resurfaced.reviewedTodayCount, 0);
    expect(resurfaced.remainingTodayCount, 1);
  });
}
