import '../models/board_reminder_alert.dart';
import '../models/board_scheduled_reminder.dart';
import '../models/board_snapshot.dart';
import '../models/column.dart';
import '../models/notification_preferences.dart';
import '../models/work_item.dart';
import '../models/work_item_type.dart';

class NotificationReminderPolicy {
  static const Duration staleDueReminderWindow = Duration(days: 2);
  static const Duration staleStartReminderWindow = Duration(days: 1);

  static bool supportsQuickComplete(WorkItem item) {
    return item.type == WorkItemType.task || item.type == WorkItemType.action;
  }

  static List<BoardReminderAlert> buildActiveReminders({
    required List<WorkItem> items,
    required Map<String, BoardColumn> columnsById,
    required NotificationPreferences preferences,
    required DateTime now,
    Map<String, String> boardNamesById = const <String, String>{},
    int maxCount = 25,
  }) {
    if (!preferences.enabled) return const <BoardReminderAlert>[];
    final mutedUntil = preferences.mutedUntil;
    if (mutedUntil != null && mutedUntil.isAfter(now)) {
      return const <BoardReminderAlert>[];
    }

    final reminders = <BoardReminderAlert>[];

    for (final item in items) {
      if (item.archived) continue;
      if (_isDone(item, columnsById[item.columnId])) continue;

      if (preferences.remindOnStartDate && item.startAt != null) {
        final reminder = _buildStartReminder(
          item: item,
          now: now,
          minutesBefore: preferences.startReminderMinutesBefore,
          boardName: boardNamesById[item.boardId] ?? '',
        );
        if (reminder != null && !_isSnoozed(reminder, preferences, now)) {
          reminders.add(reminder);
        }
      }

      if (preferences.remindOnDueDate && item.dueAt != null) {
        final reminder = _buildDueReminder(
          item: item,
          now: now,
          minutesBefore: preferences.dueReminderMinutesBefore,
          boardName: boardNamesById[item.boardId] ?? '',
        );
        if (reminder != null && !_isSnoozed(reminder, preferences, now)) {
          reminders.add(reminder);
        }
      }
    }

    reminders.sort(compareActiveReminders);

    if (reminders.length <= maxCount) return reminders;
    return reminders.sublist(0, maxCount);
  }

  static List<BoardScheduledReminder> buildScheduledReminders({
    required List<BoardSnapshot> snapshots,
    required NotificationPreferences preferences,
    required DateTime now,
    int maxCount = 64,
  }) {
    if (!preferences.enabled) return const <BoardScheduledReminder>[];

    final reminders = <BoardScheduledReminder>[];

    for (final snapshot in snapshots) {
      final columnsById = {
        for (final column in snapshot.columns) column.columnId: column,
      };
      for (final item in snapshot.items) {
        if (item.archived) continue;
        if (_isDone(item, columnsById[item.columnId])) continue;

        if (preferences.remindOnStartDate && item.startAt != null) {
          final reminder = _buildScheduledStartReminder(
            boardId: snapshot.board.boardId,
            boardName: snapshot.board.name,
            item: item,
            now: now,
            preferences: preferences,
          );
          if (reminder != null) reminders.add(reminder);
        }

        if (preferences.remindOnDueDate && item.dueAt != null) {
          final reminder = _buildScheduledDueReminder(
            boardId: snapshot.board.boardId,
            boardName: snapshot.board.name,
            item: item,
            now: now,
            preferences: preferences,
          );
          if (reminder != null) reminders.add(reminder);
        }
      }
    }

    reminders.sort((a, b) {
      final byScheduledAt = a.scheduledAt.compareTo(b.scheduledAt);
      if (byScheduledAt != 0) return byScheduledAt;
      final byReference = a.referenceAt.compareTo(b.referenceAt);
      if (byReference != 0) return byReference;
      return a.itemTitle.toLowerCase().compareTo(b.itemTitle.toLowerCase());
    });

    if (reminders.length <= maxCount) return reminders;
    return reminders.sublist(0, maxCount);
  }

