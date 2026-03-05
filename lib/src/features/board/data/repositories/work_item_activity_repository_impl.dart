import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/models/work_item_activity_event.dart';
import '../../domain/repositories/work_item_activity_repository.dart';
import '../local/drift/board_database.dart';

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
}

class DriftWorkItemActivityRepository implements WorkItemActivityRepository {
  DriftWorkItemActivityRepository({
    required BoardDatabase database,
    this.maxEventsPerItem = 200,
  }) : _database = database;

  final BoardDatabase _database;
  final int maxEventsPerItem;

  Future<void> _ensureTable() async {
    await _database.customStatement(
      'CREATE TABLE IF NOT EXISTS work_item_activity_events ('
      'event_id TEXT PRIMARY KEY NOT NULL, '
      'board_id TEXT NOT NULL, '
      'item_id TEXT NOT NULL, '
      'event_type TEXT NOT NULL, '
      'actor_user_id TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'payload_json TEXT NOT NULL'
      ')',
    );

    await _database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_activity_item_created '
      'ON work_item_activity_events(board_id, item_id, created_at DESC)',
    );
  }

  @override
  Future<void> append(WorkItemActivityEvent event) async {
    await _ensureTable();

    await _database.customStatement(
      'INSERT OR REPLACE INTO work_item_activity_events('
      'event_id, board_id, item_id, event_type, actor_user_id, created_at, payload_json'
      ') VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        event.eventId,
        event.boardId,
        event.itemId,
        event.type.name,
        event.actorUserId,
        event.createdAt.millisecondsSinceEpoch,
        jsonEncode(event.payload),
      ],
    );

    await _database.customStatement(
      'DELETE FROM work_item_activity_events '
      'WHERE board_id = ? AND item_id = ? AND event_id NOT IN ('
      '  SELECT event_id FROM work_item_activity_events '
      '  WHERE board_id = ? AND item_id = ? '
      '  ORDER BY created_at DESC, event_id DESC '
      '  LIMIT ?'
      ')',
      [
        event.boardId,
        event.itemId,
        event.boardId,
        event.itemId,
        maxEventsPerItem,
      ],
    );
  }

  @override
  Future<List<WorkItemActivityEvent>> listForItem({
    required String boardId,
    required String itemId,
    int limit = 100,
  }) async {
    await _ensureTable();

    final rows = await _database.customSelect(
      'SELECT event_id, board_id, item_id, event_type, actor_user_id, created_at, payload_json '
      'FROM work_item_activity_events '
      'WHERE board_id = ? AND item_id = ? '
      'ORDER BY created_at DESC, event_id DESC '
      'LIMIT ?',
      variables: [
        drift.Variable(boardId),
        drift.Variable(itemId),
        drift.Variable(limit),
      ],
    ).get();

    return rows.map((row) {
      final data = row.data;
      final typeName = (data['event_type'] as String?) ?? 'updated';
      final type = WorkItemActivityType.values.firstWhere(
        (entry) => entry.name == typeName,
        orElse: () => WorkItemActivityType.updated,
      );
      final payloadJson = (data['payload_json'] as String?) ?? '{}';
      final payload = (jsonDecode(payloadJson) as Map?)
              ?.map((key, value) => MapEntry('$key', value))
              .cast<String, Object?>() ??
          const <String, Object?>{};

      return WorkItemActivityEvent(
        eventId: (data['event_id'] as String?) ??
            'missing-${DateTime.now().microsecondsSinceEpoch}',
        boardId: (data['board_id'] as String?) ?? boardId,
        itemId: (data['item_id'] as String?) ?? itemId,
        type: type,
        actorUserId: (data['actor_user_id'] as String?) ?? 'unknown',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (data['created_at'] as int?) ?? 0,
        ),
        payload: payload,
      );
    }).toList(growable: false);
  }
}
