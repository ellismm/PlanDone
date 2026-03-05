import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/models/autofill_settings.dart';
import '../../domain/repositories/autofill_settings_repository.dart';
import '../local/drift/board_database.dart';

class InMemoryAutofillSettingsRepository implements AutofillSettingsRepository {
  InMemoryAutofillSettingsRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, AutofillSettings> _settingsByUser =
      <String, AutofillSettings>{};

  @override
  Future<AutofillSettings> load() async {
    return _settingsByUser[_userId] ?? const AutofillSettings();
  }

  @override
  Future<AutofillSettings> save(AutofillSettings settings) async {
    _settingsByUser[_userId] = settings;
    return settings;
  }
}

class DriftAutofillSettingsRepository implements AutofillSettingsRepository {
  DriftAutofillSettingsRepository({
    required BoardDatabase database,
    required String userId,
  })  : _database = database,
        _storageKey = 'autofill_settings_v1_${_sanitizeForKey(userId)}';

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
  Future<AutofillSettings> load() async {
    await _ensureSettingsTable();
    final rows = await _database.customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [drift.Variable(_storageKey)],
    ).get();
    final raw = rows.isEmpty ? null : rows.first.data['value'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      return const AutofillSettings();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const AutofillSettings();

    return AutofillSettings.fromMap(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  @override
  Future<AutofillSettings> save(AutofillSettings settings) async {
    await _ensureSettingsTable();
    await _database.customStatement(
      'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
      [_storageKey, jsonEncode(settings.toMap())],
    );
    return settings;
  }
}
