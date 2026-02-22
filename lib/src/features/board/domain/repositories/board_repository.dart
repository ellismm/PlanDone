import '../models/board.dart';
import '../models/board_member.dart';
import '../models/board_snapshot.dart';
import '../models/work_item_type.dart';

abstract class BoardRepository {
  Future<List<Board>> listBoards();
  Future<Board> createBoard(String name);
  Stream<BoardSnapshot> watchBoard(String boardId);

  Future<void> addMember({
    required String boardId,
    required String userId,
    required BoardRole role,
  });

  Future<void> updateMemberRole({
    required String boardId,
    required String userId,
    required BoardRole role,
  });

  Future<void> removeMember({
    required String boardId,
    required String userId,
  });

  Future<void> createColumn({
    required String boardId,
    required String name,
  });

  Future<void> renameColumn({
    required String boardId,
    required String columnId,
    required String name,
  });

  Future<void> deleteColumn({
    required String boardId,
    required String columnId,
  });

  Future<void> reorderColumns({
    required String boardId,
    required List<String> orderedColumnIds,
  });

  Future<void> createItem({
    required String boardId,
    required String title,
    required WorkItemType type,
    required String toColumnId,
    String? parentId,
  });

  Future<void> createTask({
    required String boardId,
    required String title,
    required String toColumnId,
  });

  Future<void> moveItem({
    required String boardId,
    required String itemId,
    required String toColumnId,
  });

  Future<void> moveItemToBoard({
    required String fromBoardId,
    required String itemId,
    required String toBoardId,
    required String toColumnId,
  });

  Future<void> updateItem({
    required String boardId,
    required String itemId,
    String? title,
    String? description,
    String? parentId,
    DateTime? dueAt,
    List<String>? tags,
    bool? archived,
    bool clearParent = false,
    bool clearDescription = false,
    bool clearDueAt = false,
  });
}
