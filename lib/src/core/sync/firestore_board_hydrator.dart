import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/board/data/local/local_board_store.dart';
import '../../features/board/domain/models/board.dart';
import '../../features/board/domain/models/board_member.dart';
import '../../features/board/domain/models/board_validation_settings.dart';
import '../../features/board/domain/models/board_workflow_settings.dart';
import '../../features/board/domain/models/column.dart';
import '../../features/board/domain/models/work_item.dart';
import '../../features/board/domain/models/work_item_recurrence.dart';
import '../../features/board/domain/models/work_item_type.dart';

class FirestoreBoardHydrator {
  FirestoreBoardHydrator({
    required FirebaseFirestore firestore,
    required LocalBoardStore localStore,
  })  : _firestore = firestore,
        _localStore = localStore;

  final FirebaseFirestore _firestore;
  final LocalBoardStore _localStore;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  CollectionReference<Map<String, dynamic>> get _boards =>
      _firestore.collection('boards');

  Future<void> startForBoard(String boardId) async {
    await stop();

    _subscriptions.add(
      _boards.doc(boardId).snapshots().listen((doc) async {
        if (!doc.exists) {
          await _localStore.deleteBoard(boardId);
          return;
        }
        final data = doc.data() ?? const <String, dynamic>{};
        final createdAt =
            DateTime.tryParse((data['createdAt'] as String?) ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        final updatedAt =
            DateTime.tryParse((data['updatedAt'] as String?) ?? '') ??
                createdAt;
        final validationSettings = BoardValidationSettings.fromMap(
          (data['validationSettings'] as Map?)?.cast<String, Object?>(),
        );
        final workflowSettings = BoardWorkflowSettings.fromMap(
          (data['workflowSettings'] as Map?)?.cast<String, Object?>(),
        );

        await _localStore.upsertBoard(
          Board(
            boardId: boardId,
            name: (data['name'] as String?) ?? 'Board',
            ownerId: (data['ownerId'] as String?) ?? 'unknown',
            createdAt: createdAt,
            updatedAt: updatedAt,
            validationSettings: validationSettings,
            workflowSettings: workflowSettings,
          ),
        );
      }),
    );

    _subscriptions.add(
      _boards
          .doc(boardId)
          .collection('members')
          .snapshots()
          .listen((snapshot) async {
        for (final change in snapshot.docChanges) {
          final data = change.doc.data() ?? const <String, dynamic>{};
          final userId = (data['userId'] as String?) ?? change.doc.id;
          if (change.type == DocumentChangeType.removed) {
            await _localStore.deleteMember(boardId: boardId, userId: userId);
            continue;
          }

          final roleName = (data['role'] as String?) ?? BoardRole.member.name;
          final role = BoardRole.values.firstWhere(
            (r) => r.name == roleName,
            orElse: () => BoardRole.member,
          );
          final joinedAtEpochMillis =
              (data['joinedAtEpochMillis'] as num?)?.toInt();
          final joinedAt = joinedAtEpochMillis != null
              ? DateTime.fromMillisecondsSinceEpoch(joinedAtEpochMillis)
              : DateTime.tryParse((data['joinedAt'] as String?) ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);

          await _localStore.upsertMember(
            BoardMember(
              boardId: boardId,
              userId: userId,
              role: role,
              joinedAt: joinedAt,
            ),
          );
        }
      }),
    );

    _subscriptions.add(
      _boards
          .doc(boardId)
          .collection('columns')
          .snapshots()
          .listen((snapshot) async {
        for (final change in snapshot.docChanges) {
          final data = change.doc.data() ?? const <String, dynamic>{};
          final columnId = (data['columnId'] as String?) ?? change.doc.id;
          if (change.type == DocumentChangeType.removed) {
            await _localStore.deleteColumn(
                boardId: boardId, columnId: columnId);
            continue;
          }

          await _localStore.upsertColumn(
            BoardColumn(
              columnId: columnId,
              boardId: boardId,
              name: (data['name'] as String?) ?? 'Column',
              orderIndex: (data['orderIndex'] as num?)?.toInt() ?? 0,
              kind: boardColumnKindFromName(data['kind'] as String?),
              isDoneState: data['isDoneState'] == true,
              isBlockedState: data['isBlockedState'] == true,
              isCancelledState: data['isCancelledState'] == true,
              isDesignated: data['isDesignated'] == true,
              isEnabled: data['isEnabled'] != false,
            ),
          );
        }
      }),
    );

    _subscriptions.add(
      _boards
          .doc(boardId)
          .collection('workItems')
          .snapshots()
          .listen((snapshot) async {
        for (final change in snapshot.docChanges) {
          final data = change.doc.data() ?? const <String, dynamic>{};
          final itemId = (data['itemId'] as String?) ?? change.doc.id;
          if (change.type == DocumentChangeType.removed) {
            await _localStore.deleteItem(boardId: boardId, itemId: itemId);
            continue;
          }

          final typeName = (data['type'] as String?) ?? WorkItemType.task.name;
          final type = WorkItemType.values.firstWhere(
            (t) => t.name == typeName,
            orElse: () => WorkItemType.task,
          );

          DateTime? parseDate(String key) {
            final raw = data[key] as String?;
            if (raw == null || raw.isEmpty) return null;
            return DateTime.tryParse(raw);
          }

          final createdAt =
              parseDate('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0);
          final updatedAt = parseDate('updatedAt') ?? createdAt;

          await _localStore.upsertItem(
            WorkItem(
              itemId: itemId,
              boardId: boardId,
              title: (data['title'] as String?) ?? 'Untitled',
              type: type,
              parentId: data['parentId'] as String?,
              columnId: (data['columnId'] as String?) ?? 'c-todo',
              description: data['description'] as String?,
              assigneeIds: (data['assigneeIds'] as List?)
                      ?.whereType<String>()
                      .toList() ??
                  const <String>[],
              startAt: parseDate('startAt'),
              targetEndAt: parseDate('targetEndAt'),
              dueAt: parseDate('dueAt'),
              completedAt: parseDate('completedAt'),
              estimatedEffortMinutes:
                  (data['estimatedEffortMinutes'] as num?)?.toInt(),
              actualEffortMinutes:
                  (data['actualEffortMinutes'] as num?)?.toInt(),
              recurrence: WorkItemRecurrence.fromMap(
                (data['recurrence'] as Map?)?.cast<String, Object?>(),
              ),
              tags: (data['tags'] as List?)?.whereType<String>().toList() ??
                  const <String>[],
              archived: data['archived'] == true,
              isInbox: data['isInbox'] == true,
              createdAt: createdAt,
              updatedAt: updatedAt,
            ),
          );
        }
      }),
    );
  }

  Future<void> stop() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}
