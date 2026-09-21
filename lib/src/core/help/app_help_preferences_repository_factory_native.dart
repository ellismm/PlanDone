import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../features/board/data/local/drift/board_database.dart';
import '../../features/board/data/platform/storage_platform_interface.dart';
import '../../features/board/data/platform/storage_platform_native.dart';
import 'app_help.dart';
import 'app_help_preferences_repository.dart';

AppHelpPreferencesRepository createAppHelpPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  if (useInMemoryLocalStore) {
    return InMemoryAppHelpPreferencesRepository(userId: userId);
  }
  return _DriftAppHelpPreferencesRepository(
    database: (database as NativePlatformBoardDatabase).database,
    userId: userId,
  );
}

class _DriftAppHelpPreferencesRepository
    implements AppHelpPreferencesRepository {
  _DriftAppHelpPreferencesRepository({
    required BoardDatabase database,
    required String userId,
  })  : _database = database,
        _storageKey = 'help_preferences_v1_${_sanitizeForKey(userId)}';

  final BoardDatabase _database;
  final String _storageKey;

  static String _sanitizeForKey(String raw) {
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  Future<void> _ensureSettingsTable() {
    return _database.customStatement(
      'CREATE TABLE IF NOT EXISTS app_settings ('
      'key TEXT PRIMARY KEY NOT NULL, '
      'value TEXT NOT NULL'
      ')',
    );
  }

  @override
  Future<AppHelpPreferences> load() async {
    await _ensureSettingsTable();
    final rows = await _database.customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [drift.Variable(_storageKey)],
    ).get();
    final raw = rows.isEmpty ? null : rows.first.data['value'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      return const AppHelpPreferences();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const AppHelpPreferences();
    }
    return AppHelpPreferences.fromMap(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  @override
  Future<AppHelpPreferences> save(AppHelpPreferences preferences) async {
    await _ensureSettingsTable();
    await _database.customStatement(
      'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
      [_storageKey, jsonEncode(preferences.toMap())],
    );
    return preferences;
  }
}
