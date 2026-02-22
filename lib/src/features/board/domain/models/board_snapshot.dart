import 'board.dart';
import 'board_member.dart';
import 'column.dart';
import 'work_item.dart';

class BoardSnapshot {
  const BoardSnapshot({
    required this.board,
    required this.members,
    required this.columns,
    required this.items,
  });

  final Board board;
  final List<BoardMember> members;
  final List<BoardColumn> columns;
  final List<WorkItem> items;
}
