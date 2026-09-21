import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/outbox/outbox_operation.dart';
import '../../../../core/outbox/outbox_queue.dart';
import '../../domain/models/board.dart';
import '../../domain/models/board_backup_document.dart';
import '../../domain/models/board_member.dart';
import '../../domain/models/board_validation_settings.dart';
import '../../domain/models/board_workflow_settings.dart';
import '../../domain/models/column.dart';
import '../../domain/models/work_item.dart';
import '../../domain/models/work_item_recurrence.dart';
import '../../domain/models/work_item_type.dart';
import '../../domain/repositories/board_backup_repository.dart';
import '../local/local_board_store.dart';

typedef BackupDirectoryProvider = Future<Directory> Function();
typedef BackupClock = DateTime Function();

class BoardBackupRepositoryImpl implements BoardBackupRepository {
  BoardBackupRepositoryImpl({
    required LocalBoardStore localStore,
    required OutboxQueue outboxQueue,
    required String currentUserId,
    BackupDirectoryProvider? directoryProvider,
    BackupClock? clock,
  })  : _localStore = localStore,
        _outboxQueue = outboxQueue,
        _currentUserId = currentUserId,
        _directoryProvider =
            directoryProvider ?? getApplicationDocumentsDirectory,
        _clock = clock ?? DateTime.now;

  static const int currentSchemaVersion = 1;

  final LocalBoardStore _localStore;
  final OutboxQueue _outboxQueue;
  final String _currentUserId;
  final BackupDirectoryProvider _directoryProvider;
  final BackupClock _clock;

