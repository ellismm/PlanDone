import '../models/board_insights.dart';
import '../models/board_snapshot.dart';
import '../models/column.dart';
import '../models/work_item.dart';
import '../models/work_item_activity_event.dart';
import '../models/work_item_type.dart';
import 'workflow_semantics_policy.dart';

class BoardInsightsPolicy {
  static const Map<WorkItemType, int> _impactWeights = {
    WorkItemType.goal: 8,
    WorkItemType.project: 5,
    WorkItemType.task: 3,
    WorkItemType.action: 1,
  };

  static BoardInsightsSnapshot build({
    required BoardSnapshot snapshot,
    required List<WorkItemActivityEvent> boardActivity,
    required BoardInsightsRange range,
    required DateTime now,
  }) {
    final normalizedColumns = WorkflowSemanticsPolicy.normalizeColumns(
      snapshot.columns,
    );
    final columnsById = {
      for (final column in normalizedColumns) column.columnId: column,
    };
    final window = _rangeWindow(range: range, now: now);
    final currentCompleted = snapshot.items.where(
      (item) =>
          _countsTowardCompletion(item, columnsById) &&
          _isWithinWindow(item.completedAt, window.start, window.endExclusive),
    );
    final previousStart = window.previousStart;
    final previousCompleted = previousStart == null
        ? const <WorkItem>[]
        : snapshot.items.where(
            (item) =>
                _countsTowardCompletion(item, columnsById) &&
                _isWithinWindow(
                  item.completedAt,
                  previousStart,
                  window.start,
                ),
          );

    final completedByType = {
      for (final type in WorkItemType.values)
        type: currentCompleted.where((item) => item.type == type).length,
    };
    final currentCompletedList = currentCompleted.toList(growable: false);
    final previousCompletedList = previousCompleted.toList(growable: false);

    final completedTotal = currentCompletedList.length;
    final impactScore = _impactScore(currentCompletedList);
    final completedDelta = window.previousStart == null
        ? null
        : BoardInsightsDelta(
            current: completedTotal,
            previous: previousCompletedList.length,
          );
    final impactDelta = window.previousStart == null
        ? null
        : BoardInsightsDelta(
            current: impactScore,
            previous: _impactScore(previousCompletedList),
          );
    final openItems = snapshot.items
        .where((item) => _isOpen(item, columnsById))
        .toList(growable: false);
    final todayStart = _startOfDay(now);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final soonEndExclusive = todayStart.add(const Duration(days: 8));

    final dueTracked = currentCompletedList
        .where((item) => item.dueAt != null)
        .toList(growable: false);
    final onTimeCompletionCount = dueTracked
        .where((item) => !item.completedAt!.isAfter(item.dueAt!))
        .length;
    final slippedDueCount = dueTracked.length - onTimeCompletionCount;

    final overdueOpenCount = snapshot.items
        .where(
          (item) =>
              _isOpen(item, columnsById) &&
              item.dueAt != null &&
              item.dueAt!.isBefore(now),
        )
        .length;
    final blockedLoadCount = snapshot.items
        .where(
          (item) => _isOpen(item, columnsById) && _isBlocked(item, columnsById),
        )
        .length;
    final staleActiveCount = snapshot.items
        .where(
          (item) =>
              _isOpen(item, columnsById) &&
              _isActiveExecutionItem(item, columnsById) &&
              item.updatedAt.isBefore(now.subtract(const Duration(days: 7))),
        )
        .length;
    final reopenedCount = boardActivity
        .where(
          (event) =>
              event.type == WorkItemActivityType.reopened &&
              _isWithinWindow(
                  event.createdAt, window.start, window.endExclusive),
        )
        .length;
    final inboxPendingCount =
        snapshot.items.where((item) => item.isInbox && !item.archived).length;
    final openActionCount =
        openItems.where((item) => item.type == WorkItemType.action).length;
    final completionActiveDayCount = {
      for (final item in currentCompletedList)
        if (item.completedAt != null) _startOfDay(item.completedAt!),
    }.length;

    final allCompletedItems = snapshot.items
        .where((item) => _countsTowardCompletion(item, columnsById))
        .toList(growable: false);

    return BoardInsightsSnapshot(
      boardId: snapshot.board.boardId,
      generatedAt: now,
      range: range,
      completedByType: completedByType,
      completedTotal: completedTotal,
      impactScore: impactScore,
      completionTrend: _buildTrend(
        completedItems: currentCompletedList,
        range: range,
        now: now,
      ),
      trendGranularity: _trendGranularityFor(range),
      currentStreak: _currentStreak(
        completedItems: allCompletedItems,
        now: now,
      ),
      bestStreak: _bestStreak(
        completedItems: currentCompletedList,
      ),
      completedDelta: completedDelta,
      impactDelta: impactDelta,
      onTimeCompletionCount: onTimeCompletionCount,
      dueTrackedCompletionCount: dueTracked.length,
      overdueOpenCount: overdueOpenCount,
      blockedLoadCount: blockedLoadCount,
      staleActiveCount: staleActiveCount,
      reopenedCount: reopenedCount,
      slippedDueCount: slippedDueCount,
      inboxPendingCount: inboxPendingCount,
      openTotalCount: openItems.length,
      openActionCount: openActionCount,
      openTaskCount:
          openItems.where((item) => item.type == WorkItemType.task).length,
      activeExecutionCount: openItems
          .where((item) => _isActiveExecutionItem(item, columnsById))
          .length,
      readyQueueCount: openItems
          .where((item) => _isReadyOrPlanningItem(item, columnsById))
          .length,
      dueTodayOpenCount: openItems
          .where(
            (item) =>
                item.dueAt != null &&
                !item.dueAt!.isBefore(todayStart) &&
                item.dueAt!.isBefore(tomorrowStart),
          )
          .length,
      dueSoonOpenCount: openItems
          .where(
            (item) =>
                item.dueAt != null &&
                !item.dueAt!.isBefore(todayStart) &&
                item.dueAt!.isBefore(soonEndExclusive),
          )
          .length,
      undatedOpenActionCount: openItems
          .where(
            (item) => item.type == WorkItemType.action && item.dueAt == null,
          )
          .length,
      recentlyCreatedCount: openItems
          .where(
            (item) => !item.createdAt.isBefore(window.start),
          )
          .length,
      completionActiveDayCount: completionActiveDayCount,
    );
  }

