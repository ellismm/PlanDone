import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/models/board_calendar_preferences.dart';
import '../../domain/repositories/board_calendar_preferences_repository.dart';
import '../local/drift/board_database.dart';

class InMemoryBoardCalendarPreferencesRepository
    implements BoardCalendarPreferencesRepository {
  InMemoryBoardCalendarPreferencesRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, BoardCalendarPreferences> _byUser =
      <String, BoardCalendarPreferences>{};

  @override
  Future<BoardCalendarPreferences> load() async {
    return _byUser[_userId] ?? const BoardCalendarPreferences();
  }

  @override
  Future<BoardCalendarPreferences> save(
    BoardCalendarPreferences preferences,
  ) async {
    _byUser[_userId] = preferences;
    return preferences;
  }
}

class DriftBoardCalendarPreferencesRepository
    implements BoardCalendarPreferencesRepository {
  DriftBoardCalendarPreferencesRepository({
    required BoardDatabase database,
    required String userId,
  })  : _database = database,
        _storageKey = 'calendar_preferences_v1_${_sanitizeForKey(userId)}';

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
  Future<BoardCalendarPreferences> load() async {
    await _ensureSettingsTable();
    final rows = await _database.customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [drift.Variable(_storageKey)],
    ).get();
    final raw = rows.isEmpty ? null : rows.first.data['value'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      return const BoardCalendarPreferences();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const BoardCalendarPreferences();
    return BoardCalendarPreferences.fromMap(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  @override
  Future<BoardCalendarPreferences> save(
    BoardCalendarPreferences preferences,
  ) async {
    await _ensureSettingsTable();
    await _database.customStatement(
      'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
      [_storageKey, jsonEncode(preferences.toMap())],
    );
    return preferences;
  }
}
