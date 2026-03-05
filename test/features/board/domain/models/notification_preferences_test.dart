import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/notification_preferences.dart';

void main() {
  test('notification preferences round-trip map serialization', () {
    final now = DateTime.now();
    final original = NotificationPreferences(
      enabled: true,
      remindOnStartDate: true,
      remindOnDueDate: true,
      startReminderMinutesBefore: 10,
      dueReminderMinutesBefore: 45,
      defaultSnoozeMinutes: 30,
      mutedUntil: now,
      snoozedReminderUntilEpochMillis: const {'r-1': 1700000000000},
    );

    final restored = NotificationPreferences.fromMap(original.toMap());

    expect(restored.enabled, isTrue);
    expect(restored.remindOnStartDate, isTrue);
    expect(restored.remindOnDueDate, isTrue);
    expect(restored.startReminderMinutesBefore, 10);
    expect(restored.dueReminderMinutesBefore, 45);
    expect(restored.defaultSnoozeMinutes, 30);
    expect(restored.mutedUntil?.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch);
    expect(restored.snoozedReminderUntilEpochMillis['r-1'], 1700000000000);
  });

  test('notification preferences default safely from null map', () {
    final restored = NotificationPreferences.fromMap(null);
    expect(restored.enabled, isTrue);
    expect(restored.remindOnDueDate, isTrue);
    expect(restored.remindOnStartDate, isFalse);
    expect(restored.defaultSnoozeMinutes, 60);
    expect(restored.mutedUntil, isNull);
    expect(restored.snoozedReminderUntilEpochMillis, isEmpty);
  });
}
