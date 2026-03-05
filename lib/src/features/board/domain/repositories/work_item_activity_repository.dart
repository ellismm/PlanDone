import '../models/work_item_activity_event.dart';

abstract class WorkItemActivityRepository {
  Future<void> append(WorkItemActivityEvent event);

  Future<List<WorkItemActivityEvent>> listForItem({
    required String boardId,
    required String itemId,
    int limit = 100,
  });
}
