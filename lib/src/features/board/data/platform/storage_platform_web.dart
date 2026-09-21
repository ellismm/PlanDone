import '../../../../core/outbox/in_memory_outbox_queue.dart';
import '../../../../core/outbox/outbox_queue.dart';
import '../../domain/repositories/autofill_settings_repository.dart';
import '../../domain/repositories/board_backup_repository.dart';
import '../../domain/repositories/board_calendar_preferences_repository.dart';
import '../../domain/repositories/board_flow_preferences_repository.dart';
import '../../domain/repositories/board_filter_preset_repository.dart';
import '../../domain/repositories/hierarchy_view_preferences_repository.dart';
import '../../domain/repositories/notification_preferences_repository.dart';
import '../../domain/repositories/work_item_activity_repository.dart';
import '../local/in_memory_local_board_store.dart';
import '../local/local_board_store.dart';
import '../repositories/in_memory/autofill_settings_repository_in_memory.dart';
import '../repositories/in_memory/board_backup_repository_web_stub.dart';
import '../repositories/in_memory/board_calendar_preferences_repository_in_memory.dart';
import '../repositories/in_memory/board_flow_preferences_repository_in_memory.dart';
import '../repositories/in_memory/board_filter_preset_repository_in_memory.dart';
import '../repositories/in_memory/hierarchy_view_preferences_repository_in_memory.dart';
import '../repositories/in_memory/notification_preferences_repository_in_memory.dart';
import '../repositories/in_memory/work_item_activity_repository_in_memory.dart';
import 'storage_platform_interface.dart';

class WebPlatformBoardDatabase implements PlatformBoardDatabase {
  @override
  Future<void> close() async {}
}

PlatformBoardDatabase createBoardDatabase({
  required String databaseName,
}) {
  return WebPlatformBoardDatabase();
}

Future<void> deleteBoardDatabase({
  required String databaseName,
  required bool useInMemoryLocalStore,
}) async {}

LocalBoardStore createLocalBoardStore({
  required PlatformBoardDatabase database,
  required String currentUserId,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryLocalBoardStore(currentUserId: currentUserId);
}

OutboxQueue createOutboxQueue({
  required PlatformBoardDatabase database,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryOutboxQueue();
}

WorkItemActivityRepository createWorkItemActivityRepository({
  required PlatformBoardDatabase database,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryWorkItemActivityRepository();
}

BoardFilterPresetRepository createBoardFilterPresetRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryBoardFilterPresetRepository();
}

BoardCalendarPreferencesRepository createBoardCalendarPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryBoardCalendarPreferencesRepository(userId: userId);
}

BoardFlowPreferencesRepository createBoardFlowPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryBoardFlowPreferencesRepository(userId: userId);
}

HierarchyViewPreferencesRepository createHierarchyViewPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryHierarchyViewPreferencesRepository(userId: userId);
}

AutofillSettingsRepository createAutofillSettingsRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryAutofillSettingsRepository(userId: userId);
}

NotificationPreferencesRepository createNotificationPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryNotificationPreferencesRepository(userId: userId);
}

BoardBackupRepository createBoardBackupRepository({
  required LocalBoardStore localStore,
  required OutboxQueue outboxQueue,
  required String currentUserId,
  required bool useInMemoryLocalStore,
}) {
  return const WebBoardBackupRepository();
}
