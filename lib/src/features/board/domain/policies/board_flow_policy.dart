import '../models/board.dart';
import '../models/board_flow.dart';
import '../models/board_reminder_alert.dart';
import '../models/board_snapshot.dart';
import '../models/column.dart';
import '../models/work_item.dart';
import '../models/work_item_type.dart';
import 'workflow_semantics_policy.dart';

class BoardFlowPolicy {
  const BoardFlowPolicy._();

  static BoardFlowSnapshot build({
    required List<Board> boards,
    required List<BoardSnapshot> snapshots,
    required List<BoardReminderAlert> reminders,
    required Set<WorkItemType> visibleTypes,
    required Map<String, BoardFlowSuppressionEntry> suppressedItems,
    required Map<String, BoardFlowReviewedEntry> reviewedItems,
    required DateTime now,
    required Map<String, int> accentColorValuesByItemKey,
  }) {
    final boardById = {for (final board in boards) board.boardId: board};
    final boardNamesById = {
      for (final board in boards) board.boardId: board.name,
    };
    final remindersByItemKey = {
      for (final reminder in reminders)
        '${reminder.item.boardId}::${reminder.item.itemId}': reminder,
    };

    final candidates = <BoardFlowCandidate>[];
    var reviewedTodayCount = 0;
    final todayKey = boardFlowDayKey(now);

    for (final snapshot in snapshots) {
      final board = boardById[snapshot.board.boardId] ?? snapshot.board;
      final boardColumns =
          WorkflowSemanticsPolicy.normalizeColumns(snapshot.columns)
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      final columnsById = {
        for (final column in boardColumns) column.columnId: column
      };
      final itemsById = {for (final item in snapshot.items) item.itemId: item};
      final settings = snapshot.board.validationSettings;

      for (final item in snapshot.items) {
        if (!_supportsFlowType(item, visibleTypes)) continue;
        if (item.archived || item.isInbox || item.completedAt != null) continue;

        final column = columnsById[item.columnId];
        if (column == null) continue;
        if (_isClosedColumn(column)) continue;

        final itemKey = '${item.boardId}::${item.itemId}';
        final reminder = remindersByItemKey[itemKey];
        final eligibility = _resolveEligibility(
          item: item,
          reminder: reminder,
          now: now,
        );
        if (eligibility == null) continue;

        final stateToken = _stateTokenFor(item);
        final suppressed = suppressedItems[itemKey];
        if (suppressed != null &&
            suppressed.stateToken == stateToken &&
            suppressed.until.isAfter(now)) {
          continue;
        }

        final reviewed = reviewedItems[itemKey];
        if (reviewed != null &&
            reviewed.dayKey == todayKey &&
            reviewed.stateToken == stateToken) {
          reviewedTodayCount += 1;
          continue;
        }

        final parent = item.parentId == null ? null : itemsById[item.parentId!];
        candidates.add(
          BoardFlowCandidate(
            item: item,
            board: board,
            boardName: boardNamesById[item.boardId] ?? board.name,
            parentTitle: parent?.title,
            column: column,
            message: eligibility.message,
            urgency: eligibility.urgency,
            sortKey: eligibility.sortKey,
            stateToken: stateToken,
            boardColumns: boardColumns,
            boardItems: snapshot.items,
            validationSettings: settings,
            reminderTriggered: reminder != null,
          ),
        );
      }
    }

    candidates.sort((a, b) {
      final byKey = a.sortKey.compareTo(b.sortKey);
      if (byKey != 0) return byKey;
      final byUpdated = b.item.updatedAt.compareTo(a.item.updatedAt);
      if (byUpdated != 0) return byUpdated;
      return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
    });

    return BoardFlowSnapshot(
      candidates: candidates,
      multiBoardScope: snapshots.length > 1,
      accentColorValuesByItemKey: accentColorValuesByItemKey,
      boardNamesById: boardNamesById,
      remainingTodayCount: candidates.length,
      reviewedTodayCount: reviewedTodayCount,
    );
  }

  static bool _supportsFlowType(
    WorkItem item,
    Set<WorkItemType> visibleTypes,
  ) {
    if (item.type != WorkItemType.task && item.type != WorkItemType.action) {
      return false;
    }
    return visibleTypes.contains(item.type);
  }

  static bool _isClosedColumn(BoardColumn column) {
    if (column.isDoneState || column.isCancelledState) return true;
    return column.kind == BoardColumnKind.done ||
        column.kind == BoardColumnKind.cancelled;
  }

  static _FlowEligibility? _resolveEligibility({
    required WorkItem item,
    required BoardReminderAlert? reminder,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final due = item.dueAt == null
        ? null
        : DateTime(item.dueAt!.year, item.dueAt!.month, item.dueAt!.day);

    if (due != null) {
      if (due.isBefore(today)) {
        final daysLate = today.difference(due).inDays;
        return _FlowEligibility(
          urgency: BoardFlowUrgency.overdue,
          sortKey: -daysLate,
          message: daysLate <= 1 ? 'Overdue' : 'Overdue by ${daysLate}d',
        );
      }
      if (_sameDate(due, today)) {
        return const _FlowEligibility(
          urgency: BoardFlowUrgency.today,
          sortKey: 100000000,
          message: 'Due today',
        );
      }

      final dayDistance = due.difference(today).inDays;
      return _FlowEligibility(
        urgency: BoardFlowUrgency.upcoming,
        sortKey: 300000000 + dayDistance,
        message: dayDistance == 1 ? 'Due tomorrow' : 'Due in ${dayDistance}d',
      );
    }

    if (reminder != null) {
      return _FlowEligibility(
        urgency: reminder.isOverdue
            ? BoardFlowUrgency.overdue
            : BoardFlowUrgency.reminder,
        sortKey: reminder.isOverdue ? -1 : 200000000,
        message: reminder.message,
      );
    }

    return const _FlowEligibility(
      urgency: BoardFlowUrgency.anytime,
      sortKey: 400000000,
      message: 'Ready anytime',
    );
  }

  static String _stateTokenFor(WorkItem item) {
    return [
      item.updatedAt.millisecondsSinceEpoch,
      item.dueAt?.millisecondsSinceEpoch ?? 'none',
      item.columnId,
      item.archived,
      item.completedAt?.millisecondsSinceEpoch ?? 'open',
    ].join('|');
  }

  static bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _FlowEligibility {
  const _FlowEligibility({
    required this.urgency,
    required this.sortKey,
    required this.message,
  });

  final BoardFlowUrgency urgency;
  final int sortKey;
  final String message;
}
