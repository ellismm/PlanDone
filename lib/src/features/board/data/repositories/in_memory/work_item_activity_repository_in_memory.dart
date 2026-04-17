import '../../../domain/models/work_item_activity_event.dart';
import '../../../domain/repositories/work_item_activity_repository.dart';

class InMemoryWorkItemActivityRepository implements WorkItemActivityRepository {
  InMemoryWorkItemActivityRepository({this.maxEventsPerItem = 200});

  final int maxEventsPerItem;
  final Map<String, List<WorkItemActivityEvent>> _eventsByItemKey = {};

  String _key(String boardId, String itemId) => '$boardId::$itemId';

  @override
  Future<void> append(WorkItemActivityEvent event) async {
    final key = _key(event.boardId, event.itemId);
    final events = _eventsByItemKey.putIfAbsent(key, () => []);
    events.add(event);
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (events.length > maxEventsPerItem) {
      events.removeRange(maxEventsPerItem, events.length);
    }
  }

  @override
  Future<List<WorkItemActivityEvent>> listForItem({
    required String boardId,
    required String itemId,
    int limit = 100,
  }) async {
    final key = _key(boardId, itemId);
    final events = _eventsByItemKey[key] ?? const <WorkItemActivityEvent>[];
    if (events.length <= limit) return [...events];
    return events.take(limit).toList(growable: false);
  }

  @override
  Future<List<WorkItemActivityEvent>> listForBoard({
    required String boardId,
    DateTime? since,
    int limit = 500,
  }) async {
    final boardPrefix = '$boardId::';
    final events = _eventsByItemKey.entries
        .where((entry) => entry.key.startsWith(boardPrefix))
        .expand((entry) => entry.value)
        .where((event) => since == null || !event.createdAt.isBefore(since))
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (events.length <= limit) return events;
    return events.take(limit).toList(growable: false);
  }
}
