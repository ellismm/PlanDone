import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/autofill_settings.dart';
import 'package:plandone/src/features/board/domain/models/board.dart';
import 'package:plandone/src/features/board/domain/models/board_snapshot.dart';
import 'package:plandone/src/features/board/domain/models/column.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/domain/policies/autofill_suggestion_policy.dart';

void main() {
  BoardSnapshot buildSnapshot() {
    final now = DateTime(2026, 2, 28, 10);
    return BoardSnapshot(
      board: Board(
        boardId: 'board-1',
        name: 'Board',
        ownerId: 'user-1',
        createdAt: now,
        updatedAt: now,
      ),
      columns: const [
        BoardColumn(
            columnId: 'c-todo',
            boardId: 'board-1',
            name: 'Todo',
            orderIndex: 0),
        BoardColumn(
            columnId: 'c-doing',
            boardId: 'board-1',
            name: 'Doing',
            orderIndex: 1),
        BoardColumn(
          columnId: 'c-done',
          boardId: 'board-1',
          name: 'Done',
          orderIndex: 2,
          isDoneState: true,
        ),
      ],
      members: const [],
      items: [
        WorkItem(
          itemId: 'p-1',
          boardId: 'board-1',
          title: 'Parent project',
          type: WorkItemType.project,
          columnId: 'c-doing',
          createdAt: now,
          updatedAt: now,
        ),
        WorkItem(
          itemId: 'a-1',
          boardId: 'board-1',
          title: 'Action 1',
          type: WorkItemType.action,
          parentId: 'p-1',
          columnId: 'c-doing',
          tags: const ['ops', 'bug'],
          estimatedEffortMinutes: 30,
          createdAt: now,
          updatedAt: now,
        ),
        WorkItem(
          itemId: 'a-2',
          boardId: 'board-1',
          title: 'Action 2',
          type: WorkItemType.action,
          parentId: 'p-1',
          columnId: 'c-doing',
          tags: const ['ops'],
          estimatedEffortMinutes: 45,
          createdAt: now,
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
      ],
    );
  }

  test('forCreateItem suggests deterministic type/column/parent/tags/estimate',
      () {
    final snapshot = buildSnapshot();
    final suggestion = AutofillSuggestionPolicy.forCreateItem(
      snapshot: snapshot,
      settings: const AutofillSettings(),
    );

    expect(suggestion.type, WorkItemType.action);
    expect(suggestion.columnId, 'c-doing');
    expect(suggestion.parentId, 'p-1');
    expect(suggestion.tags, contains('ops'));
    expect(suggestion.estimatedEffortMinutes, 38);
  });

  test('forCreateItem falls back safely on cold start', () {
    final now = DateTime(2026, 2, 28, 10);
    final snapshot = BoardSnapshot(
      board: Board(
        boardId: 'board-1',
        name: 'Board',
        ownerId: 'user-1',
        createdAt: now,
        updatedAt: now,
      ),
      columns: const [
        BoardColumn(
            columnId: 'c-todo',
            boardId: 'board-1',
            name: 'Todo',
            orderIndex: 0),
      ],
      members: const [],
      items: const [],
    );

    final suggestion = AutofillSuggestionPolicy.forCreateItem(
      snapshot: snapshot,
      settings: const AutofillSettings(),
    );

    expect(suggestion.type, WorkItemType.action);
    expect(suggestion.columnId, 'c-todo');
    expect(suggestion.parentId, isNull);
    expect(suggestion.tags, isEmpty);
    expect(suggestion.estimatedEffortMinutes, isNull);
  });

  test('suggestBoardForInboxTriage chooses board by overlap score', () {
    final now = DateTime(2026, 2, 28, 10);
    final inboxItem = WorkItem(
      itemId: 'in-1',
      boardId: 'board-1',
      title: 'Fix urgent sync bug',
      type: WorkItemType.task,
      columnId: 'c-todo',
      tags: const ['sync', 'bug'],
      createdAt: now,
      updatedAt: now,
      isInbox: true,
    );

    BoardSnapshot board(String id, String titleTag) => BoardSnapshot(
          board: Board(
            boardId: id,
            name: id,
            ownerId: 'user-1',
            createdAt: now,
            updatedAt: now,
          ),
          columns: const [
            BoardColumn(
                columnId: 'c', boardId: 'x', name: 'Todo', orderIndex: 0),
          ],
          members: const [],
          items: [
            WorkItem(
              itemId: '$id-item',
              boardId: id,
              title: titleTag,
              type: WorkItemType.action,
              columnId: 'c',
              tags: id == 'board-2' ? const ['sync', 'bug'] : const ['docs'],
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );

    final suggested = AutofillSuggestionPolicy.suggestBoardForInboxTriage(
      inboxItem: inboxItem,
      boardSnapshots: [
        board('board-1', 'Write docs'),
        board('board-2', 'Sync bug fix')
      ],
      settings: const AutofillSettings(),
      fallbackBoardId: 'board-1',
    );

    expect(suggested, 'board-2');
  });
}
