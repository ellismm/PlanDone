import 'board.dart';
import 'board_member.dart';
import 'column.dart';
import 'work_item.dart';

class BoardBackupDocument {
  const BoardBackupDocument({
    required this.schemaVersion,
    required this.exportedAt,
    required this.board,
    required this.members,
    required this.columns,
    required this.items,
  });

  final int schemaVersion;
  final DateTime exportedAt;
  final Board board;
  final List<BoardMember> members;
  final List<BoardColumn> columns;
  final List<WorkItem> items;
}

class BoardBackupFile {
  const BoardBackupFile({
    required this.path,
    required this.fileName,
    required this.boardId,
    required this.boardName,
    required this.exportedAt,
  });

  final String path;
  final String fileName;
  final String boardId;
  final String boardName;
  final DateTime exportedAt;
}
