import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/repositories/hierarchy_view_preferences_repository.dart';
import '../local/drift/board_database.dart';

class DriftHierarchyViewPreferencesRepository
    implements HierarchyViewPreferencesRepository {
  DriftHierarchyViewPreferencesRepository({
    required BoardDatabase database,
    required String userId,
  })  : _database = database,
        _storageKey =
            'hierarchy_view_preferences_v1_${_sanitizeForKey(userId)}';

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
  Future<Set<String>> loadCollapsedItemIds() async {
    await _ensureSettingsTable();
    final rows = await _database.customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [drift.Variable(_storageKey)],
    ).get();
    final raw = rows.isEmpty ? null : rows.first.data['value'] as String?;
    if (raw == null || raw.trim().isEmpty) return <String>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return <String>{};
    }
  }

  @override
  Future<Set<String>> saveCollapsedItemIds(Set<String> itemIds) async {
    await _ensureSettingsTable();
    final sorted = itemIds.toList()..sort();
    await _database.customStatement(
      'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
      [_storageKey, jsonEncode(sorted)],
    );
    return Set<String>.unmodifiable(itemIds);
  }
}
