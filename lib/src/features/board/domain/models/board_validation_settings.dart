enum HierarchyParentPathMode {
  visible,
  subtle,
  hidden,
}

HierarchyParentPathMode hierarchyParentPathModeFromName(String? raw) {
  if (raw == null || raw.isEmpty) return HierarchyParentPathMode.visible;
  return HierarchyParentPathMode.values.firstWhere(
    (mode) => mode.name == raw,
    orElse: () => HierarchyParentPathMode.visible,
  );
}

class BoardValidationSettings {
  const BoardValidationSettings({
    this.requireParentForProjects = false,
    this.requireParentForTasks = false,
    this.requireParentForActions = false,
    this.enforceParentTypeOrder = false,
    this.showStartDate = true,
    this.showTargetEndDate = true,
    this.showDueDate = true,
    this.showCreatedDate = true,
    this.showCompletedDate = true,
    this.showEstimatedEffort = true,
    this.showActualEffort = true,
    this.requireStartDate = false,
    this.requireTargetEndDate = false,
    this.requireDueDate = false,
    this.requireEstimatedEffort = false,
    this.hierarchyColorGroupingByGoal = false,
    this.hierarchyParentPathMode = HierarchyParentPathMode.visible,
    this.hierarchyGoalColorOverrides = const <String, int>{},
  });