  @override
  Future<BoardBackupFile> exportBoard({
    required String boardId,
  }) async {
    final snapshot = await _localStore.getBoard(boardId);
    final exportedAt = _clock();
    final document = BoardBackupDocument(
      schemaVersion: currentSchemaVersion,
      exportedAt: exportedAt,
      board: snapshot.board,
      members: snapshot.members,
      columns: [...snapshot.columns]
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
      items: [...snapshot.items]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );

    final directory = await _ensureBackupDirectory();
    final fileName =
        'board-${_sanitizeForFile(snapshot.board.name)}-${exportedAt.microsecondsSinceEpoch}.json';
    final file = File(p.join(directory.path, fileName));
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_documentToMap(document)),
      flush: true,
    );
    return BoardBackupFile(
      path: file.path,
      fileName: fileName,
      boardId: snapshot.board.boardId,
      boardName: snapshot.board.name,
      exportedAt: exportedAt,
    );
  }

  @override
  Future<List<BoardBackupFile>> listBackups() async {
    final directory = await _ensureBackupDirectory();
    if (!await directory.exists()) return const <BoardBackupFile>[];

    final files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .cast<File>()
        .toList();

    final backups = <BoardBackupFile>[];
    for (final file in files) {
      try {
        backups.add(await _readBackupFileMetadata(file));
      } catch (_) {
        // Skip malformed backups in the listing. Import path handles errors
        // explicitly when the user tries to restore one.
      }
    }

    backups.sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
    return backups;
  }

  @override
  Future<Board> importBackup({
    required String backupPath,
  }) async {
    final document = await _readBackupDocument(File(backupPath));
    final now = _clock();
    final boardId = 'board-import-${now.microsecondsSinceEpoch}';
    final importedBoard = Board(
      boardId: boardId,
      name: document.board.name,
      ownerId: _currentUserId,
      createdAt: now,
      updatedAt: now,
      validationSettings: document.board.validationSettings,
      workflowSettings: document.board.workflowSettings,
    );

    await _localStore.upsertBoard(importedBoard);
    await _localStore.upsertMember(
      BoardMember(
        boardId: importedBoard.boardId,
        userId: _currentUserId,
        role: BoardRole.owner,
        joinedAt: now,
      ),
    );
    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'board',
      entityId: importedBoard.boardId,
      boardId: importedBoard.boardId,
      payload: {
        'name': importedBoard.name,
        'ownerId': importedBoard.ownerId,
        'createdAt': importedBoard.createdAt.toIso8601String(),
        'updatedAt': importedBoard.updatedAt.toIso8601String(),
        'validationSettings': importedBoard.validationSettings.toMap(),
        'workflowSettings': importedBoard.workflowSettings.toMap(),
      },
    );
    await _enqueue(
      now: now,
      type: OutboxOperationType.create,
      entity: 'boardMember',
      entityId: '${importedBoard.boardId}:$_currentUserId',
      boardId: importedBoard.boardId,
      payload: {
        'userId': _currentUserId,
        'role': BoardRole.owner.name,
        'joinedAt': now.toIso8601String(),
        'joinedAtEpochMillis': now.millisecondsSinceEpoch,
      },
    );

    final orderedColumns = [...document.columns]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final columnIdMap = <String, String>{};
    for (var index = 0; index < orderedColumns.length; index++) {
      final sourceColumn = orderedColumns[index];
      final columnId =
          '$boardId-col-${index + 1}-${_sanitizeForId(sourceColumn.name)}';
      columnIdMap[sourceColumn.columnId] = columnId;
      final importedColumn = sourceColumn.copyWith(
        name: sourceColumn.name,
        orderIndex: index,
      );
      final persistedColumn = BoardColumn(
        columnId: columnId,
        boardId: boardId,
        name: importedColumn.name,
        orderIndex: index,
        kind: importedColumn.kind,
        isDoneState: importedColumn.isDoneState,
        isBlockedState: importedColumn.isBlockedState,
        isCancelledState: importedColumn.isCancelledState,
        isDesignated: importedColumn.isDesignated,
        isEnabled: importedColumn.isEnabled,
      );
      await _localStore.upsertColumn(persistedColumn);
      await _enqueue(
        now: now,
        type: OutboxOperationType.create,
        entity: 'column',
        entityId: persistedColumn.columnId,
        boardId: boardId,
        payload: {
          'columnId': persistedColumn.columnId,
          'name': persistedColumn.name,
          'orderIndex': persistedColumn.orderIndex,
          'kind': persistedColumn.kind.name,
          'isDoneState': persistedColumn.isDoneState,
          'isBlockedState': persistedColumn.isBlockedState,
          'isCancelledState': persistedColumn.isCancelledState,
          'isDesignated': persistedColumn.isDesignated,
          'isEnabled': persistedColumn.isEnabled,
        },
      );
    }

    final orderedItems = [...document.items]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final itemIdMap = <String, String>{};
    for (var index = 0; index < orderedItems.length; index++) {
      itemIdMap[orderedItems[index].itemId] =
          '$boardId-item-${index + 1}-${_sanitizeForId(orderedItems[index].title)}';
    }

    for (final sourceItem in orderedItems) {
      final importedItem = WorkItem(
        itemId: itemIdMap[sourceItem.itemId]!,
        boardId: boardId,
        title: sourceItem.title,
        type: sourceItem.type,
        sortOrder: sourceItem.sortOrder,
        parentId: sourceItem.parentId == null
            ? null
            : itemIdMap[sourceItem.parentId!],
        columnId: columnIdMap[sourceItem.columnId] ?? columnIdMap.values.first,
        description: sourceItem.description,
        assigneeIds: const <String>[],
        startAt: sourceItem.startAt,
        targetEndAt: sourceItem.targetEndAt,
        dueAt: sourceItem.dueAt,
        completedAt: sourceItem.completedAt,
        estimatedEffortMinutes: sourceItem.estimatedEffortMinutes,
        actualEffortMinutes: sourceItem.actualEffortMinutes,
        tags: sourceItem.tags,
        archived: sourceItem.archived,
        isInbox: sourceItem.isInbox,
        recurrence: _remapRecurrence(
          sourceItem.recurrence,
          sourceItemId: sourceItem.itemId,
          remappedItemIds: itemIdMap,
        ),
        createdAt: sourceItem.createdAt,
        updatedAt: sourceItem.updatedAt,
      );
      await _localStore.upsertItem(importedItem);
      await _enqueue(
        now: now,
        type: OutboxOperationType.create,
        entity: 'workItem',
        entityId: importedItem.itemId,
        boardId: boardId,
        payload: {
          'itemId': importedItem.itemId,
          'title': importedItem.title,
          'type': importedItem.type.name,
          'sortOrder': importedItem.sortOrder,
          'parentId': importedItem.parentId,
          'columnId': importedItem.columnId,
          'toColumnId': importedItem.columnId,
          'description': importedItem.description,
          'assigneeIds': importedItem.assigneeIds,
          'startAt': importedItem.startAt?.toIso8601String(),
          'targetEndAt': importedItem.targetEndAt?.toIso8601String(),
          'dueAt': importedItem.dueAt?.toIso8601String(),
          'completedAt': importedItem.completedAt?.toIso8601String(),
          'estimatedEffortMinutes': importedItem.estimatedEffortMinutes,
          'actualEffortMinutes': importedItem.actualEffortMinutes,
          'tags': importedItem.tags,
          'archived': importedItem.archived,
          'isInbox': importedItem.isInbox,
          'recurrence': importedItem.recurrence?.toMap(),
          'createdAt': importedItem.createdAt.toIso8601String(),
          'updatedAt': importedItem.updatedAt.toIso8601String(),
        },
      );
    }

    return importedBoard;
  }

  @override
  Future<void> deleteBackup({
    required String backupPath,
  }) async {
    final file = File(backupPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _ensureBackupDirectory() async {
    final root = await _directoryProvider();
    final directory = Directory(p.join(root.path, 'board_backups'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<BoardBackupFile> _readBackupFileMetadata(File file) async {
    final document = await _readBackupDocument(file);
    return BoardBackupFile(
      path: file.path,
      fileName: p.basename(file.path),
      boardId: document.board.boardId,
      boardName: document.board.name,
      exportedAt: document.exportedAt,
    );
  }

  Future<BoardBackupDocument> _readBackupDocument(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Backup file must contain a JSON object.');
    }
    return _documentFromMap(decoded.cast<String, Object?>());
  }

  Map<String, Object?> _documentToMap(BoardBackupDocument document) {
    return <String, Object?>{
      'schemaVersion': document.schemaVersion,
      'exportedAt': document.exportedAt.toIso8601String(),
      'board': _boardToMap(document.board),
      'members': document.members.map(_memberToMap).toList(),
      'columns': document.columns.map(_columnToMap).toList(),
      'items': document.items.map(_itemToMap).toList(),
    };
  }

  BoardBackupDocument _documentFromMap(Map<String, Object?> map) {
    final boardPayload = (map['board'] as Map?)?.cast<String, Object?>();
    if (boardPayload == null) {
      throw const FormatException('Backup file is missing board payload.');
    }

    final members = ((map['members'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((entry) => _memberFromMap(entry.cast<String, Object?>()))
        .toList();
    final columns = ((map['columns'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((entry) => _columnFromMap(entry.cast<String, Object?>()))
        .toList();
    final items = ((map['items'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((entry) => _itemFromMap(entry.cast<String, Object?>()))
        .toList();

    return BoardBackupDocument(
      schemaVersion: _readInt(map['schemaVersion'], currentSchemaVersion),
      exportedAt: _readDateTime(map['exportedAt']) ?? _clock(),
      board: _boardFromMap(boardPayload),
      members: members,
      columns: columns,
      items: items,
    );
  }

  Map<String, Object?> _boardToMap(Board board) {
    return <String, Object?>{
      'boardId': board.boardId,
      'name': board.name,
      'ownerId': board.ownerId,
      'createdAt': board.createdAt.toIso8601String(),
      'updatedAt': board.updatedAt.toIso8601String(),
      'validationSettings': board.validationSettings.toMap(),
      'workflowSettings': board.workflowSettings.toMap(),
    };
  }

  Board _boardFromMap(Map<String, Object?> map) {
    return Board(
      boardId: (map['boardId'] as String?)?.trim().isNotEmpty == true
          ? map['boardId']! as String
          : 'backup-board',
      name: ((map['name'] as String?) ?? 'Imported board').trim(),
      ownerId: ((map['ownerId'] as String?) ?? 'unknown').trim(),
      createdAt: _readDateTime(map['createdAt']) ?? _clock(),
      updatedAt: _readDateTime(map['updatedAt']) ??
          _readDateTime(map['createdAt']) ??
          _clock(),
      validationSettings: BoardValidationSettings.fromMap(
        (map['validationSettings'] as Map?)?.cast<String, Object?>(),
      ),
      workflowSettings: BoardWorkflowSettings.fromMap(
        (map['workflowSettings'] as Map?)?.cast<String, Object?>(),
      ),
    );
  }

  Map<String, Object?> _memberToMap(BoardMember member) {
    return <String, Object?>{
      'boardId': member.boardId,
      'userId': member.userId,
      'role': member.role.name,
      'joinedAt': member.joinedAt.toIso8601String(),
    };
  }

  BoardMember _memberFromMap(Map<String, Object?> map) {
    final roleName = map['role'] as String?;
    return BoardMember(
      boardId: (map['boardId'] as String?) ?? 'backup-board',
      userId: (map['userId'] as String?) ?? 'unknown',
      role: BoardRole.values.firstWhere(
        (entry) => entry.name == roleName,
        orElse: () => BoardRole.member,
      ),
      joinedAt: _readDateTime(map['joinedAt']) ?? _clock(),
    );
  }

  Map<String, Object?> _columnToMap(BoardColumn column) {
    return <String, Object?>{
      'columnId': column.columnId,
      'boardId': column.boardId,
      'name': column.name,
      'orderIndex': column.orderIndex,
      'kind': column.kind.name,
      'isDoneState': column.isDoneState,
      'isBlockedState': column.isBlockedState,
      'isCancelledState': column.isCancelledState,
      'isDesignated': column.isDesignated,
      'isEnabled': column.isEnabled,
    };
  }

  BoardColumn _columnFromMap(Map<String, Object?> map) {
    return BoardColumn(
      columnId: (map['columnId'] as String?) ?? 'column',
      boardId: (map['boardId'] as String?) ?? 'backup-board',
      name: ((map['name'] as String?) ?? 'Column').trim(),
      orderIndex: _readInt(map['orderIndex'], 0),
      kind: boardColumnKindFromName(map['kind'] as String?),
      isDoneState: map['isDoneState'] == true,
      isBlockedState: map['isBlockedState'] == true,
      isCancelledState: map['isCancelledState'] == true,
      isDesignated: map['isDesignated'] == true,
      isEnabled: map['isEnabled'] != false,
    );
  }

  Map<String, Object?> _itemToMap(WorkItem item) {
    return <String, Object?>{
      'itemId': item.itemId,
      'boardId': item.boardId,
      'title': item.title,
      'type': item.type.name,
      'sortOrder': item.sortOrder,
      'parentId': item.parentId,
      'columnId': item.columnId,
      'description': item.description,
      'assigneeIds': item.assigneeIds,
      'startAt': item.startAt?.toIso8601String(),
      'targetEndAt': item.targetEndAt?.toIso8601String(),
      'dueAt': item.dueAt?.toIso8601String(),
      'completedAt': item.completedAt?.toIso8601String(),
      'estimatedEffortMinutes': item.estimatedEffortMinutes,
      'actualEffortMinutes': item.actualEffortMinutes,
      'tags': item.tags,
      'archived': item.archived,
      'isInbox': item.isInbox,
      'recurrence': item.recurrence?.toMap(),
      'createdAt': item.createdAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
    };
  }

  WorkItem _itemFromMap(Map<String, Object?> map) {
    final type = WorkItemType.values.firstWhere(
      (entry) => entry.name == (map['type'] as String?),
      orElse: () => WorkItemType.task,
    );
    return WorkItem(
      itemId: (map['itemId'] as String?) ?? 'item',
      boardId: (map['boardId'] as String?) ?? 'backup-board',
      title: ((map['title'] as String?) ?? 'Untitled').trim(),
      type: type,
      sortOrder: (map['sortOrder'] as num?)?.toDouble() ?? 0,
      parentId: map['parentId'] as String?,
      columnId: (map['columnId'] as String?) ?? 'column',
      description: map['description'] as String?,
      assigneeIds: ((map['assigneeIds'] as List?) ?? const <Object?>[])
          .whereType<String>()
          .toList(),
      startAt: _readDateTime(map['startAt']),
      targetEndAt: _readDateTime(map['targetEndAt']),
      dueAt: _readDateTime(map['dueAt']),
      completedAt: _readDateTime(map['completedAt']),
      estimatedEffortMinutes: _readNullableInt(map['estimatedEffortMinutes']),
      actualEffortMinutes: _readNullableInt(map['actualEffortMinutes']),
      tags: ((map['tags'] as List?) ?? const <Object?>[])
          .whereType<String>()
          .toList(),
      archived: map['archived'] == true,
      isInbox: map['isInbox'] == true,
      recurrence: WorkItemRecurrence.fromMap(
        (map['recurrence'] as Map?)?.cast<String, Object?>(),
      ),
      createdAt: _readDateTime(map['createdAt']) ?? _clock(),
      updatedAt: _readDateTime(map['updatedAt']) ??
          _readDateTime(map['createdAt']) ??
          _clock(),
    );
  }

  WorkItemRecurrence? _remapRecurrence(
    WorkItemRecurrence? recurrence, {
    required String sourceItemId,
    required Map<String, String> remappedItemIds,
  }) {
    if (recurrence == null) return null;
    final sourceRoot = recurrence.rootItemId.trim();
    final fallbackRoot = remappedItemIds[sourceItemId] ?? sourceItemId;
    return recurrence.copyWith(
      rootItemId: remappedItemIds[sourceRoot] ?? fallbackRoot,
    );
  }

  Future<void> _enqueue({
    required DateTime now,
    required OutboxOperationType type,
    required String entity,
    required String entityId,
    required String boardId,
    required Map<String, Object?> payload,
  }) {
    return _outboxQueue.enqueue(
      OutboxOperation(
        id: 'op-${now.microsecondsSinceEpoch}-${type.name}-$entity-${_sanitizeForId(entityId)}',
        type: type,
        entity: entity,
        entityId: entityId,
        payload: <String, Object?>{
          'version': OutboxOperation.currentPayloadVersion,
          'boardId': boardId,
          'actorUserId': _currentUserId,
          ...payload,
        },
        createdAt: now,
      ),
    );
  }

  String _sanitizeForFile(String raw) {
    final next = raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return next.isEmpty ? 'backup' : next;
  }

  String _sanitizeForId(String raw) {
    final next = raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return next.isEmpty ? 'id' : next;
  }

  int _readInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  int? _readNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  DateTime? _readDateTime(Object? value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }
}
