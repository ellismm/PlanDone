import 'work_item.dart';

enum BoardReminderKind {
  start,
  due,
}

class BoardReminderAlert {
  const BoardReminderAlert({
    required this.reminderId,
    required this.kind,
    required this.item,
    required this.triggerAt,
    required this.referenceAt,
    required this.title,
    required this.message,
    required this.isOverdue,
  });

  final String reminderId;
  final BoardReminderKind kind;
  final WorkItem item;
  final DateTime triggerAt;
  final DateTime referenceAt;
  final String title;
  final String message;
  final bool isOverdue;
}
