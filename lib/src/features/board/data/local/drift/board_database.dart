import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'board_database.g.dart';

class Boards extends Table {
  TextColumn get boardId => text()();
  TextColumn get name => text()();
  TextColumn get ownerId => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get validationSettingsJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get workflowSettingsJson =>
      text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {boardId};
}

class BoardColumns extends Table {
  TextColumn get columnId => text()();
  TextColumn get boardId => text()();
  TextColumn get name => text()();
  IntColumn get orderIndex => integer()();
  TextColumn get kind => text().withDefault(const Constant('custom'))();
  BoolColumn get isDoneState => boolean().withDefault(const Constant(false))();
  BoolColumn get isBlockedState =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isCancelledState =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDesignated => boolean().withDefault(const Constant(false))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {columnId};
}

class BoardMembers extends Table {
  TextColumn get boardId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text()();
  IntColumn get joinedAt => integer()();
  IntColumn get joinedAtEpochMillis =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {boardId, userId};
}

class WorkItems extends Table {
  TextColumn get itemId => text()();
  TextColumn get boardId => text()();
  TextColumn get title => text()();
  TextColumn get type => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get columnId => text()();
  TextColumn get description => text().nullable()();
  TextColumn get assigneeIdsJson => text().withDefault(const Constant('[]'))();
  IntColumn get startAt => integer().nullable()();
  IntColumn get targetEndAt => integer().nullable()();
  IntColumn get dueAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get estimatedEffortMinutes => integer().nullable()();
  IntColumn get actualEffortMinutes => integer().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {itemId};
}

@DriftDatabase(tables: [Boards, BoardColumns, BoardMembers, WorkItems])
class BoardDatabase extends _$BoardDatabase {
  BoardDatabase({String databaseName = 'plandone.sqlite'})
      : super(_openConnection(databaseName));
  BoardDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(boardMembers);
          }
          if (from < 3) {
            try {
              await m.database.customStatement(
                "ALTER TABLE boards ADD COLUMN validation_settings_json TEXT NOT NULL DEFAULT '{}'",
              );
            } catch (_) {
              // Column may already exist.
            }
            try {
              await m.database.customStatement(
                'ALTER TABLE board_members ADD COLUMN joined_at_epoch_millis INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {
              // Column may already exist.
            }
          }
          if (from < 4) {
            try {
              await m.database.customStatement(
                "ALTER TABLE boards ADD COLUMN workflow_settings_json TEXT NOT NULL DEFAULT '{}'",
              );
            } catch (_) {
              // Column may already exist.
            }

            try {
              await m.database.customStatement(
                "ALTER TABLE board_columns ADD COLUMN kind TEXT NOT NULL DEFAULT 'custom'",
              );
            } catch (_) {
              // Column may already exist.
            }
            try {
              await m.database.customStatement(
                'ALTER TABLE board_columns ADD COLUMN is_done_state INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {
              // Column may already exist.
            }
            try {
              await m.database.customStatement(
                'ALTER TABLE board_columns ADD COLUMN is_blocked_state INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {
              // Column may already exist.
            }
            try {
              await m.database.customStatement(
                'ALTER TABLE board_columns ADD COLUMN is_cancelled_state INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {
              // Column may already exist.
            }
            try {
              await m.database.customStatement(
                'ALTER TABLE board_columns ADD COLUMN is_designated INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {
              // Column may already exist.
            }
            try {
              await m.database.customStatement(
                'ALTER TABLE board_columns ADD COLUMN is_enabled INTEGER NOT NULL DEFAULT 1',
              );
            } catch (_) {
              // Column may already exist.
            }

            // Best-effort legacy semantic inference for existing boards.
            await m.database.customStatement('''
UPDATE board_columns
SET
  kind = CASE
    WHEN lower(name) LIKE '%cancel%' THEN 'cancelled'
    WHEN lower(name) IN ('done', 'complete', 'completed', 'closed') THEN 'done'
    WHEN lower(name) LIKE '%block%' THEN 'blocked'
    WHEN lower(name) LIKE '%review%' THEN 'review'
    WHEN lower(name) LIKE '%urgent%' THEN 'urgent'
    WHEN lower(name) IN ('doing') OR lower(name) LIKE '%progress%' THEN 'inProgress'
    WHEN lower(name) LIKE '%ready%' THEN 'ready'
    WHEN lower(name) LIKE '%plan%' THEN 'planning'
    WHEN lower(name) IN ('to do', 'todo', 'backlog') THEN 'backlog'
    ELSE kind
  END,
  is_done_state = CASE
    WHEN lower(name) LIKE '%cancel%' THEN 1
    WHEN lower(name) IN ('done', 'complete', 'completed', 'closed') THEN 1
    ELSE is_done_state
  END,
  is_blocked_state = CASE
    WHEN lower(name) LIKE '%block%' THEN 1
    ELSE is_blocked_state
  END,
  is_cancelled_state = CASE
    WHEN lower(name) LIKE '%cancel%' THEN 1
    ELSE is_cancelled_state
  END
WHERE kind = 'custom' AND is_done_state = 0 AND is_blocked_state = 0 AND is_cancelled_state = 0
''');
          }
          if (from < 5) {
            try {
              await m.database.customStatement(
                'ALTER TABLE work_items ADD COLUMN is_inbox INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {
              // Column may already exist.
            }
          }
          if (from < 6) {
            try {
              await m.database.customStatement(
                'ALTER TABLE work_items ADD COLUMN target_end_at INTEGER',
              );
            } catch (_) {
              // Column may already exist.
            }
            try {
              await m.database.customStatement(
                'ALTER TABLE work_items ADD COLUMN estimated_effort_minutes INTEGER',
              );
            } catch (_) {
              // Column may already exist.
            }
            try {
              await m.database.customStatement(
                'ALTER TABLE work_items ADD COLUMN actual_effort_minutes INTEGER',
              );
            } catch (_) {
              // Column may already exist.
            }
          }
        },
      );
}

LazyDatabase _openConnection(String databaseName) {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, databaseName));
    return NativeDatabase.createInBackground(file);
  });
}
