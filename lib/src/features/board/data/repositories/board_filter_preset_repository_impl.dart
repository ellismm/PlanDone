import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/models/board_filter_preset.dart';
import '../../domain/repositories/board_filter_preset_repository.dart';
import '../local/drift/board_database.dart';

class InMemoryBoardFilterPresetRepository
    implements BoardFilterPresetRepository {
  final Map<String, BoardFilterPreset> _presetsById = {};

  @override
  Future<void> deletePreset(String presetId) async {
    _presetsById.remove(presetId);
  }

  @override
  Future<List<BoardFilterPreset>> listPresets() async {
    final values = _presetsById.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  @override
  Future<BoardFilterPreset> savePreset(BoardFilterPreset preset) async {
    _presetsById[preset.presetId] = preset;
    return preset;
  }
}

class DriftBoardFilterPresetRepository implements BoardFilterPresetRepository {
  DriftBoardFilterPresetRepository({
    required BoardDatabase database,
    required String userId,
  })  : _database = database,
        _storageKey = 'filter_presets_v1_${_sanitizeForKey(userId)}';

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

  Future<List<BoardFilterPreset>> _loadPresets() async {
    await _ensureSettingsTable();
    final rows = await _database.customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [drift.Variable(_storageKey)],
    ).get();
    final raw = rows.isEmpty ? null : rows.first.data['value'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      return const <BoardFilterPreset>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <BoardFilterPreset>[];

    return decoded
        .whereType<Map>()
        .map((entry) => BoardFilterPreset.fromMap(
            entry.map((key, value) => MapEntry('$key', value))))
        .toList(growable: false);
  }

  Future<void> _storePresets(List<BoardFilterPreset> presets) async {
    await _ensureSettingsTable();
    final payload = jsonEncode([
      for (final preset in presets) preset.toMap(),
    ]);

    await _database.customStatement(
      'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
      [_storageKey, payload],
    );
  }

  @override
  Future<void> deletePreset(String presetId) async {
    final existing = await _loadPresets();
    final updated =
        existing.where((preset) => preset.presetId != presetId).toList();
    await _storePresets(updated);
  }

  @override
  Future<List<BoardFilterPreset>> listPresets() async {
    final presets = await _loadPresets();
    presets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return presets;
  }

  @override
  Future<BoardFilterPreset> savePreset(BoardFilterPreset preset) async {
    final existing = await _loadPresets();
    final index =
        existing.indexWhere((entry) => entry.presetId == preset.presetId);
    if (index >= 0) {
      existing[index] = preset;
    } else {
      existing.add(preset);
    }
    await _storePresets(existing);
    return preset;
  }
}
