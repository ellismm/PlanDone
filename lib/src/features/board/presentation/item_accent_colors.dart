import '../domain/models/board_validation_settings.dart';
import '../domain/models/work_item.dart';
import 'hierarchy_visuals.dart';

String itemAccentKey({
  required String boardId,
  required String itemId,
}) =>
    '$boardId::$itemId';

Map<String, int> resolveItemAccentColorValues({
  required Map<String, List<WorkItem>> itemsByBoardId,
  required Map<String, BoardValidationSettings> settingsByBoardId,
}) {
  final accentColorsByItemKey = <String, int>{};

  for (final entry in itemsByBoardId.entries) {
    final boardId = entry.key;
    final boardItems = entry.value;
    final settings =
        settingsByBoardId[boardId] ?? const BoardValidationSettings();
    if (!settings.hierarchyColorGroupingByGoal || boardItems.isEmpty) {
      continue;
    }

    final boardItemsById = {
      for (final item in boardItems) item.itemId: item,
    };
    final goalColors = resolveGoalColors(
      items: boardItems,
      overrides: settings.hierarchyGoalColorOverrides,
    );

    for (final item in boardItems) {
      final topGoalId = topLevelGoalIdForItem(item, boardItemsById);
      final accentColorValue =
          topGoalId == null ? null : goalColors[topGoalId];
      if (accentColorValue == null) continue;
      accentColorsByItemKey[
        itemAccentKey(boardId: item.boardId, itemId: item.itemId)
      ] = accentColorValue;
    }
  }

  return accentColorsByItemKey;
}
