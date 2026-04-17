import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/column.dart';
import 'package:plandone/src/features/board/domain/models/notification_preferences.dart';
import 'package:plandone/src/features/board/domain/models/board.dart';
import 'package:plandone/src/features/board/domain/models/board_snapshot.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/domain/policies/notification_reminder_policy.dart';

void main() {
  test('buildActiveReminders emits due and start reminders when eligible', () {
    final now = DateTime(2026, 2, 28, 12, 00);
    final items = [
      WorkItem(
        itemId: 'i-due',
        boardId: 'b-1',
        title: 'Due item',
        type: WorkItemType.task,
        columnId: 'c-doing',
        dueAt: now.add(const Duration(minutes: 40)),
        createdAt: now,
        updatedAt: now,
      ),
      WorkItem(
        itemId: 'i-start',
        boardId: 'b-1',
        title: 'Start item',
        type: WorkItemType.task,
        columnId: 'c-doing',
        startAt: now.add(const Duration(minutes: 10)),
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final reminders = NotificationReminderPolicy.buildActiveReminders(
      items: items,
      columnsById: {
        'c-doing': BoardColumn(
          columnId: 'c-doing',
          boardId: 'b-1',
          name: 'Doing',
          orderIndex: 1,
        ),
      },
      preferences: const NotificationPreferences(
        remindOnDueDate: true,
        remindOnStartDate: true,
        dueReminderMinutesBefore: 60,
        startReminderMinutesBefore: 15,
      ),
      now: now,
    );

    expect(reminders.length, 2);
    expect(reminders.any((r) => r.item.itemId == 'i-due'), isTrue);
    expect(reminders.any((r) => r.item.itemId == 'i-start'), isTrue);
  });

  test('buildActiveReminders suppresses done, archived, and snoozed reminders',
      () {
    final now = DateTime(2026, 2, 28, 12, 00);
    final archived = WorkItem(
      itemId: 'archived',
      boardId: 'b-1',
      title: 'Archived',
      type: WorkItemType.action,
      columnId: 'c-doing',
      dueAt: now,
      archived: true,
      createdAt: now,
      updatedAt: now,
    );
    final done = WorkItem(
      itemId: 'done',
      boardId: 'b-1',
      title: 'Done',
      type: WorkItemType.action,
      columnId: 'c-done',
      dueAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final snoozed = WorkItem(
      itemId: 'snoozed',
      boardId: 'b-1',
      title: 'Snoozed',
      type: WorkItemType.action,
      columnId: 'c-doing',
      dueAt: now,
      createdAt: now,
      updatedAt: now,
    );

    final reminderId =
        '${snoozed.itemId}|due|${snoozed.dueAt!.millisecondsSinceEpoch}|60';
    final reminders = NotificationReminderPolicy.buildActiveReminders(
      items: [archived, done, snoozed],
      columnsById: {
        'c-doing': BoardColumn(
          columnId: 'c-doing',
          boardId: 'b-1',
          name: 'Doing',
          orderIndex: 1,
        ),
        'c-done': BoardColumn(
          columnId: 'c-done',
          boardId: 'b-1',
          name: 'Done',
          orderIndex: 2,
          isDoneState: true,
        ),
      },
      preferences: NotificationPreferences(
        remindOnDueDate: true,
        dueReminderMinutesBefore: 60,
        snoozedReminderUntilEpochMillis: {
          reminderId: now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        },
      ),
      now: now,
    );

    expect(reminders, isEmpty);
  });

  test('buildActiveReminders returns empty when muted', () {
    final now = DateTime(2026, 2, 28, 12, 00);
    final item = WorkItem(
      itemId: 'due-item',
      boardId: 'b-1',
      title: 'Due item',
      type: WorkItemType.task,
      columnId: 'c-doing',
      dueAt: now,
      createdAt: now,
      updatedAt: now,
    );

    final reminders = NotificationReminderPolicy.buildActiveReminders(
      items: [item],
      columnsById: {
        'c-doing': BoardColumn(
          columnId: 'c-doing',
          boardId: 'b-1',
          name: 'Doing',
          orderIndex: 1,
        ),
      },
      preferences: NotificationPreferences(
        remindOnDueDate: true,
        mutedUntil: now.add(const Duration(hours: 2)),
      ),
      now: now,
    );

    expect(reminders, isEmpty);
  });

  test('buildScheduledReminders emits future reminder notifications', () {
    final now = DateTime(2026, 2, 28, 12, 00);
    final snapshot = BoardSnapshot(
      board: Board(
        boardId: 'b-1',
        name: 'Work',
        ownerId: 'user-1',
        createdAt: now,
        updatedAt: now,
      ),
      members: const [],
      columns: const [
        BoardColumn(
          columnId: 'c-doing',
          boardId: 'b-1',
          name: 'Doing',
          orderIndex: 1,
        ),
      ],
      items: [
        WorkItem(
          itemId: 'future-due',
          boardId: 'b-1',
          title: 'Prepare notes',
          type: WorkItemType.task,
          columnId: 'c-doing',
          dueAt: now.add(const Duration(minutes: 90)),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    final reminders = NotificationReminderPolicy.buildScheduledReminders(
      snapshots: [snapshot],
      preferences: const NotificationPreferences(
        remindOnDueDate: true,
        dueReminderMinutesBefore: 60,
      ),
      now: now,
    );

    expect(reminders, hasLength(1));
    expect(reminders.first.boardName, 'Work');
    expect(reminders.first.itemTitle, 'Prepare notes');
    expect(reminders.first.scheduledAt, now.add(const Duration(minutes: 30)));
  });

  test('buildScheduledReminders respects snooze and mute timing', () {
    final now = DateTime(2026, 2, 28, 12, 00);
    final dueAt = now.add(const Duration(hours: 2));
    final reminderId = 'future-due|due|${dueAt.millisecondsSinceEpoch}|60';
    final snapshot = BoardSnapshot(
      board: Board(
        boardId: 'b-1',
        name: 'Work',
        ownerId: 'user-1',
        createdAt: now,
        updatedAt: now,
      ),
      members: const [],
      columns: const [
        BoardColumn(
          columnId: 'c-doing',
          boardId: 'b-1',
          name: 'Doing',
          orderIndex: 1,
        ),
      ],
      items: [
        WorkItem(
          itemId: 'future-due',
          boardId: 'b-1',
          title: 'Prepare notes',
          type: WorkItemType.task,
          columnId: 'c-doing',
          dueAt: dueAt,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    final reminders = NotificationReminderPolicy.buildScheduledReminders(
      snapshots: [snapshot],
      preferences: NotificationPreferences(
        remindOnDueDate: true,
        dueReminderMinutesBefore: 60,
        mutedUntil: now.add(const Duration(minutes: 45)),
        snoozedReminderUntilEpochMillis: {
          reminderId:
              now.add(const Duration(minutes: 20)).millisecondsSinceEpoch,
        },
      ),
      now: now,
    );

    expect(reminders, hasLength(1));
    expect(reminders.first.scheduledAt, now.add(const Duration(minutes: 45)));
  });
}
