import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/board/domain/models/board_validation_settings.dart';
import 'package:plandone/src/features/board/domain/models/work_item.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';
import 'package:plandone/src/features/board/presentation/hierarchy_visuals.dart';

WorkItem _item({
  required String id,
  required WorkItemType type,
  String? parentId,
  String title = 'Item',
}) {
  final now = DateTime.utc(2026, 1, 1);
  return WorkItem(
    itemId: id,
    boardId: 'board-1',
    title: title,
    type: type,
    parentId: parentId,
    columnId: 'c-todo',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('topLevelGoalIdForItem resolves root goal lineage', () {
    final goal = _item(id: 'g-1', type: WorkItemType.goal, title: 'Goal');
    final project = _item(
      id: 'p-1',
      type: WorkItemType.project,
      parentId: 'g-1',
      title: 'Project',
    );
    final action = _item(
      id: 'a-1',
      type: WorkItemType.action,
      parentId: 'p-1',
      title: 'Action',
    );

    final byId = {
      for (final item in [goal, project, action]) item.itemId: item
    };
    expect(topLevelGoalIdForItem(action, byId), 'g-1');
    expect(topLevelGoalIdForItem(project, byId), 'g-1');
    expect(topLevelGoalIdForItem(goal, byId), 'g-1');
  });

  test('resolveGoalColors is stable and applies overrides', () {
    final goals = [
      _item(id: 'goal-alpha', type: WorkItemType.goal),
      _item(id: 'goal-beta', type: WorkItemType.goal),
      _item(id: 'goal-gamma', type: WorkItemType.goal),
    ];
    final overrideColor = hierarchyGoalColorPalette.last;
    final overrides = {'goal-beta': overrideColor};

    final first = resolveGoalColors(items: goals, overrides: overrides);
    final second =
        resolveGoalColors(items: goals.reversed, overrides: overrides);

    expect(first, second);
    expect(first['goal-beta'], overrideColor);
  });

  test('resolveGoalColors avoids conflicts while palette has free colors', () {
    final goals = [
      _item(id: 'g-1', type: WorkItemType.goal),
      _item(id: 'g-2', type: WorkItemType.goal),
      _item(id: 'g-3', type: WorkItemType.goal),
      _item(id: 'g-4', type: WorkItemType.goal),
    ];
    final resolved = resolveGoalColors(
      items: goals,
      overrides: const {},
      palette: hierarchyGoalColorPalette.take(4).toList(),
    );

    expect(resolved.length, 4);
    expect(resolved.values.toSet().length, 4);
  });

  test('chooseRandomUnusedGoalColor prefers available palette colors', () {
    final goals = [
      _item(id: 'g-1', type: WorkItemType.goal),
      _item(id: 'g-2', type: WorkItemType.goal),
    ];
    final palette = [0xFF000001, 0xFF000002, 0xFF000003];
    final overrides = {'g-1': 0xFF000001, 'g-2': 0xFF000002};

    final chosen = chooseRandomUnusedGoalColor(
      items: goals,
      overrides: overrides,
      palette: palette,
      random: Random(3),
    );

    expect(chosen, 0xFF000003);
  });

  test('chooseRandomUnusedGoalColor falls back to palette when exhausted', () {
    final goals = [
      _item(id: 'g-1', type: WorkItemType.goal),
      _item(id: 'g-2', type: WorkItemType.goal),
    ];
    final palette = [0xFF000001, 0xFF000002];
    final overrides = {'g-1': 0xFF000001, 'g-2': 0xFF000002};

    final chosen = chooseRandomUnusedGoalColor(
      items: goals,
      overrides: overrides,
      palette: palette,
      random: Random(1),
    );

    expect(palette, contains(chosen));
  });

  test('BoardValidationSettings preserves hierarchy visual preferences', () {
    const settings = BoardValidationSettings(
      hierarchyColorGroupingByGoal: true,
      hierarchyParentPathMode: HierarchyParentPathMode.hidden,
      hierarchyGoalColorOverrides: {'g-1': 0xFF123456},
    );

    final roundTrip = BoardValidationSettings.fromMap(settings.toMap());
    expect(roundTrip.hierarchyColorGroupingByGoal, isTrue);
    expect(roundTrip.hierarchyParentPathMode, HierarchyParentPathMode.hidden);
    expect(roundTrip.hierarchyGoalColorOverrides['g-1'], 0xFF123456);
  });
}
