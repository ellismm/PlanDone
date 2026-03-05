import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/models/notification_preferences.dart';
import '../../domain/repositories/notification_preferences_repository.dart';
import '../local/drift/board_database.dart';

class InMemoryNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  InMemoryNotificationPreferencesRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, NotificationPreferences> _byUser =
      <String, NotificationPreferences>{};

  @override
  Future<NotificationPreferences> load() async {
    return _byUser[_userId] ?? const NotificationPreferences();
  }

  @override
  Future<NotificationPreferences> save(
      NotificationPreferences preferences) async {
    _byUser[_userId] = preferences;
    return preferences;
  }
}

class DriftNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  DriftNotificationPreferencesRepository({
    required BoardDatabase database,
    required String userId,
  })  : _database = database,
        _storageKey = 'notification_preferences_v1_${_sanitizeForKey(userId)}';

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
  Future<NotificationPreferences> load() async {
    await _ensureSettingsTable();
    final rows = await _database.customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [drift.Variable(_storageKey)],
    ).get();
    final raw = rows.isEmpty ? null : rows.first.data['value'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      return const NotificationPreferences();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const NotificationPreferences();
    return NotificationPreferences.fromMap(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  @override
  Future<NotificationPreferences> save(
      NotificationPreferences preferences) async {
    await _ensureSettingsTable();
    await _database.customStatement(
      'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
      [_storageKey, jsonEncode(preferences.toMap())],
    );
    return preferences;
  }
}
