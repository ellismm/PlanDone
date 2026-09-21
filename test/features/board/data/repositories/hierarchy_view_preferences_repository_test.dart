import 'dart:ffi';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/data/local/drift/board_database.dart';
import 'package:plandone/src/features/board/data/repositories/hierarchy_view_preferences_repository_impl.dart';
import 'package:plandone/src/features/board/data/repositories/in_memory/hierarchy_view_preferences_repository_in_memory.dart';

bool _hasSqliteDynamicLibrary() {
  try {
    DynamicLibrary.open('libsqlite3.so');
    return true;
  } catch (_) {
    return false;
  }
}

final _canRunDriftTests = _hasSqliteDynamicLibrary();

void main() {
  test('in-memory hierarchy preferences return defensive copies', () async {
    final repository =
        InMemoryHierarchyViewPreferencesRepository(userId: 'user-a');
    final original = <String>{'board-1::goal-1'};

    await repository.saveCollapsedItemIds(original);
    original.add('board-1::goal-2');
    final loaded = await repository.loadCollapsedItemIds();
    loaded.add('board-1::goal-3');

    expect(
      await repository.loadCollapsedItemIds(),
      {'board-1::goal-1'},
    );
  });

  test('drift hierarchy preferences persist and remain user-scoped', () async {
    final database = BoardDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final userA = DriftHierarchyViewPreferencesRepository(
      database: database,
      userId: 'user-a',
    );
    final userB = DriftHierarchyViewPreferencesRepository(
      database: database,
      userId: 'user-b',
    );

    await userA.saveCollapsedItemIds({
      'board-1::goal-1',
      'board-2::project-4',
    });

    expect(
      await userA.loadCollapsedItemIds(),
      {'board-1::goal-1', 'board-2::project-4'},
    );
    expect(await userB.loadCollapsedItemIds(), isEmpty);
  }, skip: !_canRunDriftTests);
}
