import '../models/autofill_settings.dart';
import '../models/board_snapshot.dart';
import '../models/column.dart';
import '../models/work_item.dart';
import '../models/work_item_type.dart';

class AutofillSuggestionDraft {
  const AutofillSuggestionDraft({
    this.type,
    this.columnId,
    this.parentId,
    this.tags = const <String>[],
    this.estimatedEffortMinutes,
    this.boardId,
  });

  final WorkItemType? type;
  final String? columnId;
  final String? parentId;
  final List<String> tags;
  final int? estimatedEffortMinutes;
  final String? boardId;
}

class AutofillSuggestionPolicy {
  static const int _historyLimit = 40;

  static AutofillSuggestionDraft forCreateItem({
    required BoardSnapshot snapshot,
    required AutofillSettings settings,
    WorkItemType? selectedType,
  }) {
    if (!settings.enabled) return const AutofillSuggestionDraft();

    final recent = snapshot.items
        .where((item) => !item.archived && !item.isInbox)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final history = recent.take(_historyLimit).toList();

    final suggestedType = settings.suggestType
        ? (selectedType ?? _mostFrequentType(history) ?? WorkItemType.action)
        : selectedType;

    final effectiveType = selectedType ?? suggestedType;
    final typeScoped = effectiveType == null
        ? history
        : history.where((item) => item.type == effectiveType).toList();

    final suggestedColumnId = settings.suggestColumn
        ? _mostFrequentColumn(
            typeScoped,
            fallbackColumns: snapshot.columns,
          )
        : null;

    final suggestedParentId = settings.suggestParent && effectiveType != null
        ? _bestParentId(snapshot.items, typeScoped, effectiveType)
        : null;

    final suggestedTags = settings.suggestTags
        ? _topTags(typeScoped, maxCount: 3)
        : const <String>[];

    final suggestedEstimate =
        settings.suggestEstimate ? _medianEstimateMinutes(typeScoped) : null;

    return AutofillSuggestionDraft(
      type: suggestedType,
      columnId: suggestedColumnId,
      parentId: suggestedParentId,
      tags: suggestedTags,
      estimatedEffortMinutes: suggestedEstimate,
    );
  }

  static String? suggestBoardForInboxTriage({
    required WorkItem inboxItem,
    required List<BoardSnapshot> boardSnapshots,
    required AutofillSettings settings,
    required String fallbackBoardId,
  }) {
    if (!settings.enabled || !settings.suggestBoard) return fallbackBoardId;
    if (boardSnapshots.isEmpty) return fallbackBoardId;

    final inboxTags = inboxItem.tags.map((tag) => tag.toLowerCase()).toSet();
    final titleTokens = inboxItem.title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3)
        .toSet();

    String? bestBoardId;
    var bestScore = -1;

    for (final snapshot in boardSnapshots) {
      var score = 0;
      final items = snapshot.items.where((item) => !item.archived).toList();
      for (final item in items.take(_historyLimit)) {
        final itemTags = item.tags.map((tag) => tag.toLowerCase()).toSet();
        final tagOverlap = itemTags.intersection(inboxTags).length;
        score += tagOverlap * 3;

        final itemTitle = item.title.toLowerCase();
        final tokenMatches = titleTokens.where(itemTitle.contains).length;
        score += tokenMatches;
      }

      if (score > bestScore) {
        bestScore = score;
        bestBoardId = snapshot.board.boardId;
      }
    }

    return bestBoardId ?? fallbackBoardId;
  }

  static WorkItemType? _mostFrequentType(List<WorkItem> items) {
    if (items.isEmpty) return null;
    final counts = <WorkItemType, int>{};
    for (final item in items) {
      counts[item.type] = (counts[item.type] ?? 0) + 1;
    }

    WorkItemType? best;
    var bestCount = -1;
    for (final type in WorkItemType.values) {
      final count = counts[type] ?? 0;
      if (count > bestCount) {
        bestCount = count;
        best = type;
      }
    }
    return best;
  }

  static String? _mostFrequentColumn(
    List<WorkItem> items, {
    required List<BoardColumn> fallbackColumns,
  }) {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.columnId] = (counts[item.columnId] ?? 0) + 1;
    }

    String? bestColumnId;
    var bestCount = -1;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        bestColumnId = entry.key;
      }
    }

    if (bestColumnId != null) return bestColumnId;

    final orderedColumns = [...fallbackColumns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final preferred = orderedColumns
        .where((column) => !column.isDoneState && !column.isCancelledState)
        .cast<BoardColumn?>()
        .firstWhere((_) => true, orElse: () => null);
    return preferred?.columnId ??
        (orderedColumns.isEmpty ? null : orderedColumns.first.columnId);
  }

  static String? _bestParentId(
    List<WorkItem> allItems,
    List<WorkItem> recent,
    WorkItemType childType,
  ) {
    final rank = _typeRank(childType);
    if (rank <= 0) return null;

    final candidates = allItems
        .where((item) => _typeRank(item.type) < rank && !item.archived)
        .toList();
    if (candidates.isEmpty) return null;

    final counts = <String, int>{};
    for (final item in recent) {
      final parentId = item.parentId;
      if (parentId == null) continue;
      final parent = candidates
          .where((candidate) => candidate.itemId == parentId)
          .cast<WorkItem?>()
          .firstWhere((_) => true, orElse: () => null);
      if (parent == null) continue;
      counts[parentId] = (counts[parentId] ?? 0) + 1;
    }

    String? bestId;
    var bestCount = -1;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        bestId = entry.key;
      }
    }

    if (bestId != null) return bestId;

    candidates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates.first.itemId;
  }

  static List<String> _topTags(List<WorkItem> items, {required int maxCount}) {
    if (items.isEmpty) return const <String>[];
    final counts = <String, int>{};
    for (final item in items) {
      for (final tag in item.tags) {
        final normalized = tag.trim();
        if (normalized.isEmpty) continue;
        counts[normalized] = (counts[normalized] ?? 0) + 1;
      }
    }

    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });

    return ranked.take(maxCount).map((entry) => entry.key).toList();
  }

  static int? _medianEstimateMinutes(List<WorkItem> items) {
    final estimates = items
        .map((item) => item.estimatedEffortMinutes)
        .whereType<int>()
        .where((value) => value > 0)
        .toList()
      ..sort();
    if (estimates.isEmpty) return null;
    final mid = estimates.length ~/ 2;
    if (estimates.length.isOdd) return estimates[mid];
    return ((estimates[mid - 1] + estimates[mid]) / 2).round();
  }

  static int _typeRank(WorkItemType type) {
    return switch (type) {
      WorkItemType.goal => 0,
      WorkItemType.project => 1,
      WorkItemType.task => 2,
      WorkItemType.action => 3,
    };
  }
}
