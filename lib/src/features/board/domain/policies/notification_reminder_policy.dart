import '../models/board_reminder_alert.dart';
import '../models/column.dart';
import '../models/notification_preferences.dart';
import '../models/work_item.dart';

class NotificationReminderPolicy {
  static const Duration staleDueReminderWindow = Duration(days: 2);
  static const Duration staleStartReminderWindow = Duration(days: 1);

  static List<BoardReminderAlert> buildActiveReminders({
    required List<WorkItem> items,
    required Map<String, BoardColumn> columnsById,
    required NotificationPreferences preferences,
    required DateTime now,
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
        );
        if (reminder != null && !_isSnoozed(reminder, preferences, now)) {
          reminders.add(reminder);
        }
      }
    }

    reminders.sort((a, b) {
      if (a.isOverdue != b.isOverdue) {
        return a.isOverdue ? -1 : 1;
      }
      final byReference = a.referenceAt.compareTo(b.referenceAt);
      if (byReference != 0) return byReference;
      return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
    });

    if (reminders.length <= maxCount) return reminders;
    return reminders.sublist(0, maxCount);
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
  }) {
    final startAt = item.startAt;
    if (startAt == null) return null;
    final triggerAt = startAt.subtract(Duration(minutes: minutesBefore));
    if (triggerAt.isAfter(now)) return null;
    if (now.difference(startAt) > staleStartReminderWindow) {
      return null;
    }

    final isLate = now.isAfter(startAt);
    final title = isLate ? 'Start date passed' : 'Starting soon';
    final message = isLate
        ? '"${item.title}" should have started ${_formatRelative(now.difference(startAt))} ago.'
        : '"${item.title}" starts in ${_formatRelative(startAt.difference(now))}.';

    return BoardReminderAlert(
      reminderId:
          '${item.itemId}|${BoardReminderKind.start.name}|${startAt.millisecondsSinceEpoch}|$minutesBefore',
      kind: BoardReminderKind.start,
      item: item,
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
  }) {
    final dueAt = item.dueAt;
    if (dueAt == null) return null;
    final triggerAt = dueAt.subtract(Duration(minutes: minutesBefore));
    if (triggerAt.isAfter(now)) return null;
    if (now.difference(dueAt) > staleDueReminderWindow) {
      return null;
    }

    final isOverdue = now.isAfter(dueAt);
    final title = isOverdue ? 'Overdue' : 'Due soon';
    final message = isOverdue
        ? '"${item.title}" is overdue by ${_formatRelative(now.difference(dueAt))}.'
        : '"${item.title}" is due in ${_formatRelative(dueAt.difference(now))}.';

    return BoardReminderAlert(
      reminderId:
          '${item.itemId}|${BoardReminderKind.due.name}|${dueAt.millisecondsSinceEpoch}|$minutesBefore',
      kind: BoardReminderKind.due,
      item: item,
      triggerAt: triggerAt,
      referenceAt: dueAt,
      title: title,
      message: message,
      isOverdue: isOverdue,
    );
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
}
