import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/board_calendar_preferences.dart';
import 'package:plandone/src/features/board/domain/models/board_validation_settings.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/domain/policies/board_calendar_policy.dart';

void main() {
  test('calendar policy creates placements for each selected visible date kind',
      () {
    final item = WorkItem(
      itemId: 'task-1',
      boardId: 'board-1',
      title: 'Prepare release notes',
      type: WorkItemType.task,
      columnId: 'c-todo',
      startAt: DateTime(2026, 3, 19),
      targetEndAt: DateTime(2026, 3, 20),
      dueAt: DateTime(2026, 3, 21),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 10),
    );

    final snapshot = BoardCalendarPolicy.build(
      items: [item],
      settingsByBoardId: const {
        'board-1': BoardValidationSettings(),
      },
      boardNamesById: const {
        'board-1': 'Roadmap',
      },
      visibleKinds: const {
        BoardCalendarMarkerKind.start,
        BoardCalendarMarkerKind.targetEnd,
        BoardCalendarMarkerKind.due,
      },
    );

    expect(snapshot.placements.length, 3);
    expect(
      snapshot.placements.map((entry) => entry.kind).toSet(),
      {
        BoardCalendarMarkerKind.start,
        BoardCalendarMarkerKind.targetEnd,
        BoardCalendarMarkerKind.due,
      },
    );
    expect(snapshot.unscheduledItems, isEmpty);
    expect(snapshot.placements.first.boardName, 'Roadmap');
  });

  test('calendar policy respects hidden date settings and keeps unscheduled',
      () {
    final item = WorkItem(
      itemId: 'task-2',
      boardId: 'board-2',
      title: 'Review launch checklist',
      type: WorkItemType.task,
      columnId: 'c-todo',
      startAt: DateTime(2026, 3, 19),
      dueAt: DateTime(2026, 3, 21),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 10),
    );

    final snapshot = BoardCalendarPolicy.build(
      items: [item],
      settingsByBoardId: const {
        'board-2': BoardValidationSettings(
          showStartDate: false,
          showDueDate: false,
        ),
      },
      boardNamesById: const {
        'board-2': 'Execution',
      },
      visibleKinds: const {
        BoardCalendarMarkerKind.start,
        BoardCalendarMarkerKind.due,
      },
    );

    expect(snapshot.placements, isEmpty);
    expect(snapshot.unscheduledItems, hasLength(1));
    expect(snapshot.unscheduledItems.single.boardName, 'Execution');
  });
}
