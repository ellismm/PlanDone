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

  @override
  Set<Column> get primaryKey => {boardId};
}

class BoardColumns extends Table {
  TextColumn get columnId => text()();
  TextColumn get boardId => text()();
  TextColumn get name => text()();
  IntColumn get orderIndex => integer()();

  @override
  Set<Column> get primaryKey => {columnId};
}

class BoardMembers extends Table {
  TextColumn get boardId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text()();
  IntColumn get joinedAt => integer()();

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
  IntColumn get dueAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {itemId};
}

@DriftDatabase(tables: [Boards, BoardColumns, BoardMembers, WorkItems])
class BoardDatabase extends _$BoardDatabase {
  BoardDatabase() : super(_openConnection());
  BoardDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(boardMembers);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'plandone.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
