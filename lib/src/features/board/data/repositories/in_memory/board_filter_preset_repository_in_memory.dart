import '../../../domain/models/board_filter_preset.dart';
import '../../../domain/repositories/board_filter_preset_repository.dart';

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
