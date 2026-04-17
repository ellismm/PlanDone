import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/board.dart';
import 'package:plandone/src/features/board/domain/models/board_insights.dart';
import 'package:plandone/src/features/board/domain/models/board_snapshot.dart';
import 'package:plandone/src/features/board/domain/models/board_workflow_settings.dart';
import 'package:plandone/src/features/board/domain/models/column.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_activity_event.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/domain/policies/board_insights_policy.dart';

void main() {
  const boardId = 'board-1';
  final now = DateTime(2026, 3, 20, 9);

  BoardSnapshot snapshotWithItems(List<WorkItem> items) {
    return BoardSnapshot(
      board: Board(
        boardId: boardId,
        name: 'Metrics board',
        ownerId: 'user-1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: now,
        workflowSettings: const BoardWorkflowSettings(
          templateId: BoardWorkflowSettings.legacyTemplateId,
        ),
      ),
      members: const [],
      columns: const [
        BoardColumn(
          columnId: 'c-plan',
          boardId: boardId,
          name: 'Planning',
          orderIndex: 0,
          kind: BoardColumnKind.planning,
        ),
        BoardColumn(
          columnId: 'c-doing',
          boardId: boardId,
          name: 'Doing',
          orderIndex: 1,
          kind: BoardColumnKind.inProgress,
        ),
        BoardColumn(
          columnId: 'c-blocked',
          boardId: boardId,
          name: 'Blocked',
          orderIndex: 2,
          kind: BoardColumnKind.blocked,
          isBlockedState: true,
        ),
        BoardColumn(
          columnId: 'c-done',
          boardId: boardId,
          name: 'Done',
          orderIndex: 3,
          kind: BoardColumnKind.done,
          isDoneState: true,
        ),
        BoardColumn(
          columnId: 'c-cancelled',
          boardId: boardId,
          name: 'Cancelled',
          orderIndex: 4,
          kind: BoardColumnKind.cancelled,
          isDoneState: true,
          isCancelledState: true,
        ),
      ],
      items: items,
    );
  }

  WorkItem item({
    required String id,
    required WorkItemType type,
    required String columnId,
    DateTime? completedAt,
    DateTime? dueAt,
    DateTime? updatedAt,
    bool archived = false,
    bool isInbox = false,
  }) {
    return WorkItem(
      itemId: id,
      boardId: boardId,
      title: id,
      type: type,
      columnId: columnId,
      completedAt: completedAt,
      dueAt: dueAt,
      archived: archived,
      isInbox: isInbox,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updatedAt ?? now,
    );
  }

  test('build computes accomplished, health, and accountability metrics', () {
    final snapshot = snapshotWithItems([
      item(
        id: 'goal-done-today',
        type: WorkItemType.goal,
        columnId: 'c-done',
        completedAt: DateTime(2026, 3, 20, 8),
        dueAt: DateTime(2026, 3, 20, 12),
      ),
      item(
        id: 'project-done-yesterday',
        type: WorkItemType.project,
        columnId: 'c-done',
        completedAt: DateTime(2026, 3, 19, 14),
        dueAt: DateTime(2026, 3, 18, 12),
      ),
      item(
        id: 'task-done-two-days-ago',
        type: WorkItemType.task,
        columnId: 'c-done',
        completedAt: DateTime(2026, 3, 18, 10),
      ),
      item(
        id: 'action-done-archived',
        type: WorkItemType.action,
        columnId: 'c-done',
        completedAt: DateTime(2026, 3, 18, 11),
        archived: true,
      ),
      item(
        id: 'action-previous-window',
        type: WorkItemType.action,
        columnId: 'c-done',
        completedAt: DateTime(2026, 3, 12, 9),
      ),
      item(
        id: 'cancelled-completed',
        type: WorkItemType.action,
        columnId: 'c-cancelled',
        completedAt: DateTime(2026, 3, 19, 9),
      ),
      item(
        id: 'overdue-open',
        type: WorkItemType.task,
        columnId: 'c-doing',
        dueAt: DateTime(2026, 3, 18, 9),
      ),
      item(
        id: 'blocked-open',
        type: WorkItemType.action,
        columnId: 'c-blocked',
        dueAt: DateTime(2026, 3, 25, 9),
      ),
      item(
        id: 'stale-active',
        type: WorkItemType.project,
        columnId: 'c-doing',
        updatedAt: DateTime(2026, 3, 10, 9),
      ),
      item(
        id: 'inbox-pending',
        type: WorkItemType.action,
        columnId: 'c-plan',
        isInbox: true,
      ),
    ]);

    final insights = BoardInsightsPolicy.build(
      snapshot: snapshot,
      boardActivity: [
        WorkItemActivityEvent(
          eventId: 'evt-1',
          boardId: boardId,
          itemId: 'project-done-yesterday',
          type: WorkItemActivityType.reopened,
          actorUserId: 'user-1',
          createdAt: DateTime(2026, 3, 19, 16),
        ),
        WorkItemActivityEvent(
          eventId: 'evt-2',
          boardId: boardId,
          itemId: 'old-item',
          type: WorkItemActivityType.reopened,
          actorUserId: 'user-1',
          createdAt: DateTime(2026, 2, 1, 8),
        ),
      ],
      range: BoardInsightsRange.sevenDays,
      now: now,
    );

    expect(insights.completedByType[WorkItemType.goal], 1);
    expect(insights.completedByType[WorkItemType.project], 1);
    expect(insights.completedByType[WorkItemType.task], 1);
    expect(insights.completedByType[WorkItemType.action], 1);
    expect(insights.completedTotal, 4);
    expect(insights.impactScore, 17);
    expect(insights.completedDelta?.difference, 3);
    expect(insights.impactDelta?.difference, 16);
    expect(insights.currentStreak, 3);
    expect(insights.bestStreak, 3);
    expect(insights.onTimeCompletionCount, 1);
    expect(insights.dueTrackedCompletionCount, 2);
    expect(insights.slippedDueCount, 1);
    expect(insights.overdueOpenCount, 1);
    expect(insights.blockedLoadCount, 1);
    expect(insights.staleActiveCount, 1);
    expect(insights.reopenedCount, 1);
    expect(insights.inboxPendingCount, 1);
    expect(insights.openTotalCount, 3);
    expect(insights.openActionCount, 1);
    expect(insights.openTaskCount, 1);
    expect(insights.activeExecutionCount, 3);
    expect(insights.readyQueueCount, 0);
    expect(insights.dueTodayOpenCount, 0);
    expect(insights.dueSoonOpenCount, 1);
    expect(insights.undatedOpenActionCount, 0);
    expect(insights.completionActiveDayCount, 3);
    expect(insights.pressureCount, 3);
    expect(insights.mood, BoardInsightsMood.moving);
    expect(insights.focusPrompt, contains('Clear the inbox first'));
  });

  test('all-time range keeps all completions and drops previous-period deltas',
      () {
    final snapshot = snapshotWithItems([
      item(
        id: 'goal-done',
        type: WorkItemType.goal,
        columnId: 'c-done',
        completedAt: DateTime(2026, 1, 7, 8),
      ),
      item(
        id: 'action-done',
        type: WorkItemType.action,
        columnId: 'c-done',
        completedAt: DateTime(2026, 3, 20, 8),
      ),
    ]);

    final insights = BoardInsightsPolicy.build(
      snapshot: snapshot,
      boardActivity: const [],
      range: BoardInsightsRange.allTime,
      now: now,
    );

    expect(insights.completedTotal, 2);
    expect(insights.impactScore, 9);
    expect(insights.completedDelta, isNull);
    expect(insights.impactDelta, isNull);
    expect(insights.trendGranularity, BoardInsightsTrendGranularity.month);
    expect(insights.openTotalCount, 0);
    expect(insights.completionActiveDayCount, 2);
  });
}
