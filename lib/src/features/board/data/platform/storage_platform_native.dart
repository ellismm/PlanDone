import '../../../../core/outbox/drift_outbox_queue.dart';
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
import '../local/drift/board_database.dart' as drift_db;
import '../local/drift/drift_local_board_store.dart';
import '../local/in_memory_local_board_store.dart';
import '../local/local_board_store.dart';
import '../repositories/autofill_settings_repository_impl.dart';
import '../repositories/board_backup_repository_impl.dart';
import '../repositories/board_calendar_preferences_repository_impl.dart';
import '../repositories/board_flow_preferences_repository_impl.dart';
import '../repositories/board_filter_preset_repository_impl.dart';
import '../repositories/hierarchy_view_preferences_repository_impl.dart';
import '../repositories/in_memory/hierarchy_view_preferences_repository_in_memory.dart';
import '../repositories/notification_preferences_repository_impl.dart';
import '../repositories/work_item_activity_repository_impl.dart';
import 'storage_platform_interface.dart';

class NativePlatformBoardDatabase implements PlatformBoardDatabase {
  NativePlatformBoardDatabase({required String databaseName})
      : database = drift_db.BoardDatabase(databaseName: databaseName);

  final drift_db.BoardDatabase database;

  @override
  Future<void> close() => database.close();
}

PlatformBoardDatabase createBoardDatabase({
  required String databaseName,
}) {
  return NativePlatformBoardDatabase(databaseName: databaseName);
}

Future<void> deleteBoardDatabase({
  required String databaseName,
  required bool useInMemoryLocalStore,
}) async {
  if (useInMemoryLocalStore) return;
  await drift_db.deleteBoardDatabaseFile(databaseName);
}

LocalBoardStore createLocalBoardStore({
  required PlatformBoardDatabase database,
  required String currentUserId,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftLocalBoardStore(
      database: (database as NativePlatformBoardDatabase).database,
      currentUserId: currentUserId,
    );
  }
  return InMemoryLocalBoardStore(currentUserId: currentUserId);
}

OutboxQueue createOutboxQueue({
  required PlatformBoardDatabase database,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftOutboxQueue((database as NativePlatformBoardDatabase).database);
  }
  return InMemoryOutboxQueue();
}

WorkItemActivityRepository createWorkItemActivityRepository({
  required PlatformBoardDatabase database,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftWorkItemActivityRepository(
      database: (database as NativePlatformBoardDatabase).database,
    );
  }
  return InMemoryWorkItemActivityRepository();
}

BoardFilterPresetRepository createBoardFilterPresetRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftBoardFilterPresetRepository(
      database: (database as NativePlatformBoardDatabase).database,
      userId: userId,
    );
  }
  return InMemoryBoardFilterPresetRepository();
}

BoardCalendarPreferencesRepository createBoardCalendarPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftBoardCalendarPreferencesRepository(
      database: (database as NativePlatformBoardDatabase).database,
      userId: userId,
    );
  }
  return InMemoryBoardCalendarPreferencesRepository(userId: userId);
}

BoardFlowPreferencesRepository createBoardFlowPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftBoardFlowPreferencesRepository(
      database: (database as NativePlatformBoardDatabase).database,
      userId: userId,
    );
  }
  return InMemoryBoardFlowPreferencesRepository(userId: userId);
}

HierarchyViewPreferencesRepository createHierarchyViewPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftHierarchyViewPreferencesRepository(
      database: (database as NativePlatformBoardDatabase).database,
      userId: userId,
    );
  }
  return InMemoryHierarchyViewPreferencesRepository(userId: userId);
}

AutofillSettingsRepository createAutofillSettingsRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftAutofillSettingsRepository(
      database: (database as NativePlatformBoardDatabase).database,
      userId: userId,
    );
  }
  return InMemoryAutofillSettingsRepository(userId: userId);
}

NotificationPreferencesRepository createNotificationPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  if (!useInMemoryLocalStore) {
    return DriftNotificationPreferencesRepository(
      database: (database as NativePlatformBoardDatabase).database,
      userId: userId,
    );
  }
  return InMemoryNotificationPreferencesRepository(userId: userId);
}

BoardBackupRepository createBoardBackupRepository({
  required LocalBoardStore localStore,
  required OutboxQueue outboxQueue,
  required String currentUserId,
  required bool useInMemoryLocalStore,
}) {
  return BoardBackupRepositoryImpl(
    localStore: localStore,
    outboxQueue: outboxQueue,
    currentUserId: currentUserId,
  );
}