  final bool requireParentForProjects;
  final bool requireParentForTasks;
  final bool requireParentForActions;
  final bool enforceParentTypeOrder;
  final bool showStartDate;
  final bool showTargetEndDate;
  final bool showDueDate;
  final bool showCreatedDate;
  final bool showCompletedDate;
  final bool showEstimatedEffort;
  final bool showActualEffort;
  final bool requireStartDate;
  final bool requireTargetEndDate;
  final bool requireDueDate;
  final bool requireEstimatedEffort;
  final bool hierarchyColorGroupingByGoal;
  final HierarchyParentPathMode hierarchyParentPathMode;
  final Map<String, int> hierarchyGoalColorOverrides;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'requireParentForProjects': requireParentForProjects,
      'requireParentForTasks': requireParentForTasks,
      'requireParentForActions': requireParentForActions,
      'enforceParentTypeOrder': enforceParentTypeOrder,
      'showStartDate': showStartDate,
      'showTargetEndDate': showTargetEndDate,
      'showDueDate': showDueDate,
      'showCreatedDate': showCreatedDate,
      'showCompletedDate': showCompletedDate,
      'showEstimatedEffort': showEstimatedEffort,
      'showActualEffort': showActualEffort,
      'requireStartDate': requireStartDate,
      'requireTargetEndDate': requireTargetEndDate,
      'requireDueDate': requireDueDate,
      'requireEstimatedEffort': requireEstimatedEffort,
      'hierarchyColorGroupingByGoal': hierarchyColorGroupingByGoal,
      'hierarchyParentPathMode': hierarchyParentPathMode.name,
      'hierarchyGoalColorOverrides': hierarchyGoalColorOverrides,
    };
  }

  BoardValidationSettings copyWith({
    bool? requireParentForProjects,
    bool? requireParentForTasks,
    bool? requireParentForActions,
    bool? enforceParentTypeOrder,
    bool? showStartDate,
    bool? showTargetEndDate,
    bool? showDueDate,
    bool? showCreatedDate,
    bool? showCompletedDate,
    bool? showEstimatedEffort,
    bool? showActualEffort,
    bool? requireStartDate,
    bool? requireTargetEndDate,
    bool? requireDueDate,
    bool? requireEstimatedEffort,
    bool? hierarchyColorGroupingByGoal,
    HierarchyParentPathMode? hierarchyParentPathMode,
    Map<String, int>? hierarchyGoalColorOverrides,
  }) {
    return BoardValidationSettings(
      requireParentForProjects:
          requireParentForProjects ?? this.requireParentForProjects,
      requireParentForTasks:
          requireParentForTasks ?? this.requireParentForTasks,
      requireParentForActions:
          requireParentForActions ?? this.requireParentForActions,
      enforceParentTypeOrder:
          enforceParentTypeOrder ?? this.enforceParentTypeOrder,
      showStartDate: showStartDate ?? this.showStartDate,
      showTargetEndDate: showTargetEndDate ?? this.showTargetEndDate,
      showDueDate: showDueDate ?? this.showDueDate,
      showCreatedDate: showCreatedDate ?? this.showCreatedDate,
      showCompletedDate: showCompletedDate ?? this.showCompletedDate,
      showEstimatedEffort: showEstimatedEffort ?? this.showEstimatedEffort,
      showActualEffort: showActualEffort ?? this.showActualEffort,
      requireStartDate: requireStartDate ?? this.requireStartDate,
      requireTargetEndDate: requireTargetEndDate ?? this.requireTargetEndDate,
      requireDueDate: requireDueDate ?? this.requireDueDate,
      requireEstimatedEffort:
          requireEstimatedEffort ?? this.requireEstimatedEffort,
      hierarchyColorGroupingByGoal:
          hierarchyColorGroupingByGoal ?? this.hierarchyColorGroupingByGoal,
      hierarchyParentPathMode:
          hierarchyParentPathMode ?? this.hierarchyParentPathMode,
      hierarchyGoalColorOverrides: hierarchyGoalColorOverrides ??
          Map<String, int>.from(this.hierarchyGoalColorOverrides),
    );
  }

  static BoardValidationSettings fromMap(Map<String, Object?>? map) {
    if (map == null) return const BoardValidationSettings();

    bool readBool(String key) {
      final value = map[key];
      return value == true;
    }

    Map<String, int> readColorOverrides(String key) {
      final raw = map[key];
      if (raw is! Map) return const <String, int>{};
      final parsed = <String, int>{};
      for (final entry in raw.entries) {
        final goalId = entry.key.toString().trim();
        if (goalId.isEmpty) continue;
        final value = entry.value;
        if (value is int) {
          parsed[goalId] = value;
          continue;
        }
        if (value is num) {
          parsed[goalId] = value.toInt();
          continue;
        }
        if (value is String) {
          final asInt = int.tryParse(value);
          if (asInt != null) parsed[goalId] = asInt;
        }
      }
      return parsed;
    }

    return BoardValidationSettings(
      requireParentForProjects: readBool('requireParentForProjects'),
      requireParentForTasks: readBool('requireParentForTasks'),
      requireParentForActions: readBool('requireParentForActions'),
      enforceParentTypeOrder: readBool('enforceParentTypeOrder'),
      showStartDate:
          map.containsKey('showStartDate') ? readBool('showStartDate') : true,
      showTargetEndDate: map.containsKey('showTargetEndDate')
          ? readBool('showTargetEndDate')
          : true,
      showDueDate:
          map.containsKey('showDueDate') ? readBool('showDueDate') : true,
      showCreatedDate: map.containsKey('showCreatedDate')
          ? readBool('showCreatedDate')
          : true,
      showCompletedDate: map.containsKey('showCompletedDate')
          ? readBool('showCompletedDate')
          : true,
      showEstimatedEffort: map.containsKey('showEstimatedEffort')
          ? readBool('showEstimatedEffort')
          : true,
      showActualEffort: map.containsKey('showActualEffort')
          ? readBool('showActualEffort')
          : true,
      requireStartDate: readBool('requireStartDate'),
      requireTargetEndDate: readBool('requireTargetEndDate'),
      requireDueDate: readBool('requireDueDate'),
      requireEstimatedEffort: readBool('requireEstimatedEffort'),
      hierarchyColorGroupingByGoal: readBool('hierarchyColorGroupingByGoal'),
      hierarchyParentPathMode: hierarchyParentPathModeFromName(
        map['hierarchyParentPathMode'] as String?,
      ),
      hierarchyGoalColorOverrides:
          readColorOverrides('hierarchyGoalColorOverrides'),
    );
  }
}
