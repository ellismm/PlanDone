import 'work_item_type.dart';

class BoardFilterPreset {
  const BoardFilterPreset({
    required this.presetId,
    required this.name,
    required this.visibilityFilter,
    required this.selectedTypes,
    required this.stateFilter,
    required this.tagFilter,
    required this.textQuery,
    required this.selectedBoardIds,
    required this.showOverdueOnly,
    required this.showDueSoonOnly,
    required this.showArchivedOnly,
    required this.planningView,
    required this.workspaceSurface,
    required this.calendarSubview,
    required this.calendarVisibleDateKinds,
    required this.showCalendarUnscheduled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String presetId;
  final String name;
  final String visibilityFilter;
  final List<String> selectedTypes;
  final String stateFilter;
  final String tagFilter;
  final String textQuery;
  final List<String> selectedBoardIds;
  final bool showOverdueOnly;
  final bool showDueSoonOnly;
  final bool showArchivedOnly;
  final String planningView;
  final String workspaceSurface;
  final String calendarSubview;
  final List<String> calendarVisibleDateKinds;
  final bool showCalendarUnscheduled;
  final DateTime createdAt;
  final DateTime updatedAt;

  BoardFilterPreset copyWith({
    String? name,
    String? visibilityFilter,
    List<String>? selectedTypes,
    String? stateFilter,
    String? tagFilter,
    String? textQuery,
    List<String>? selectedBoardIds,
    bool? showOverdueOnly,
    bool? showDueSoonOnly,
    bool? showArchivedOnly,
    String? planningView,
    String? workspaceSurface,
    String? calendarSubview,
    List<String>? calendarVisibleDateKinds,
    bool? showCalendarUnscheduled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BoardFilterPreset(
      presetId: presetId,
      name: name ?? this.name,
      visibilityFilter: visibilityFilter ?? this.visibilityFilter,
      selectedTypes: selectedTypes ?? this.selectedTypes,
      stateFilter: stateFilter ?? this.stateFilter,
      tagFilter: tagFilter ?? this.tagFilter,
      textQuery: textQuery ?? this.textQuery,
      selectedBoardIds: selectedBoardIds ?? this.selectedBoardIds,
      showOverdueOnly: showOverdueOnly ?? this.showOverdueOnly,
      showDueSoonOnly: showDueSoonOnly ?? this.showDueSoonOnly,
      showArchivedOnly: showArchivedOnly ?? this.showArchivedOnly,
      planningView: planningView ?? this.planningView,
      workspaceSurface: workspaceSurface ?? this.workspaceSurface,
      calendarSubview: calendarSubview ?? this.calendarSubview,
      calendarVisibleDateKinds:
          calendarVisibleDateKinds ?? this.calendarVisibleDateKinds,
      showCalendarUnscheduled:
          showCalendarUnscheduled ?? this.showCalendarUnscheduled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'presetId': presetId,
      'name': name,
      'visibilityFilter': visibilityFilter,
      'selectedTypes': selectedTypes,
      'stateFilter': stateFilter,
      'tagFilter': tagFilter,
      'textQuery': textQuery,
      'selectedBoardIds': selectedBoardIds,
      'showOverdueOnly': showOverdueOnly,
      'showDueSoonOnly': showDueSoonOnly,
      'showArchivedOnly': showArchivedOnly,
      'planningView': planningView,
      'workspaceSurface': workspaceSurface,
      'calendarSubview': calendarSubview,
      'calendarVisibleDateKinds': calendarVisibleDateKinds,
      'showCalendarUnscheduled': showCalendarUnscheduled,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static BoardFilterPreset fromMap(Map<String, Object?> map) {
    final selectedBoardIds = (map['selectedBoardIds'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    final selectedTypes = (map['selectedTypes'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    final calendarVisibleDateKinds = (map['calendarVisibleDateKinds'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>['start', 'targetEnd', 'due'];

    final createdAt = DateTime.tryParse((map['createdAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final updatedAt =
        DateTime.tryParse((map['updatedAt'] as String?) ?? '') ?? createdAt;

    return BoardFilterPreset(
      presetId: (map['presetId'] as String?) ??
          'preset-${DateTime.now().microsecondsSinceEpoch}',
      name: (map['name'] as String?) ?? 'Preset',
      visibilityFilter: (map['visibilityFilter'] as String?) ?? 'allItems',
      selectedTypes: selectedTypes,
      stateFilter: (map['stateFilter'] as String?) ?? 'any',
      tagFilter: (map['tagFilter'] as String?) ?? '',
      textQuery: (map['textQuery'] as String?) ?? '',
      selectedBoardIds: selectedBoardIds,
      showOverdueOnly: map['showOverdueOnly'] == true,
      showDueSoonOnly: map['showDueSoonOnly'] == true,
      showArchivedOnly: map['showArchivedOnly'] == true,
      planningView: (map['planningView'] as String?) ?? 'kanban',
      workspaceSurface: (map['workspaceSurface'] as String?) ?? 'board',
      calendarSubview: (map['calendarSubview'] as String?) ?? 'month',
      calendarVisibleDateKinds: calendarVisibleDateKinds,
      showCalendarUnscheduled: map['showCalendarUnscheduled'] != false,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Set<WorkItemType> resolvedSelectedTypes() {
    if (selectedTypes.isNotEmpty) {
      final resolved = selectedTypes
          .map(
            (name) => WorkItemType.values.where((entry) => entry.name == name),
          )
          .where((matches) => matches.isNotEmpty)
          .map((matches) => matches.first)
          .toSet();
      if (resolved.isNotEmpty) return resolved;
    }

    return switch (visibilityFilter) {
      'goalsOnly' => {WorkItemType.goal},
      'projectsOnly' => {WorkItemType.project},
      'tasksOnly' => {WorkItemType.task},
      'actionsOnly' => {WorkItemType.action},
      _ => <WorkItemType>{},
    };
  }
}
