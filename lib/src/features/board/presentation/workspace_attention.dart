import '../domain/models/board_reminder_alert.dart';

enum WorkspaceAttentionNoticeCategory {
  access,
  sync,
  reminder,
}

enum WorkspaceAttentionSeverity {
  neutral,
  warning,
  critical,
}

enum WorkspaceNoticeActionKind {
  reminderDone,
  reminderOpen,
  reminderSnooze,
  retrySync,
  reviewSync,
}

class WorkspaceNoticeAction {
  const WorkspaceNoticeAction({
    required this.kind,
    required this.label,
  });

  final WorkspaceNoticeActionKind kind;
  final String label;
}

enum WorkspaceSystemNoticeKind {
  permissionDenied,
  syncFailed,
  retryScheduled,
}

class WorkspaceSystemNotice {
  const WorkspaceSystemNotice({
    required this.noticeId,
    required this.kind,
    required this.title,
    required this.message,
    required this.severity,
    required this.stateToken,
    required this.primaryAction,
    this.secondaryAction,
    this.dismissible = true,
  });

  final String noticeId;
  final WorkspaceSystemNoticeKind kind;
  final String title;
  final String message;
  final WorkspaceAttentionSeverity severity;
  final String stateToken;
  final WorkspaceNoticeAction primaryAction;
  final WorkspaceNoticeAction? secondaryAction;
  final bool dismissible;

  String get dismissalKey => '$noticeId|$stateToken';
}

class WorkspaceAttentionNotice {
  const WorkspaceAttentionNotice({
    required this.noticeId,
    required this.category,
    required this.severity,
    required this.title,
    required this.message,
    required this.primaryAction,
    this.secondaryAction,
    this.dismissible = true,
    this.stateToken,
    this.reminder,
    this.systemNotice,
  });

  factory WorkspaceAttentionNotice.fromReminder(BoardReminderAlert reminder) {
    final primaryAction = reminder.supportsQuickComplete
        ? const WorkspaceNoticeAction(
            kind: WorkspaceNoticeActionKind.reminderDone,
            label: 'Done',
          )
        : const WorkspaceNoticeAction(
            kind: WorkspaceNoticeActionKind.reminderOpen,
            label: 'Open',
          );
    return WorkspaceAttentionNotice(
      noticeId: reminder.reminderId,
      category: WorkspaceAttentionNoticeCategory.reminder,
      severity: reminder.isOverdue
          ? WorkspaceAttentionSeverity.warning
          : WorkspaceAttentionSeverity.neutral,
      title: reminder.title,
      message: reminder.message,
      primaryAction: primaryAction,
      secondaryAction: const WorkspaceNoticeAction(
        kind: WorkspaceNoticeActionKind.reminderSnooze,
        label: 'Snooze',
      ),
      stateToken: reminder.reminderId,
      reminder: reminder,
    );
  }

  factory WorkspaceAttentionNotice.fromSystem(WorkspaceSystemNotice notice) {
    return WorkspaceAttentionNotice(
      noticeId: notice.noticeId,
      category: notice.kind == WorkspaceSystemNoticeKind.permissionDenied
          ? WorkspaceAttentionNoticeCategory.access
          : WorkspaceAttentionNoticeCategory.sync,
      severity: notice.severity,
      title: notice.title,
      message: notice.message,
      primaryAction: notice.primaryAction,
      secondaryAction: notice.secondaryAction,
      dismissible: notice.dismissible,
      stateToken: notice.stateToken,
      systemNotice: notice,
    );
  }

  final String noticeId;
  final WorkspaceAttentionNoticeCategory category;
  final WorkspaceAttentionSeverity severity;
  final String title;
  final String message;
  final WorkspaceNoticeAction primaryAction;
  final WorkspaceNoticeAction? secondaryAction;
  final bool dismissible;
  final String? stateToken;
  final BoardReminderAlert? reminder;
  final WorkspaceSystemNotice? systemNotice;
}

enum WorkspaceFeedbackSeverity {
  info,
  success,
  error,
}

class WorkspaceFeedbackMessage {
  const WorkspaceFeedbackMessage({
    required this.feedbackId,
    required this.message,
    required this.severity,
    required this.createdAt,
    required this.expiresAt,
  });

  final String feedbackId;
  final String message;
  final WorkspaceFeedbackSeverity severity;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
