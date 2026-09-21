import '../models/board.dart';
import '../models/board_member.dart';
import '../models/board_snapshot.dart';
import '../models/board_validation_settings.dart';
import '../models/board_workflow_settings.dart';
import '../models/column.dart';
import '../models/work_item.dart';
import '../models/work_item_recurrence.dart';
import '../models/work_item_type.dart';

abstract class BoardRepository {
  Future<List<Board>> listBoards();
  Future<Board> createBoard(String name);
  Future<int> enqueueOwnedBoardSnapshotsForSync();
  Stream<BoardSnapshot> watchBoard(String boardId);
  Future<void> renameBoard({
    required String boardId,
    required String name,
  });
  Future<void> deleteBoard({
    required String boardId,
  });

  Future<void> inviteMember({
    required String boardId,
    required String userId,
    required BoardRole role,
  });

  Future<void> acceptInvite({
    required String boardId,
  });

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

  Future<void> updateColumnSemantics({
    required String boardId,
    required String columnId,
    BoardColumnKind? kind,
    bool? isDoneState,
    bool? isBlockedState,
    bool? isCancelledState,
    bool? isEnabled,
  });

  Future<WorkItem> createItem({
    required String boardId,
    required String title,
    required WorkItemType type,
    required String toColumnId,
    String? parentId,
    String? description,
    DateTime? startAt,
    DateTime? targetEndAt,
    DateTime? dueAt,
    List<String> tags = const [],
    int? estimatedEffortMinutes,
    int? actualEffortMinutes,
    WorkItemRecurrence? recurrence,
  });

  Future<void> createInboxCapture({
    required String boardId,
    required String title,
    List<String> tags = const [],
  });

  Future<void> triageInboxItem({
    required String fromBoardId,
    required String itemId,
    required String toBoardId,
    required String toColumnId,
    required WorkItemType type,
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

  Future<void> reorderItem({
    required String boardId,
    required String itemId,
    String? toColumnId,
    String? parentId,
    bool clearParent = false,
    String? beforeItemId,
    String? afterItemId,
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
    double? sortOrder,
    String? parentId,
    DateTime? startAt,
    DateTime? targetEndAt,
    DateTime? dueAt,
    int? estimatedEffortMinutes,
    int? actualEffortMinutes,
    WorkItemRecurrence? recurrence,
    List<String>? tags,
    bool? archived,
    bool clearParent = false,
    bool clearDescription = false,
    bool clearStartAt = false,
    bool clearTargetEndAt = false,
    bool clearDueAt = false,
    bool clearEstimatedEffort = false,
    bool clearActualEffort = false,
    bool clearRecurrence = false,
  });

  Future<void> reparentItem({
    required String boardId,
    required String itemId,
    String? parentId,
    bool clearParent = false,
  });

  Future<void> deleteItem({
    required String boardId,
    required String itemId,
  });

  Future<void> restoreItem({
    required String boardId,
    required WorkItem item,
  });

  Future<void> bulkUpdateItems({
    required String boardId,
    required List<String> itemIds,
    String? toColumnId,
    bool? archived,
    List<String> addTags = const [],
    List<String> removeTags = const [],
  });

  Future<void> updateBoardValidationSettings({
    required String boardId,
    required BoardValidationSettings settings,
  });

  Future<void> updateBoardWorkflowSettings({
    required String boardId,
    required BoardWorkflowSettings settings,
  });

  Future<void> applyWorkflowTemplate({
    required String boardId,
    required String templateId,
  });
}