  static int compareActiveReminders(
    BoardReminderAlert a,
    BoardReminderAlert b,
  ) {
    if (a.isOverdue != b.isOverdue) {
      return a.isOverdue ? -1 : 1;
    }
    final kindPriorityA = _reminderPriority(a);
    final kindPriorityB = _reminderPriority(b);
    final byKind = kindPriorityA.compareTo(kindPriorityB);
    if (byKind != 0) return byKind;
    final byReference = a.referenceAt.compareTo(b.referenceAt);
    if (byReference != 0) return byReference;
    return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
  }

  static bool _isDone(WorkItem item, BoardColumn? column) {
    if (item.completedAt != null) return true;
    if (column == null) return false;
    return column.isDoneState || column.isCancelledState;
  }

  static bool _isSnoozed(
    BoardReminderAlert reminder,
    NotificationPreferences preferences,
    DateTime now,
  ) {
    final snoozedUntilMillis =
        preferences.snoozedReminderUntilEpochMillis[reminder.reminderId];
    if (snoozedUntilMillis == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(snoozedUntilMillis).isAfter(now);
  }

  static BoardReminderAlert? _buildStartReminder({
    required WorkItem item,
    required DateTime now,
    required int minutesBefore,
    required String boardName,
  }) {
    final startAt = item.startAt;
    if (startAt == null) return null;
    final triggerAt = startAt.subtract(Duration(minutes: minutesBefore));
    if (triggerAt.isAfter(now)) return null;
    if (now.difference(startAt) > staleStartReminderWindow) {
      return null;
    }

    final isLate = now.isAfter(startAt);
    final title = item.title;
    final message = isLate
        ? 'Started ${_formatRelative(now.difference(startAt))} ago'
        : 'Starts in ${_formatRelative(startAt.difference(now))}';

    return BoardReminderAlert(
      reminderId:
          '${item.itemId}|${BoardReminderKind.start.name}|${startAt.millisecondsSinceEpoch}|$minutesBefore',
      kind: BoardReminderKind.start,
      item: item,
      boardName: boardName,
      triggerAt: triggerAt,
      referenceAt: startAt,
      title: title,
      message: message,
      isOverdue: isLate,
    );
  }

  static BoardReminderAlert? _buildDueReminder({
    required WorkItem item,
    required DateTime now,
    required int minutesBefore,
    required String boardName,
  }) {
    final dueAt = item.dueAt;
    if (dueAt == null) return null;
    final triggerAt = dueAt.subtract(Duration(minutes: minutesBefore));
    if (triggerAt.isAfter(now)) return null;
    if (now.difference(dueAt) > staleDueReminderWindow) {
      return null;
    }

    final isOverdue = now.isAfter(dueAt);
    final title = item.title;
    final message = isOverdue
        ? 'Overdue by ${_formatRelative(now.difference(dueAt))}'
        : 'Due in ${_formatRelative(dueAt.difference(now))}';

    return BoardReminderAlert(
      reminderId:
          '${item.itemId}|${BoardReminderKind.due.name}|${dueAt.millisecondsSinceEpoch}|$minutesBefore',
      kind: BoardReminderKind.due,
      item: item,
      boardName: boardName,
      triggerAt: triggerAt,
      referenceAt: dueAt,
      title: title,
      message: message,
      isOverdue: isOverdue,
    );
  }

  static BoardScheduledReminder? _buildScheduledStartReminder({
    required String boardId,
    required String boardName,
    required WorkItem item,
    required DateTime now,
    required NotificationPreferences preferences,
  }) {
    final startAt = item.startAt;
    if (startAt == null) return null;
    final triggerAt = startAt.subtract(
      Duration(minutes: preferences.startReminderMinutesBefore),
    );
    final reminderId =
        '${item.itemId}|${BoardReminderKind.start.name}|${startAt.millisecondsSinceEpoch}|${preferences.startReminderMinutesBefore}';
    final scheduledAt = _resolveScheduledAt(
      reminderId: reminderId,
      triggerAt: triggerAt,
      referenceAt: startAt,
      staleWindow: staleStartReminderWindow,
      preferences: preferences,
      now: now,
    );
    if (scheduledAt == null) return null;

    final isLate = scheduledAt.isAfter(startAt);
    return BoardScheduledReminder(
      reminderId: reminderId,
      boardId: boardId,
      boardName: boardName,
      itemId: item.itemId,
      itemTitle: item.title,
      kind: BoardReminderKind.start,
      title: item.title,
      message: isLate
          ? 'Started at ${_formatDateTime(startAt)} • $boardName'
          : 'Starts at ${_formatDateTime(startAt)} • $boardName',
      scheduledAt: scheduledAt,
      referenceAt: startAt,
      supportsQuickComplete: supportsQuickComplete(item),
    );
  }

  static BoardScheduledReminder? _buildScheduledDueReminder({
    required String boardId,
    required String boardName,
    required WorkItem item,
    required DateTime now,
    required NotificationPreferences preferences,
  }) {
    final dueAt = item.dueAt;
    if (dueAt == null) return null;
    final triggerAt = dueAt.subtract(
      Duration(minutes: preferences.dueReminderMinutesBefore),
    );
    final reminderId =
        '${item.itemId}|${BoardReminderKind.due.name}|${dueAt.millisecondsSinceEpoch}|${preferences.dueReminderMinutesBefore}';
    final scheduledAt = _resolveScheduledAt(
      reminderId: reminderId,
      triggerAt: triggerAt,
      referenceAt: dueAt,
      staleWindow: staleDueReminderWindow,
      preferences: preferences,
      now: now,
    );
    if (scheduledAt == null) return null;

    final isLate = scheduledAt.isAfter(dueAt);
    return BoardScheduledReminder(
      reminderId: reminderId,
      boardId: boardId,
      boardName: boardName,
      itemId: item.itemId,
      itemTitle: item.title,
      kind: BoardReminderKind.due,
      title: item.title,
      message: isLate
          ? 'Was due at ${_formatDateTime(dueAt)} • $boardName'
          : 'Due at ${_formatDateTime(dueAt)} • $boardName',
      scheduledAt: scheduledAt,
      referenceAt: dueAt,
      supportsQuickComplete: supportsQuickComplete(item),
    );
  }

  static DateTime? _resolveScheduledAt({
    required String reminderId,
    required DateTime triggerAt,
    required DateTime referenceAt,
    required Duration staleWindow,
    required NotificationPreferences preferences,
    required DateTime now,
  }) {
    DateTime? scheduledAt;
    final snoozedUntilMillis =
        preferences.snoozedReminderUntilEpochMillis[reminderId];
    if (snoozedUntilMillis != null) {
      final snoozedUntil =
          DateTime.fromMillisecondsSinceEpoch(snoozedUntilMillis);
      if (snoozedUntil.isAfter(now)) {
        scheduledAt = snoozedUntil;
      }
    }
    scheduledAt ??= triggerAt.isAfter(now) ? triggerAt : null;
    if (scheduledAt == null) return null;

    final mutedUntil = preferences.mutedUntil;
    if (mutedUntil != null && mutedUntil.isAfter(scheduledAt)) {
      scheduledAt = mutedUntil;
    }
    if (!scheduledAt.isAfter(now)) return null;

    final staleAt = referenceAt.add(staleWindow);
    if (scheduledAt.isAfter(staleAt)) return null;
    return scheduledAt;
  }

  static String _formatRelative(Duration duration) {
    final abs = duration.abs();
    if (abs.inMinutes < 1) return 'less than a minute';
    if (abs.inHours < 1) {
      final minutes = abs.inMinutes;
      return minutes == 1 ? '1 minute' : '$minutes minutes';
    }
    if (abs.inDays < 1) {
      final hours = abs.inHours;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    final days = abs.inDays;
    return days == 1 ? '1 day' : '$days days';
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int input) => input.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static int _reminderPriority(BoardReminderAlert reminder) {
    if (reminder.isOverdue) return 0;
    return switch (reminder.kind) {
      BoardReminderKind.due => 1,
      BoardReminderKind.start => 2,
    };
  }
}
