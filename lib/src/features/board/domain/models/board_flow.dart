import 'board.dart';
import 'board_validation_settings.dart';
import 'column.dart';
import 'work_item.dart';
import 'work_item_type.dart';

enum BoardFlowUrgency {
  overdue,
  today,
  reminder,
  upcoming,
  anytime,
}

const boardFlowMinMotionSpeed = 0.5;
const boardFlowDefaultMotionSpeed = 1.0;
const boardFlowMaxMotionSpeed = 2.0;

String boardFlowDayKey(DateTime dateTime) {
  final normalized = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  return '${normalized.year}-$month-$day';
}

class BoardFlowSuppressionEntry {
  const BoardFlowSuppressionEntry({
    required this.untilEpochMillis,
    required this.stateToken,
  });

  final int untilEpochMillis;
  final String stateToken;

  DateTime get until => DateTime.fromMillisecondsSinceEpoch(untilEpochMillis);

  Map<String, Object?> toMap() {
    return {
      'untilEpochMillis': untilEpochMillis,
      'stateToken': stateToken,
    };
  }

  static BoardFlowSuppressionEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final until = raw['untilEpochMillis'];
    final token = raw['stateToken'];
    if (until is! int || token is! String || token.trim().isEmpty) {
      return null;
    }
    return BoardFlowSuppressionEntry(
      untilEpochMillis: until,
      stateToken: token,
    );
  }
}

class BoardFlowReviewedEntry {
  const BoardFlowReviewedEntry({
    required this.dayKey,
    required this.stateToken,
  });

  final String dayKey;
  final String stateToken;

  Map<String, Object?> toMap() {
    return {
      'dayKey': dayKey,
      'stateToken': stateToken,
    };
  }

  static BoardFlowReviewedEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final dayKey = raw['dayKey'];
    final token = raw['stateToken'];
    if (dayKey is! String ||
        dayKey.trim().isEmpty ||
        token is! String ||
        token.trim().isEmpty) {
      return null;
    }
    return BoardFlowReviewedEntry(
      dayKey: dayKey,
      stateToken: token,
    );
  }
}

class BoardFlowPreferences {
  const BoardFlowPreferences({
    this.visibleTypes = const <WorkItemType>{WorkItemType.action},
    this.motionEnabled = true,
    this.motionSpeed = boardFlowDefaultMotionSpeed,
    this.suppressedItems = const <String, BoardFlowSuppressionEntry>{},
    this.reviewedItems = const <String, BoardFlowReviewedEntry>{},
  });

  final Set<WorkItemType> visibleTypes;
  final bool motionEnabled;
  final double motionSpeed;
  final Map<String, BoardFlowSuppressionEntry> suppressedItems;
  final Map<String, BoardFlowReviewedEntry> reviewedItems;

  BoardFlowPreferences copyWith({
    Set<WorkItemType>? visibleTypes,
    bool? motionEnabled,
    double? motionSpeed,
    Map<String, BoardFlowSuppressionEntry>? suppressedItems,
    Map<String, BoardFlowReviewedEntry>? reviewedItems,
  }) {
    return BoardFlowPreferences(
      visibleTypes: visibleTypes ?? this.visibleTypes,
      motionEnabled: motionEnabled ?? this.motionEnabled,
      motionSpeed: motionSpeed ?? this.motionSpeed,
      suppressedItems: suppressedItems ?? this.suppressedItems,
      reviewedItems: reviewedItems ?? this.reviewedItems,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'visibleTypes': visibleTypes.map((type) => type.name).toList(),
      'motionEnabled': motionEnabled,
      'motionSpeed': motionSpeed,
      'suppressedItems': {
        for (final entry in suppressedItems.entries)
          entry.key: entry.value.toMap(),
      },
      'reviewedItems': {
        for (final entry in reviewedItems.entries)
          entry.key: entry.value.toMap(),
      },
    };
  }

  static BoardFlowPreferences fromMap(Map<String, Object?>? map) {
    if (map == null) return const BoardFlowPreferences();

    final rawVisibleTypes = (map['visibleTypes'] as List?)
            ?.whereType<String>()
            .map(
              (name) =>
                  WorkItemType.values.where((entry) => entry.name == name),
            )
            .where((matches) => matches.isNotEmpty)
            .map((matches) => matches.first)
            .where(
              (type) =>
                  type == WorkItemType.task || type == WorkItemType.action,
            )
            .toSet() ??
        const <WorkItemType>{WorkItemType.action};

    final normalizedVisibleTypes = rawVisibleTypes.isEmpty
        ? const <WorkItemType>{WorkItemType.action}
        : rawVisibleTypes;
    final rawMotionSpeed = map['motionSpeed'];
    final motionSpeed = switch (rawMotionSpeed) {
      final num value => value
          .toDouble()
          .clamp(boardFlowMinMotionSpeed, boardFlowMaxMotionSpeed),
      _ => boardFlowDefaultMotionSpeed,
    };

    final rawSuppressedItems = map['suppressedItems'];
    final suppressedItems = <String, BoardFlowSuppressionEntry>{};
    if (rawSuppressedItems is Map) {
      for (final entry in rawSuppressedItems.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        final parsed = BoardFlowSuppressionEntry.fromMap(entry.value);
        if (parsed == null) continue;
        suppressedItems[key] = parsed;
      }
    }

    final rawReviewedItems = map['reviewedItems'];
    final reviewedItems = <String, BoardFlowReviewedEntry>{};
    if (rawReviewedItems is Map) {
      for (final entry in rawReviewedItems.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        final parsed = BoardFlowReviewedEntry.fromMap(entry.value);
        if (parsed == null) continue;
        reviewedItems[key] = parsed;
      }
    }

    return BoardFlowPreferences(
      visibleTypes: normalizedVisibleTypes,
      motionEnabled: map['motionEnabled'] != false,
      motionSpeed: motionSpeed,
      suppressedItems: suppressedItems,
      reviewedItems: reviewedItems,
    );
  }
}

class BoardFlowCandidate {
  const BoardFlowCandidate({
    required this.item,
    required this.board,
    required this.boardName,
    required this.parentTitle,
    required this.column,
    required this.message,
    required this.urgency,
    required this.sortKey,
    required this.stateToken,
    required this.boardColumns,
    required this.boardItems,
    required this.validationSettings,
    required this.reminderTriggered,
  });

  final WorkItem item;
  final Board board;
  final String boardName;
  final String? parentTitle;
  final BoardColumn column;
  final String message;
  final BoardFlowUrgency urgency;
  final int sortKey;
  final String stateToken;
  final List<BoardColumn> boardColumns;
  final List<WorkItem> boardItems;
  final BoardValidationSettings validationSettings;
  final bool reminderTriggered;

  String get itemKey => '${item.boardId}::${item.itemId}';
}

class BoardFlowSnapshot {
  const BoardFlowSnapshot({
    required this.candidates,
    required this.multiBoardScope,
    required this.accentColorValuesByItemKey,
    required this.boardNamesById,
    required this.remainingTodayCount,
    required this.reviewedTodayCount,
  });

  final List<BoardFlowCandidate> candidates;
  final bool multiBoardScope;
  final Map<String, int> accentColorValuesByItemKey;
  final Map<String, String> boardNamesById;
  final int remainingTodayCount;
  final int reviewedTodayCount;

  int get totalTodayCount => remainingTodayCount + reviewedTodayCount;
}
