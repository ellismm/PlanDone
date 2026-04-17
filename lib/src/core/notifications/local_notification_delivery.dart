import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/board/domain/models/board_scheduled_reminder.dart';

final localNotificationDeliveryProvider =
    Provider<LocalNotificationDelivery>((ref) {
  return const LocalNotificationDelivery();
});

class LocalNotificationDelivery {
  const LocalNotificationDelivery();

  static const MethodChannel _channel =
      MethodChannel('plandone/local_notifications');

  Future<bool> ensurePermissionRequested() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final granted =
        await _channel.invokeMethod<bool>('requestPermission') ?? false;
    return granted;
  }

  Future<void> syncScheduledReminders(
    List<BoardScheduledReminder> reminders,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>(
      'replaceSchedule',
      <String, Object?>{
        'schedules': reminders.map(_serializeReminder).toList(),
      },
    );
  }

  Future<List<PendingReminderNotificationAction>> drainPendingActions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const <PendingReminderNotificationAction>[];
    }
    final raw =
        await _channel.invokeMethod<List<Object?>>('drainPendingActions') ??
            const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(PendingReminderNotificationAction.fromPlatformMap)
        .toList();
  }

  Map<String, Object?> _serializeReminder(BoardScheduledReminder reminder) {
    return <String, Object?>{
      'reminderId': reminder.reminderId,
      'boardId': reminder.boardId,
      'boardName': reminder.boardName,
      'itemId': reminder.itemId,
      'itemTitle': reminder.itemTitle,
      'kind': reminder.kind.name,
      'title': '${reminder.boardName} • ${reminder.title}',
      'body': reminder.message,
      'scheduledAtEpochMillis': reminder.scheduledAt.millisecondsSinceEpoch,
      'referenceAtEpochMillis': reminder.referenceAt.millisecondsSinceEpoch,
      'supportsQuickComplete': reminder.supportsQuickComplete,
    };
  }
}

enum PendingReminderNotificationActionKind {
  done,
  snooze,
}

class PendingReminderNotificationAction {
  const PendingReminderNotificationAction({
    required this.kind,
    required this.reminderId,
    required this.boardId,
    required this.itemId,
  });

  factory PendingReminderNotificationAction.fromPlatformMap(
    Map<Object?, Object?> map,
  ) {
    final rawKind = map['kind']?.toString().trim() ?? 'snooze';
    final kind = PendingReminderNotificationActionKind.values.firstWhere(
      (candidate) => candidate.name == rawKind,
      orElse: () => PendingReminderNotificationActionKind.snooze,
    );
    return PendingReminderNotificationAction(
      kind: kind,
      reminderId: map['reminderId']?.toString() ?? '',
      boardId: map['boardId']?.toString() ?? '',
      itemId: map['itemId']?.toString() ?? '',
    );
  }

  final PendingReminderNotificationActionKind kind;
  final String reminderId;
  final String boardId;
  final String itemId;
}
