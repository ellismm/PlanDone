import 'dart:math';

import '../domain/models/work_item.dart';
import '../domain/models/work_item_type.dart';

const hierarchyGoalColorPalette = <int>[
  0xFF1565C0,
  0xFF2E7D32,
  0xFF6A1B9A,
  0xFFEF6C00,
  0xFF00838F,
  0xFFAD1457,
  0xFF5D4037,
  0xFF283593,
];

String? topLevelGoalIdForItem(
  WorkItem item,
  Map<String, WorkItem> byId,
) {
  var cursor = item;
  final visited = <String>{cursor.itemId};
  while (cursor.parentId != null) {
    final parent = byId[cursor.parentId!];
    if (parent == null) break;
    if (!visited.add(parent.itemId)) break;
    cursor = parent;
  }
  return cursor.type == WorkItemType.goal ? cursor.itemId : null;
}

Map<String, int> resolveGoalColors({
  required Iterable<WorkItem> items,
  required Map<String, int> overrides,
  List<int> palette = hierarchyGoalColorPalette,
}) {
  if (palette.isEmpty) return Map<String, int>.from(overrides);

  final goalIds = items
      .where((item) => item.type == WorkItemType.goal)
      .map((item) => item.itemId)
      .toSet()
      .toList()
    ..sort();

  final result = <String, int>{};
  final used = <int>{};

  for (final goalId in goalIds) {
    final override = overrides[goalId];
    if (override != null) {
      result[goalId] = override;
      used.add(override);
    }
  }

  for (final goalId in goalIds) {
    if (result.containsKey(goalId)) continue;

    final hash = goalId.codeUnits.fold<int>(
      17,
      (acc, code) => ((acc * 31) + code) & 0x7fffffff,
    );
    var index = hash % palette.length;
    var attempts = 0;
    while (attempts < palette.length && used.contains(palette[index])) {
      index = (index + 1) % palette.length;
      attempts += 1;
    }
    final color = palette[index];
    result[goalId] = color;
    used.add(color);
  }

  return result;
}

int chooseRandomUnusedGoalColor({
  required Iterable<WorkItem> items,
  required Map<String, int> overrides,
  List<int> palette = hierarchyGoalColorPalette,
  Random? random,
}) {
  if (palette.isEmpty) return 0xFF1565C0;
  final rng = random ?? Random();
  final usedColors = resolveGoalColors(
    items: items,
    overrides: overrides,
    palette: palette,
  ).values.toSet();
  final available =
      palette.where((color) => !usedColors.contains(color)).toList();
  final choices = available.isEmpty ? palette : available;
  return choices[rng.nextInt(choices.length)];
}
