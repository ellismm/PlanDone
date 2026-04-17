import 'dart:ffi';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/data/local/drift/board_database.dart';
import 'package:plandone/src/features/board/data/repositories/autofill_settings_repository_impl.dart';
import 'package:plandone/src/features/board/domain/models/autofill_settings.dart';

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
  test('in-memory autofill settings are user-scoped', () async {
    final userA = InMemoryAutofillSettingsRepository(userId: 'user-a');
    final userB = InMemoryAutofillSettingsRepository(userId: 'user-b');

    await userA
        .save(const AutofillSettings(enabled: false, suggestTags: false));

    final a = await userA.load();
    final b = await userB.load();

    expect(a.enabled, isFalse);
    expect(a.suggestTags, isFalse);
    expect(b.enabled, isTrue);
    expect(b.suggestTags, isTrue);
  });

  test('drift autofill settings persist round-trip', () async {
    final db = BoardDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final repo = DriftAutofillSettingsRepository(
      database: db,
      userId: 'dev-user',
    );

    await repo.save(const AutofillSettings(
      enabled: true,
      suggestBoard: false,
      suggestColumn: true,
      suggestType: false,
      suggestParent: true,
      suggestTags: false,
      suggestEstimate: true,
    ));

    final loaded = await repo.load();

    expect(loaded.enabled, isTrue);
    expect(loaded.suggestBoard, isFalse);
    expect(loaded.suggestColumn, isTrue);
    expect(loaded.suggestType, isFalse);
    expect(loaded.suggestParent, isTrue);
    expect(loaded.suggestTags, isFalse);
    expect(loaded.suggestEstimate, isTrue);
  }, skip: !_canRunDriftTests);
}
