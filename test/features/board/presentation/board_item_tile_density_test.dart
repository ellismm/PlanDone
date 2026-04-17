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

  testWidgets(
      'compact density still shows the parent title and keeps title tooltip',
      (tester) async {
    await tester.pumpWidget(buildTile(BoardCardDensity.compact));

    expect(find.textContaining('Parent: Parent item'), findsOneWidget);

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

  testWidgets('compact density stays thinner than comfortable density',
      (tester) async {
    await tester.pumpWidget(buildTile(BoardCardDensity.compact));
    final compactHeight = tester.getSize(find.byType(Card)).height;

    await tester.pumpWidget(buildTile(BoardCardDensity.comfortable));
    final comfortableHeight = tester.getSize(find.byType(Card)).height;

    expect(compactHeight, lessThan(comfortableHeight));
  });

  testWidgets('long press callback fires when drag is disabled',
      (tester) async {
    var didLongPress = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: BoardItemTile(
              item: item,
              columns: columns,
              allItems: [parent, item],
              focused: false,
              selected: false,
              childCount: 0,
              density: BoardCardDensity.compact,
              allowDrag: false,
              onSelect: () {},
              onLongPress: () {
                didLongPress = true;
              },
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
      ),
    );

    await tester.longPress(find.byType(BoardItemTile));
    await tester.pump();

    expect(didLongPress, isTrue);
  });

  testWidgets('overflow menu exposes add child item shortcut', (tester) async {
    var didRequestChildCreate = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: BoardItemTile(
              item: item,
              columns: columns,
              allItems: [parent, item],
              focused: false,
              selected: false,
              childCount: 0,
              density: BoardCardDensity.comfortable,
              onSelect: () {},
              onAddChildAction: () {
                didRequestChildCreate = true;
              },
              onEdit: () {},
              onViewDetails: () {},
              onToggleArchive: () {},
              onMoveToColumn: (_) async {},
              onJumpToParent: () {},
              canModifyItems: true,
            ),
          ),
        ),
      ),
    );

    tester
        .state<PopupMenuButtonState<String>>(
            find.byType(PopupMenuButton<String>))
        .showButtonMenu();
    await tester.pumpAndSettle();

    expect(find.text('Add child item'), findsOneWidget);

    await tester.tap(find.text('Add child item'));
    await tester.pumpAndSettle();

    expect(didRequestChildCreate, isTrue);
  });
}
