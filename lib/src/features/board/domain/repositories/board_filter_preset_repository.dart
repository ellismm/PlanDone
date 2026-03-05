import '../models/board_filter_preset.dart';

abstract class BoardFilterPresetRepository {
  Future<List<BoardFilterPreset>> listPresets();

  Future<BoardFilterPreset> savePreset(BoardFilterPreset preset);

  Future<void> deletePreset(String presetId);
}
