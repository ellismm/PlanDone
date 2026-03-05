import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/data/local/drift/board_database.dart';
import 'package:plandone/src/features/board/data/repositories/notification_preferences_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/notification_preferences.dart';

void main() {
  test('in-memory notification preferences are user-scoped', () async {
    final userA = InMemoryNotificationPreferencesRepository(userId: 'user-a');
    final userB = InMemoryNotificationPreferencesRepository(userId: 'user-b');

    await userA.save(const NotificationPreferences(enabled: false));

    final a = await userA.load();
    final b = await userB.load();

    expect(a.enabled, isFalse);
    expect(b.enabled, isTrue);
  });

  test('drift notification preferences persist round-trip', () async {
    final db = BoardDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final repo = DriftNotificationPreferencesRepository(
      database: db,
      userId: 'dev-user',
    );

    await repo.save(
      NotificationPreferences(
        enabled: true,
        remindOnStartDate: true,
        remindOnDueDate: false,
        startReminderMinutesBefore: 30,
        dueReminderMinutesBefore: 120,
        defaultSnoozeMinutes: 15,
        mutedUntil: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        snoozedReminderUntilEpochMillis: const {'abc': 1700000005000},
      ),
    );

    final loaded = await repo.load();

    expect(loaded.enabled, isTrue);
    expect(loaded.remindOnStartDate, isTrue);
    expect(loaded.remindOnDueDate, isFalse);
    expect(loaded.startReminderMinutesBefore, 30);
    expect(loaded.dueReminderMinutesBefore, 120);
    expect(loaded.defaultSnoozeMinutes, 15);
    expect(loaded.mutedUntil?.millisecondsSinceEpoch, 1700000000000);
    expect(loaded.snoozedReminderUntilEpochMillis['abc'], 1700000005000);
  });
}
