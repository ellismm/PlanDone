import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/data/local/drift/board_database.dart' hide BoardMember;
import 'package:plandone/src/features/board/data/local/drift/drift_local_board_store.dart';
import 'package:plandone/src/features/board/domain/models/board_member.dart';
import 'package:plandone/src/features/board/domain/models/column.dart' as domain_column;
import 'package:plandone/src/features/board/domain/models/work_item.dart' as domain;
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  test('drift store seeds and persists board snapshot updates', () async {
    final db = BoardDatabase.forTesting(NativeDatabase.memory());
    final store = DriftLocalBoardStore(database: db);

    final initial = await store.getBoard('board-1');
    expect(initial.board.name, 'My Board');
    expect(initial.columns.isNotEmpty, isTrue);
    expect(initial.items.any((i) => i.type == WorkItemType.action), isTrue);

    await store.upsertColumn(
      const domain_column.BoardColumn(
        columnId: 'c-review',
        boardId: 'board-1',
        name: 'Review',
        orderIndex: 3,
      ),
    );

    await store.upsertItem(
      domain.WorkItem(
        itemId: 'a-review',
        boardId: 'board-1',
        title: 'Review drift persistence path',
        type: WorkItemType.action,
        columnId: 'c-review',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    final updated = await store.getBoard('board-1');
    expect(updated.columns.any((c) => c.columnId == 'c-review'), isTrue);
    expect(updated.items.any((i) => i.itemId == 'a-review'), isTrue);

    await db.close();
  });

  test('drift store persists board members', () async {
    final db = BoardDatabase.forTesting(NativeDatabase.memory());
    final store = DriftLocalBoardStore(database: db);

    await store.upsertMember(
      BoardMember(
        boardId: 'board-1',
        userId: 'user-2',
        role: BoardRole.member,
        joinedAt: DateTime(2026, 1, 1),
      ),
    );

    final withMember = await store.getBoard('board-1');
    expect(withMember.members.any((m) => m.userId == 'user-2' && m.role == BoardRole.member), isTrue);

    await store.deleteMember(boardId: 'board-1', userId: 'user-2');
    final afterDelete = await store.getBoard('board-1');
    expect(afterDelete.members.any((m) => m.userId == 'user-2'), isFalse);

    await db.close();
  });
}
