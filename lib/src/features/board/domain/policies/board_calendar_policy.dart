import '../models/board_calendar.dart';
import '../models/board_calendar_preferences.dart';
import '../models/board_validation_settings.dart';
import '../models/work_item.dart';

class BoardCalendarPolicy {
  const BoardCalendarPolicy._();

  static BoardCalendarSnapshot build({
    required List<WorkItem> items,
    required Map<String, BoardValidationSettings> settingsByBoardId,
    required Map<String, String> boardNamesById,
    required Set<BoardCalendarMarkerKind> visibleKinds,
  }) {
    final placements = <BoardCalendarPlacement>[];
    final unscheduledItems = <BoardCalendarUnscheduledItem>[];

    for (final item in items) {
      final settings =
          settingsByBoardId[item.boardId] ?? const BoardValidationSettings();
      final boardName = boardNamesById[item.boardId] ?? 'Board';

      var itemPlacementCount = 0;

      void addPlacement(
        BoardCalendarMarkerKind kind,
        DateTime? rawDate,
      ) {
        if (rawDate == null || !visibleKinds.contains(kind)) return;
        if (!_isKindEnabledForBoard(kind, settings)) return;
        placements.add(
          BoardCalendarPlacement(
            item: item,
            date: dateOnly(rawDate.toLocal()),
            kind: kind,
            boardName: boardName,
          ),
        );
        itemPlacementCount += 1;
      }

      addPlacement(BoardCalendarMarkerKind.start, item.startAt);
      addPlacement(BoardCalendarMarkerKind.targetEnd, item.targetEndAt);
      addPlacement(BoardCalendarMarkerKind.due, item.dueAt);

      if (itemPlacementCount == 0) {
        unscheduledItems.add(
          BoardCalendarUnscheduledItem(item: item, boardName: boardName),
        );
      }
    }

    placements.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final byKind = _kindRank(a.kind).compareTo(_kindRank(b.kind));
      if (byKind != 0) return byKind;
      final bySortOrder = a.item.sortOrder.compareTo(b.item.sortOrder);
      if (bySortOrder != 0) return bySortOrder;
      final byBoard = a.item.boardId.compareTo(b.item.boardId);
      if (byBoard != 0) return byBoard;
      return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
    });

    unscheduledItems.sort((a, b) {
      final byBoard = a.item.boardId.compareTo(b.item.boardId);
      if (byBoard != 0) return byBoard;
      final bySortOrder = a.item.sortOrder.compareTo(b.item.sortOrder);
      if (bySortOrder != 0) return bySortOrder;
      return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
    });

    return BoardCalendarSnapshot(
      placements: placements,
      unscheduledItems: unscheduledItems,
    );
  }

  static DateTime dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static bool _isKindEnabledForBoard(
    BoardCalendarMarkerKind kind,
    BoardValidationSettings settings,
  ) {
    return switch (kind) {
      BoardCalendarMarkerKind.start => settings.showStartDate,
      BoardCalendarMarkerKind.targetEnd => settings.showTargetEndDate,
      BoardCalendarMarkerKind.due => settings.showDueDate,
    };
  }

  static int _kindRank(BoardCalendarMarkerKind kind) {
    return switch (kind) {
      BoardCalendarMarkerKind.start => 0,
      BoardCalendarMarkerKind.targetEnd => 1,
      BoardCalendarMarkerKind.due => 2,
    };
  }
}
