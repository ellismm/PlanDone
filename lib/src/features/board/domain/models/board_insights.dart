import 'work_item_type.dart';

enum BoardInsightsRange {
  sevenDays,
  thirtyDays,
  ninetyDays,
  allTime,
}

extension BoardInsightsRangeX on BoardInsightsRange {
  int? get dayWindow => switch (this) {
        BoardInsightsRange.sevenDays => 7,
        BoardInsightsRange.thirtyDays => 30,
        BoardInsightsRange.ninetyDays => 90,
        BoardInsightsRange.allTime => null,
      };

  String get shortLabel => switch (this) {
        BoardInsightsRange.sevenDays => '7D',
        BoardInsightsRange.thirtyDays => '30D',
        BoardInsightsRange.ninetyDays => '90D',
        BoardInsightsRange.allTime => 'All',
      };

  String get rangeLabel => switch (this) {
        BoardInsightsRange.sevenDays => 'Last 7 days',
        BoardInsightsRange.thirtyDays => 'Last 30 days',
        BoardInsightsRange.ninetyDays => 'Last 90 days',
        BoardInsightsRange.allTime => 'All time',
      };
}

enum BoardInsightsTrendGranularity {
  day,
  week,
  month,
}

extension BoardInsightsTrendGranularityX on BoardInsightsTrendGranularity {
  String get label => switch (this) {
        BoardInsightsTrendGranularity.day => 'Daily',
        BoardInsightsTrendGranularity.week => 'Weekly',
        BoardInsightsTrendGranularity.month => 'Monthly',
      };
}

class BoardInsightsDelta {
  const BoardInsightsDelta({
    required this.current,
    required this.previous,
  });

  final int current;
  final int previous;

  int get difference => current - previous;
}

class BoardInsightsTrendBucket {
  const BoardInsightsTrendBucket({
    required this.label,
    required this.completedCount,
  });

  final String label;
  final int completedCount;
}

class BoardInsightsSnapshot {
  const BoardInsightsSnapshot({
    required this.boardId,
    required this.generatedAt,
    required this.range,
    required this.completedByType,
    required this.completedTotal,
    required this.impactScore,
    required this.completionTrend,
    required this.trendGranularity,
    required this.currentStreak,
    required this.bestStreak,
    required this.onTimeCompletionCount,
    required this.dueTrackedCompletionCount,
    required this.overdueOpenCount,
    required this.blockedLoadCount,
    required this.staleActiveCount,
    required this.reopenedCount,
    required this.slippedDueCount,
    required this.inboxPendingCount,
    required this.openTotalCount,
    required this.openActionCount,
    required this.openTaskCount,
    required this.activeExecutionCount,
    required this.readyQueueCount,
    required this.dueTodayOpenCount,
    required this.dueSoonOpenCount,
    required this.undatedOpenActionCount,
    required this.recentlyCreatedCount,
    required this.completionActiveDayCount,
    this.completedDelta,
    this.impactDelta,
  });

  final String boardId;
  final DateTime generatedAt;
  final BoardInsightsRange range;
  final Map<WorkItemType, int> completedByType;
  final int completedTotal;
  final int impactScore;
  final List<BoardInsightsTrendBucket> completionTrend;
  final BoardInsightsTrendGranularity trendGranularity;
  final int currentStreak;
  final int bestStreak;
  final BoardInsightsDelta? completedDelta;
  final BoardInsightsDelta? impactDelta;
  final int onTimeCompletionCount;
  final int dueTrackedCompletionCount;
  final int overdueOpenCount;
  final int blockedLoadCount;
  final int staleActiveCount;
  final int reopenedCount;
  final int slippedDueCount;
  final int inboxPendingCount;
  final int openTotalCount;
  final int openActionCount;
  final int openTaskCount;
  final int activeExecutionCount;
  final int readyQueueCount;
  final int dueTodayOpenCount;
  final int dueSoonOpenCount;
  final int undatedOpenActionCount;
  final int recentlyCreatedCount;
  final int completionActiveDayCount;

  double? get onTimeCompletionRate => dueTrackedCompletionCount == 0
      ? null
      : onTimeCompletionCount / dueTrackedCompletionCount;

  double get actionShareOfOpen =>
      openTotalCount == 0 ? 0 : openActionCount / openTotalCount;

  double get averageCompletedPerActiveDay => completionActiveDayCount == 0
      ? 0
      : completedTotal / completionActiveDayCount;

  int get pressureCount =>
      overdueOpenCount +
      dueTodayOpenCount +
      blockedLoadCount +
      staleActiveCount;

  BoardInsightsMood get mood {
    if (pressureCount >= 8 || overdueOpenCount >= 4 || blockedLoadCount >= 4) {
      return BoardInsightsMood.heavy;
    }
    if (completedTotal > 0 && pressureCount <= 2) {
      return BoardInsightsMood.clear;
    }
    if (activeExecutionCount > 0 || dueSoonOpenCount > 0) {
      return BoardInsightsMood.moving;
    }
    return BoardInsightsMood.quiet;
  }

  String get focusPrompt {
    if (inboxPendingCount > 0) {
      return 'Clear the inbox first: $inboxPendingCount captured ${inboxPendingCount == 1 ? 'item needs' : 'items need'} a home.';
    }
    if (overdueOpenCount > 0) {
      return 'Start with overdue work: $overdueOpenCount open ${overdueOpenCount == 1 ? 'item is' : 'items are'} past due.';
    }
    if (blockedLoadCount > 0) {
      return 'Unblock the board: $blockedLoadCount ${blockedLoadCount == 1 ? 'item is' : 'items are'} waiting on friction.';
    }
    if (staleActiveCount > 0) {
      return 'Refresh stale active work: $staleActiveCount ${staleActiveCount == 1 ? 'item has' : 'items have'} gone quiet for 7+ days.';
    }
    if (dueTodayOpenCount > 0) {
      return 'Today has a clear target: $dueTodayOpenCount due ${dueTodayOpenCount == 1 ? 'item' : 'items'} need attention.';
    }
    if (openActionCount > 0) {
      return 'Run a small action sweep: $openActionCount open ${openActionCount == 1 ? 'action is' : 'actions are'} available.';
    }
    return 'The board is calm. Capture the next real action when it appears.';
  }
}

enum BoardInsightsMood {
  clear,
  moving,
  heavy,
  quiet,
}

extension BoardInsightsMoodX on BoardInsightsMood {
  String get label => switch (this) {
        BoardInsightsMood.clear => 'Clear',
        BoardInsightsMood.moving => 'Moving',
        BoardInsightsMood.heavy => 'Heavy',
        BoardInsightsMood.quiet => 'Quiet',
      };
}
