import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../features/board/data/local/drift/board_database.dart';
import 'outbox_operation.dart';
import 'outbox_queue.dart';

class DriftOutboxQueue implements OutboxQueue {
  DriftOutboxQueue(this._db);

  final BoardDatabase _db;
  bool _tableReady = false;

  Future<void> _ensureTable() async {
    if (_tableReady) return;
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS outbox_operations ('
      'id TEXT PRIMARY KEY NOT NULL, '
      'type TEXT NOT NULL, '
      'entity TEXT NOT NULL, '
      'entity_id TEXT NOT NULL, '
      'payload_json TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'attempt_count INTEGER NOT NULL DEFAULT 0, '
      'last_error TEXT, '
      'next_attempt_at INTEGER, '
      'last_attempt_at INTEGER'
      ')',
    );

    await _safeAddColumn(
        'ALTER TABLE outbox_operations ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0');
    await _safeAddColumn(
        'ALTER TABLE outbox_operations ADD COLUMN last_error TEXT');
    await _safeAddColumn(
        'ALTER TABLE outbox_operations ADD COLUMN next_attempt_at INTEGER');
    await _safeAddColumn(
        'ALTER TABLE outbox_operations ADD COLUMN last_attempt_at INTEGER');
    _tableReady = true;
  }

  Future<void> _safeAddColumn(String statement) async {
    try {
      await _db.customStatement(statement);
    } catch (_) {
      // Column likely already exists.
    }
  }

  @override
  Future<void> enqueue(OutboxOperation operation) async {
    await _ensureTable();
    await _db.customStatement(
      'INSERT OR REPLACE INTO outbox_operations('
      'id, type, entity, entity_id, payload_json, created_at, attempt_count, last_error, next_attempt_at, last_attempt_at'
      ') VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        operation.id,
        operation.type.name,
        operation.entity,
        operation.entityId,
        jsonEncode(operation.payload),
        operation.createdAt.millisecondsSinceEpoch,
        operation.attemptCount,
        operation.lastError,
        operation.nextAttemptAt?.millisecondsSinceEpoch,
        operation.lastAttemptAt?.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> update(OutboxOperation operation) async {
    await enqueue(operation);
  }

  @override
  Future<List<OutboxOperation>> listPending() async {
    await _ensureTable();
    final rows = await _db.customSelect(
      'SELECT id, type, entity, entity_id, payload_json, created_at, attempt_count, last_error, next_attempt_at '
      ', last_attempt_at '
      'FROM outbox_operations ORDER BY created_at ASC',
      readsFrom: const {},
    ).get();

    return rows.map((row) {
      final data = row.data;
      final typeName = data['type'] as String;
      final payloadRaw = data['payload_json'] as String;
      return OutboxOperation(
        id: data['id'] as String,
        type: OutboxOperationType.values.firstWhere(
          (t) => t.name == typeName,
          orElse: () => OutboxOperationType.update,
        ),
        entity: data['entity'] as String,
        entityId: data['entity_id'] as String,
        payload: (jsonDecode(payloadRaw) as Map<String, dynamic>)
            .cast<String, Object?>(),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int),
        attemptCount: (data['attempt_count'] as int?) ?? 0,
        lastError: data['last_error'] as String?,
        nextAttemptAt: data['next_attempt_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                data['next_attempt_at'] as int),
        lastAttemptAt: data['last_attempt_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                data['last_attempt_at'] as int),
      );
    }).toList();
  }

  @override
  Future<void> markProcessed(String operationId) async {
    await _ensureTable();
    await _db.customStatement(
      'DELETE FROM outbox_operations WHERE id = ?',
      [operationId],
    );
  }
}