  static int _impactScore(List<WorkItem> items) {
    return items.fold<int>(
      0,
      (total, item) => total + (_impactWeights[item.type] ?? 0),
    );
  }

  static bool _countsTowardCompletion(
    WorkItem item,
    Map<String, BoardColumn> columnsById,
  ) {
    if (item.completedAt == null) return false;
    final column = columnsById[item.columnId];
    if (column?.isCancelledState ?? false) return false;
    return true;
  }

  static bool _isOpen(WorkItem item, Map<String, BoardColumn> columnsById) {
    if (item.archived || item.isInbox) return false;
    final column = columnsById[item.columnId];
    if (column?.isDoneState ?? false) return false;
    return true;
  }

  static bool _isBlocked(
    WorkItem item,
    Map<String, BoardColumn> columnsById,
  ) {
    final column = columnsById[item.columnId];
    if (column == null) return false;
    return column.isBlockedState || column.kind == BoardColumnKind.blocked;
  }

  static bool _isActiveExecutionItem(
    WorkItem item,
    Map<String, BoardColumn> columnsById,
  ) {
    final kind = columnsById[item.columnId]?.kind;
    return kind == BoardColumnKind.inProgress ||
        kind == BoardColumnKind.review ||
        kind == BoardColumnKind.blocked ||
        kind == BoardColumnKind.urgent;
  }

  static bool _isReadyOrPlanningItem(
    WorkItem item,
    Map<String, BoardColumn> columnsById,
  ) {
    final kind = columnsById[item.columnId]?.kind;
    return kind == BoardColumnKind.planning ||
        kind == BoardColumnKind.backlog ||
        kind == BoardColumnKind.ready ||
        kind == BoardColumnKind.custom;
  }

  static bool _isWithinWindow(
    DateTime? value,
    DateTime start,
    DateTime endExclusive,
  ) {
    if (value == null) return false;
    return !value.isBefore(start) && value.isBefore(endExclusive);
  }

  static _RangeWindow _rangeWindow({
    required BoardInsightsRange range,
    required DateTime now,
  }) {
    final todayStart = _startOfDay(now);
    final endExclusive = todayStart.add(const Duration(days: 1));
    final days = range.dayWindow;
    if (days == null) {
      return _RangeWindow(
        start: DateTime.fromMillisecondsSinceEpoch(0),
        endExclusive: endExclusive,
        previousStart: null,
      );
    }

    final start = todayStart.subtract(Duration(days: days - 1));
    final previousStart = start.subtract(Duration(days: days));
    return _RangeWindow(
      start: start,
      endExclusive: endExclusive,
      previousStart: previousStart,
    );
  }

