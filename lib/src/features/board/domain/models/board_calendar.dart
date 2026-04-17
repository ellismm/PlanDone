import 'board_calendar_preferences.dart';
import 'work_item.dart';

class BoardCalendarPlacement {
  const BoardCalendarPlacement({
    required this.item,
    required this.date,
    required this.kind,
    required this.boardName,
  });

  final WorkItem item;
  final DateTime date;
  final BoardCalendarMarkerKind kind;
  final String boardName;
}

class BoardCalendarUnscheduledItem {
  const BoardCalendarUnscheduledItem({
    required this.item,
    required this.boardName,
  });

  final WorkItem item;
  final String boardName;
}

class BoardCalendarSnapshot {
  const BoardCalendarSnapshot({
    required this.placements,
    required this.unscheduledItems,
  });

  final List<BoardCalendarPlacement> placements;
  final List<BoardCalendarUnscheduledItem> unscheduledItems;
}
