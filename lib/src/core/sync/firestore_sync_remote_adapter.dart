import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../outbox/outbox_operation.dart';
import 'sync_remote_adapter.dart';

class FirestoreSyncRemoteAdapter implements SyncRemoteAdapter {
  FirestoreSyncRemoteAdapter({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _boards =>
      _firestore.collection('boards');

  CollectionReference<Map<String, dynamic>> _members(String boardId) =>
      _boards.doc(boardId).collection('members');

  CollectionReference<Map<String, dynamic>> _columns(String boardId) =>
      _boards.doc(boardId).collection('columns');

  CollectionReference<Map<String, dynamic>> _workItems(String boardId) =>
      _boards.doc(boardId).collection('workItems');

  DocumentReference<Map<String, dynamic>> _opMarker(
    String boardId,
    String operationId,
  ) =>
      _boards.doc(boardId).collection('_appliedOps').doc(operationId);

  String _requiredString(
    Map<String, Object?> payload,
    String key,
  ) {
    final value = payload[key];
    if (value is String && value.isNotEmpty) return value;
    throw SyncRemoteException('Missing required payload field "$key"');
  }

  DateTime? _parseIsoDate(Map<String, Object?> payload, String key) {
    final raw = payload[key];
    if (raw == null) return null;
    if (raw is! String) {
      throw SyncRemoteException('Payload field "$key" must be ISO-8601 string');
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  int _updatedAtMicros(Map<String, Object?> payload,
      {required DateTime fallback}) {
    final parsed = _parseIsoDate(payload, 'updatedAt');
    return (parsed ?? fallback.toUtc()).microsecondsSinceEpoch;
  }

  Future<void> _withIdempotency({
    required String boardId,
    required OutboxOperation operation,
    required Future<void> Function(Transaction tx) apply,
  }) async {
    final marker = _opMarker(boardId, operation.id);
    await _firestore.runTransaction((tx) async {
      final markerSnap = await tx.get(marker);
      if (markerSnap.exists) return;
      await apply(tx);
      tx.set(marker, {
        'operationId': operation.id,
        'entity': operation.entity,
        'entityId': operation.entityId,
        'type': operation.type.name,
        'appliedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _applyBoardOp(OutboxOperation op) async {
    final boardId = _requiredString(op.payload, 'boardId');
    final doc = _boards.doc(boardId);

    await _withIdempotency(
      boardId: boardId,
      operation: op,
      apply: (tx) async {
        if (op.type == OutboxOperationType.delete) {
          tx.delete(doc);
          return;
        }

        final updatedAtMicros =
            _updatedAtMicros(op.payload, fallback: op.createdAt);
        final ownerId = _requiredString(op.payload, 'ownerId');
        final data = <String, Object?>{
          'boardId': boardId,
          'name': _requiredString(op.payload, 'name'),
          'ownerId': ownerId,
          'createdAt':
              op.payload['createdAt'] ?? op.createdAt.toUtc().toIso8601String(),
          'updatedAt':
              op.payload['updatedAt'] ?? op.createdAt.toUtc().toIso8601String(),
          'updatedAtMicros': updatedAtMicros,
          'lastWriterOpId': op.id,
          'validationSettings': (op.payload['validationSettings'] as Map?)
                  ?.cast<String, Object?>() ??
              const <String, Object?>{},
          'workflowSettings': (op.payload['workflowSettings'] as Map?)
                  ?.cast<String, Object?>() ??
              const <String, Object?>{},
        };

        final current = await tx.get(doc);
        final ownerMemberDoc = _members(boardId).doc(ownerId);
        final ownerMemberSnap = await tx.get(ownerMemberDoc);

        if (current.exists) {
          final currentMicros =
              (current.data()?['updatedAtMicros'] as int?) ?? 0;
          if (currentMicros > updatedAtMicros) {
            return;
          }
        }

        tx.set(doc, data, SetOptions(merge: true));
        if (!ownerMemberSnap.exists) {
          tx.set(
              ownerMemberDoc,
              {
                'boardId': boardId,
                'userId': ownerId,
                'role': 'owner',
                'joinedAt': op.payload['createdAt'] ??
                    op.createdAt.toUtc().toIso8601String(),
                'joinedAtEpochMillis':
                    op.createdAt.toUtc().millisecondsSinceEpoch,
                'updatedAtMicros': updatedAtMicros,
                'lastWriterOpId': op.id,
              },
              SetOptions(merge: true));
        }
      },
    );
  }

  Future<void> _applyMemberOp(OutboxOperation op) async {
    final boardId = _requiredString(op.payload, 'boardId');
    final userId = _requiredString(op.payload, 'userId');
    final doc = _members(boardId).doc(userId);

    await _withIdempotency(
      boardId: boardId,
      operation: op,
      apply: (tx) async {
        if (op.type == OutboxOperationType.delete) {
          tx.delete(doc);
          return;
        }

        final updatedAtMicros =
            _updatedAtMicros(op.payload, fallback: op.createdAt);
        final current = await tx.get(doc);

        final data = <String, Object?>{
          'boardId': boardId,
          'userId': userId,
          'role': _requiredString(op.payload, 'role'),
          'joinedAt': op.payload['joinedAt'] ??
              current.data()?['joinedAt'] ??
              op.createdAt.toUtc().toIso8601String(),
          'joinedAtEpochMillis':
              (op.payload['joinedAtEpochMillis'] as num?)?.toInt() ??
                  current.data()?['joinedAtEpochMillis'] ??
                  op.createdAt.toUtc().millisecondsSinceEpoch,
          'updatedAtMicros': updatedAtMicros,
          'lastWriterOpId': op.id,
        };

        if (current.exists) {
          final currentMicros =
              (current.data()?['updatedAtMicros'] as int?) ?? 0;
          if (currentMicros > updatedAtMicros) {
            return;
          }
        }

        tx.set(doc, data, SetOptions(merge: true));
      },
    );
  }

  Future<void> _applyColumnOp(OutboxOperation op) async {
    final boardId = _requiredString(op.payload, 'boardId');
    final columnId = _requiredString(op.payload, 'columnId');
    final doc = _columns(boardId).doc(columnId);

    await _withIdempotency(
      boardId: boardId,
      operation: op,
      apply: (tx) async {
        if (op.type == OutboxOperationType.delete) {
          tx.delete(doc);
          return;
        }

        final updatedAtMicros =
            _updatedAtMicros(op.payload, fallback: op.createdAt);
        final current = await tx.get(doc);

        final data = <String, Object?>{
          'boardId': boardId,
          'columnId': columnId,
          'name': (op.payload['name'] as String?) ??
              (current.data()?['name'] as String?) ??
              'Column',
          'orderIndex': (op.payload['orderIndex'] as num?)?.toInt() ??
              (current.data()?['orderIndex'] as int?) ??
              0,
          'kind': (op.payload['kind'] as String?) ??
              (current.data()?['kind'] as String?) ??
              'custom',
          'isDoneState': op.payload['isDoneState'] == true ||
              (current.data()?['isDoneState'] == true &&
                  !op.payload.containsKey('isDoneState')),
          'isBlockedState': op.payload['isBlockedState'] == true ||
              (current.data()?['isBlockedState'] == true &&
                  !op.payload.containsKey('isBlockedState')),
          'isCancelledState': op.payload['isCancelledState'] == true ||
              (current.data()?['isCancelledState'] == true &&
                  !op.payload.containsKey('isCancelledState')),
          'isDesignated': op.payload['isDesignated'] == true ||
              (current.data()?['isDesignated'] == true &&
                  !op.payload.containsKey('isDesignated')),
          'isEnabled': op.payload.containsKey('isEnabled')
              ? op.payload['isEnabled'] == true
              : (current.data()?['isEnabled'] != false),
          'updatedAtMicros': updatedAtMicros,
          'lastWriterOpId': op.id,
        };

        if (current.exists) {
          final currentMicros =
              (current.data()?['updatedAtMicros'] as int?) ?? 0;
          if (currentMicros > updatedAtMicros) {
            return;
          }
        }

        tx.set(doc, data, SetOptions(merge: true));
      },
    );
  }

  Future<void> _applyColumnReorder(OutboxOperation op) async {
    final boardId = _requiredString(op.payload, 'boardId');
    final ordered = (op.payload['orderedColumnIds'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];

    await _withIdempotency(
      boardId: boardId,
      operation: op,
      apply: (tx) async {
        final updatedAtMicros =
            _updatedAtMicros(op.payload, fallback: op.createdAt);
        for (var i = 0; i < ordered.length; i++) {
          final doc = _columns(boardId).doc(ordered[i]);
          final current = await tx.get(doc);
          final currentMicros =
              (current.data()?['updatedAtMicros'] as int?) ?? 0;
          if (current.exists && currentMicros > updatedAtMicros) {
            continue;
          }
          tx.set(
            doc,
            {
              'boardId': boardId,
              'columnId': ordered[i],
              'orderIndex': i,
              'updatedAtMicros': updatedAtMicros,
              'lastWriterOpId': op.id,
            },
            SetOptions(merge: true),
          );
        }
      },
    );
  }

  Future<void> _applyWorkItemOp(OutboxOperation op) async {
    final boardId = _requiredString(op.payload, 'boardId');
    final itemId = _requiredString(op.payload, 'itemId');
    final doc = _workItems(boardId).doc(itemId);

    await _withIdempotency(
      boardId: boardId,
      operation: op,
      apply: (tx) async {
        if (op.type == OutboxOperationType.delete) {
          tx.delete(doc);
          return;
        }

        final updatedAtMicros =
            _updatedAtMicros(op.payload, fallback: op.createdAt);
        final current = await tx.get(doc);
        final currentData = current.data() ?? const <String, dynamic>{};
        final columnId = (op.payload['columnId'] as String?) ??
            (op.payload['toColumnId'] as String?) ??
            (currentData['columnId'] as String?);
        if (columnId == null || columnId.isEmpty) {
          throw SyncRemoteException(
              'Missing required payload field "columnId"');
        }

        final data = <String, Object?>{
          'boardId': boardId,
          'itemId': itemId,
          'title': (op.payload['title'] as String?) ??
              (currentData['title'] as String?) ??
              'Untitled',
          'type': (op.payload['type'] as String?) ??
              (currentData['type'] as String?) ??
              'task',
          'sortOrder': (op.payload['sortOrder'] as num?)?.toDouble() ??
              (currentData['sortOrder'] as num?)?.toDouble() ??
              0,
          'parentId': op.payload.containsKey('parentId')
              ? op.payload['parentId']
              : currentData['parentId'],
          'columnId': columnId,
          'description': op.payload.containsKey('description')
              ? op.payload['description']
              : currentData['description'],
          'assigneeIds': (op.payload['assigneeIds'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              (currentData['assigneeIds'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              const <String>[],
          'startAt': op.payload.containsKey('startAt')
              ? op.payload['startAt']
              : currentData['startAt'],
          'targetEndAt': op.payload.containsKey('targetEndAt')
              ? op.payload['targetEndAt']
              : currentData['targetEndAt'],
          'dueAt': op.payload.containsKey('dueAt')
              ? op.payload['dueAt']
              : currentData['dueAt'],
          'completedAt': op.payload.containsKey('completedAt')
              ? op.payload['completedAt']
              : currentData['completedAt'],
          'estimatedEffortMinutes':
              op.payload.containsKey('estimatedEffortMinutes')
                  ? op.payload['estimatedEffortMinutes']
                  : currentData['estimatedEffortMinutes'],
          'actualEffortMinutes': op.payload.containsKey('actualEffortMinutes')
              ? op.payload['actualEffortMinutes']
              : currentData['actualEffortMinutes'],
          'tags': (op.payload['tags'] as List?)?.whereType<String>().toList() ??
              (currentData['tags'] as List?)?.whereType<String>().toList() ??
              const <String>[],
          'archived': op.payload.containsKey('archived')
              ? op.payload['archived'] == true
              : currentData['archived'] == true,
          'isInbox': op.payload.containsKey('isInbox')
              ? op.payload['isInbox'] == true
              : currentData['isInbox'] == true,
          'recurrence': op.payload.containsKey('recurrence')
              ? (op.payload['recurrence'] as Map?)?.cast<String, Object?>()
              : (currentData['recurrence'] as Map?)?.cast<String, Object?>(),
          'createdAt': op.payload['createdAt'] ??
              currentData['createdAt'] ??
              op.createdAt.toUtc().toIso8601String(),
          'updatedAt':
              op.payload['updatedAt'] ?? op.createdAt.toUtc().toIso8601String(),
          'updatedAtMicros': updatedAtMicros,
          'lastWriterOpId': op.id,
        };

        if (current.exists) {
          final currentMicros =
              (current.data()?['updatedAtMicros'] as int?) ?? 0;
          if (currentMicros > updatedAtMicros) {
            return;
          }
        }

        tx.set(doc, data, SetOptions(merge: true));
      },
    );
  }

  @override
  Future<void> applyOperation(OutboxOperation operation) async {
    try {
      final boardId = operation.payload['boardId'];
      if (boardId is! String || boardId.isEmpty) {
        throw SyncRemoteException('Operation payload must contain boardId');
      }

      if (operation.entity == 'board') {
        await _applyBoardOp(operation);
        return;
      }
      if (operation.entity == 'boardMember') {
        await _applyMemberOp(operation);
        return;
      }
      if (operation.entity == 'column') {
        if (operation.type == OutboxOperationType.reorder) {
          await _applyColumnReorder(operation);
        } else {
          await _applyColumnOp(operation);
        }
        return;
      }
      if (operation.entity == 'workItem') {
        await _applyWorkItemOp(operation);
        return;
      }

      throw SyncRemoteException('Unsupported entity "${operation.entity}"');
    } on FirebaseException catch (error) {
      throw mapFirestoreExceptionToSyncRemote(error, operation.id);
    }
  }
}

@visibleForTesting
SyncRemoteException mapFirestoreExceptionToSyncRemote(
  FirebaseException error,
  String operationId,
) {
  if (error.code == 'permission-denied') {
    return SyncRemotePermissionDeniedException(
      'Permission denied by Firestore rules while applying operation $operationId.',
    );
  }
  return SyncRemoteException(
      'Firestore error (${error.code}): ${error.message}');
}