  static BoardInsightsTrendGranularity _trendGranularityFor(
    BoardInsightsRange range,
  ) {
    return switch (range) {
      BoardInsightsRange.sevenDays => BoardInsightsTrendGranularity.day,
      BoardInsightsRange.thirtyDays => BoardInsightsTrendGranularity.day,
      BoardInsightsRange.ninetyDays => BoardInsightsTrendGranularity.week,
      BoardInsightsRange.allTime => BoardInsightsTrendGranularity.month,
    };
  }

  static List<BoardInsightsTrendBucket> _buildTrend({
    required List<WorkItem> completedItems,
    required BoardInsightsRange range,
    required DateTime now,
  }) {
    final completionsByDay = <DateTime, int>{};
    for (final item in completedItems) {
      final completedAt = item.completedAt;
      if (completedAt == null) continue;
      final key = _startOfDay(completedAt);
      completionsByDay.update(key, (count) => count + 1, ifAbsent: () => 1);
    }

    switch (range) {
      case BoardInsightsRange.sevenDays:
      case BoardInsightsRange.thirtyDays:
        final days = range.dayWindow!;
        final start = _startOfDay(now).subtract(Duration(days: days - 1));
        return List.generate(days, (index) {
          final day = start.add(Duration(days: index));
          return BoardInsightsTrendBucket(
            label: _monthDayLabel(day),
            completedCount: completionsByDay[day] ?? 0,
          );
        });
      case BoardInsightsRange.ninetyDays:
        final currentWeekStart = _startOfWeek(now);
        return List.generate(13, (index) {
          final weekStart = currentWeekStart.subtract(
            Duration(days: 7 * (12 - index)),
          );
          var count = 0;
          for (var offset = 0; offset < 7; offset++) {
            count +=
                completionsByDay[weekStart.add(Duration(days: offset))] ?? 0;
          }
          return BoardInsightsTrendBucket(
            label: _monthDayLabel(weekStart),
            completedCount: count,
          );
        });
      case BoardInsightsRange.allTime:
        final currentMonthStart = DateTime(now.year, now.month);
        return List.generate(12, (index) {
          final monthStart = DateTime(
            currentMonthStart.year,
            currentMonthStart.month - (11 - index),
          );
          final nextMonth = DateTime(monthStart.year, monthStart.month + 1);
          var count = 0;
          for (final entry in completionsByDay.entries) {
            final day = entry.key;
            if (!day.isBefore(monthStart) && day.isBefore(nextMonth)) {
              count += entry.value;
            }
          }
          return BoardInsightsTrendBucket(
            label: _monthLabel(monthStart),
            completedCount: count,
          );
        });
    }
  }

  static int _currentStreak({
    required List<WorkItem> completedItems,
    required DateTime now,
  }) {
    final completionDays = {
      for (final item in completedItems)
        if (item.completedAt != null) _startOfDay(item.completedAt!),
    };
    var streak = 0;
    var cursor = _startOfDay(now);
    while (completionDays.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int _bestStreak({required List<WorkItem> completedItems}) {
    final sortedDays = {
      for (final item in completedItems)
        if (item.completedAt != null) _startOfDay(item.completedAt!),
    }.toList()
      ..sort();
    if (sortedDays.isEmpty) return 0;

    var best = 1;
    var current = 1;
    for (var i = 1; i < sortedDays.length; i++) {
      final previous = sortedDays[i - 1];
      final currentDay = sortedDays[i];
      final gap = currentDay.difference(previous).inDays;
      if (gap == 1) {
        current += 1;
        if (current > best) best = current;
      } else if (gap > 1) {
        current = 1;
      }
    }
    return best;
  }

  static DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static DateTime _startOfWeek(DateTime value) {
    final dayStart = _startOfDay(value);
    return dayStart
        .subtract(Duration(days: dayStart.weekday - DateTime.monday));
  }

  static String _monthDayLabel(DateTime value) {
    const monthLabels = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthLabels[value.month]} ${value.day}';
  }

  static String _monthLabel(DateTime value) {
    const monthLabels = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return monthLabels[value.month];
  }
}

class _RangeWindow {
  const _RangeWindow({
    required this.start,
    required this.endExclusive,
    required this.previousStart,
  });

  final DateTime start;
  final DateTime endExclusive;
  final DateTime? previousStart;
}
