import '../../../../core/outbox/outbox_queue.dart';
import '../../domain/repositories/autofill_settings_repository.dart';
import '../../domain/repositories/board_backup_repository.dart';
import '../../domain/repositories/board_calendar_preferences_repository.dart';
import '../../domain/repositories/board_flow_preferences_repository.dart';
import '../../domain/repositories/board_filter_preset_repository.dart';
import '../../domain/repositories/hierarchy_view_preferences_repository.dart';
import '../../domain/repositories/notification_preferences_repository.dart';
import '../../domain/repositories/work_item_activity_repository.dart';
import '../local/local_board_store.dart';
import 'storage_platform_interface.dart';
import 'storage_platform_native.dart'
    if (dart.library.js_interop) 'storage_platform_web.dart' as impl;

PlatformBoardDatabase createBoardDatabase({
  required String databaseName,
}) {
  return impl.createBoardDatabase(databaseName: databaseName);
}

Future<void> deleteBoardDatabase({
  required String databaseName,
  required bool useInMemoryLocalStore,
}) {
  return impl.deleteBoardDatabase(
    databaseName: databaseName,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

LocalBoardStore createLocalBoardStore({
  required PlatformBoardDatabase database,
  required String currentUserId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createLocalBoardStore(
    database: database,
    currentUserId: currentUserId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

OutboxQueue createOutboxQueue({
  required PlatformBoardDatabase database,
  required bool useInMemoryLocalStore,
}) {
  return impl.createOutboxQueue(
    database: database,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

WorkItemActivityRepository createWorkItemActivityRepository({
  required PlatformBoardDatabase database,
  required bool useInMemoryLocalStore,
}) {
  return impl.createWorkItemActivityRepository(
    database: database,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

BoardFilterPresetRepository createBoardFilterPresetRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createBoardFilterPresetRepository(
    database: database,
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

BoardCalendarPreferencesRepository createBoardCalendarPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createBoardCalendarPreferencesRepository(
    database: database,
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

BoardFlowPreferencesRepository createBoardFlowPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createBoardFlowPreferencesRepository(
    database: database,
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

HierarchyViewPreferencesRepository createHierarchyViewPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createHierarchyViewPreferencesRepository(
    database: database,
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

AutofillSettingsRepository createAutofillSettingsRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createAutofillSettingsRepository(
    database: database,
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

NotificationPreferencesRepository createNotificationPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createNotificationPreferencesRepository(
    database: database,
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}

BoardBackupRepository createBoardBackupRepository({
  required LocalBoardStore localStore,
  required OutboxQueue outboxQueue,
  required String currentUserId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createBoardBackupRepository(
    localStore: localStore,
    outboxQueue: outboxQueue,
    currentUserId: currentUserId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}
