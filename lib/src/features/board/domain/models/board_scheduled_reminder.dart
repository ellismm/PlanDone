import 'board_reminder_alert.dart';

class BoardScheduledReminder {
  const BoardScheduledReminder({
    required this.reminderId,
    required this.boardId,
    required this.boardName,
    required this.itemId,
    required this.itemTitle,
    required this.kind,
    required this.title,
    required this.message,
    required this.scheduledAt,
    required this.referenceAt,
    required this.supportsQuickComplete,
  });

  final String reminderId;
  final String boardId;
  final String boardName;
  final String itemId;
  final String itemTitle;
  final BoardReminderKind kind;
  final String title;
  final String message;
  final DateTime scheduledAt;
  final DateTime referenceAt;
  final bool supportsQuickComplete;
}
