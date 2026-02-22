import '../../domain/models/board.dart';
import '../../domain/models/board_member.dart';
import '../../domain/models/board_snapshot.dart';
import '../../domain/models/column.dart';
import '../../domain/models/work_item.dart';

abstract class LocalBoardStore {
  Future<List<Board>> listBoards();
  Future<Board> createBoard(String name);
  Stream<BoardSnapshot> watchBoard(String boardId);
  Future<BoardSnapshot> getBoard(String boardId);
  Future<void> upsertColumn(BoardColumn column);
  Future<void> deleteColumn({
    required String boardId,
    required String columnId,
  });
  Future<void> reorderColumns({
    required String boardId,
    required List<String> orderedColumnIds,
  });
  Future<void> upsertMember(BoardMember member);
  Future<void> deleteMember({
    required String boardId,
    required String userId,
  });
  Future<void> upsertItem(WorkItem item);
  Future<void> deleteItem({
    required String boardId,
    required String itemId,
  });
}
