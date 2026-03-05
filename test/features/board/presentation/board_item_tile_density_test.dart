import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/column.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/presentation/board_controller.dart';
import 'package:plandone/src/features/board/presentation/board_item_tile.dart';

void main() {
  final columns = <BoardColumn>[
    const BoardColumn(
      columnId: 'c-todo',
      boardId: 'board-1',
      name: 'To Do',
      orderIndex: 0,
    ),
    const BoardColumn(
      columnId: 'c-done',
      boardId: 'board-1',
      name: 'Done',
      orderIndex: 1,
      kind: BoardColumnKind.done,
      isDoneState: true,
    ),
  ];

  final parent = WorkItem(
    itemId: 'parent-1',
    boardId: 'board-1',
    title: 'Parent item',
    type: WorkItemType.task,
    columnId: 'c-todo',
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  final item = WorkItem(
    itemId: 'item-1',
    boardId: 'board-1',
    title:
        'This is a very long work item title that should remain inspectable via tooltip for readability',
    type: WorkItemType.action,
    parentId: parent.itemId,
    columnId: 'c-todo',
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  Widget buildTile(BoardCardDensity density) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: BoardItemTile(
            item: item,
            columns: columns,
            allItems: [parent, item],
            focused: false,
            selected: false,
            childCount: 2,
            density: density,
            onSelect: () {},
            onAddChildAction: () {},
            onEdit: () {},
            onViewDetails: () {},
            onToggleArchive: () {},
            onMoveToColumn: (_) async {},
            onJumpToParent: () {},
            canModifyItems: true,
          ),
        ),
      ),
    );
  }

  testWidgets('comfortable density keeps richer parent metadata row',
      (tester) async {
    await tester.pumpWidget(buildTile(BoardCardDensity.comfortable));

    expect(find.textContaining('Parent: Parent item'), findsOneWidget);
    expect(find.text('Children: 2'), findsOneWidget);
  });

  testWidgets('compact density reduces parent chrome and keeps title tooltip',
      (tester) async {
    await tester.pumpWidget(buildTile(BoardCardDensity.compact));

    expect(find.textContaining('Parent: Parent item'), findsNothing);
    expect(find.text('Parent'), findsOneWidget);

    final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
    expect(
      tooltips.any(
        (tooltip) =>
            tooltip.message ==
            'This is a very long work item title that should remain inspectable via tooltip for readability',
      ),
      isTrue,
    );
  });
}
