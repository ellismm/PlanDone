import 'package:drift/drift.dart' as drift;

import '../../features/board/data/platform/storage_platform_interface.dart';
import '../../features/board/data/platform/storage_platform_native.dart';
import '../../features/board/data/local/drift/board_database.dart';
import 'plan_done_theme.dart';
import 'theme_settings_repository.dart';

class DriftThemeSettingsRepository implements ThemeSettingsRepository {
  DriftThemeSettingsRepository(PlatformBoardDatabase database)
      : _db = (database as NativePlatformBoardDatabase).database;

  static const _themeKey = 'selected_theme';
  final BoardDatabase _db;

  Future<void> _ensureSettingsTable() {
    return _db.customStatement(
      'CREATE TABLE IF NOT EXISTS app_settings ('
      'key TEXT PRIMARY KEY NOT NULL, '
      'value TEXT NOT NULL'
      ')',
    );
  }

  @override
  Future<PlanDoneThemeKey> loadSelectedTheme() async {
    await _ensureSettingsTable();
    final rows = await _db.customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [
        drift.Variable(_themeKey),
      ],
    ).get();
    final value = rows.isEmpty ? null : rows.first.data['value'] as String?;
    if (value == null) return PlanDoneThemeKey.calmFocus;
    return PlanDoneThemeKey.values.firstWhere(
      (theme) => theme.name == value,
      orElse: () => PlanDoneThemeKey.calmFocus,
    );
  }

  @override
  Future<void> saveSelectedTheme(PlanDoneThemeKey key) async {
    await _ensureSettingsTable();
    await _db.customStatement(
      'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
      [_themeKey, key.name],
    );
  }
}
