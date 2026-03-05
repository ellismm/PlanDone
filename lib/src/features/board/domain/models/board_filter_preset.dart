class BoardFilterPreset {
  const BoardFilterPreset({
    required this.presetId,
    required this.name,
    required this.visibilityFilter,
    required this.stateFilter,
    required this.tagFilter,
    required this.textQuery,
    required this.selectedBoardIds,
    required this.showOverdueOnly,
    required this.showDueSoonOnly,
    required this.showArchivedOnly,
    required this.planningView,
    required this.workspaceSurface,
    required this.createdAt,
    required this.updatedAt,
  });

  final String presetId;
  final String name;
  final String visibilityFilter;
  final String stateFilter;
  final String tagFilter;
  final String textQuery;
  final List<String> selectedBoardIds;
  final bool showOverdueOnly;
  final bool showDueSoonOnly;
  final bool showArchivedOnly;
  final String planningView;
  final String workspaceSurface;
  final DateTime createdAt;
  final DateTime updatedAt;

  BoardFilterPreset copyWith({
    String? name,
    String? visibilityFilter,
    String? stateFilter,
    String? tagFilter,
    String? textQuery,
    List<String>? selectedBoardIds,
    bool? showOverdueOnly,
    bool? showDueSoonOnly,
    bool? showArchivedOnly,
    String? planningView,
    String? workspaceSurface,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BoardFilterPreset(
      presetId: presetId,
      name: name ?? this.name,
      visibilityFilter: visibilityFilter ?? this.visibilityFilter,
      stateFilter: stateFilter ?? this.stateFilter,
      tagFilter: tagFilter ?? this.tagFilter,
      textQuery: textQuery ?? this.textQuery,
      selectedBoardIds: selectedBoardIds ?? this.selectedBoardIds,
      showOverdueOnly: showOverdueOnly ?? this.showOverdueOnly,
      showDueSoonOnly: showDueSoonOnly ?? this.showDueSoonOnly,
      showArchivedOnly: showArchivedOnly ?? this.showArchivedOnly,
      planningView: planningView ?? this.planningView,
      workspaceSurface: workspaceSurface ?? this.workspaceSurface,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'presetId': presetId,
      'name': name,
      'visibilityFilter': visibilityFilter,
      'stateFilter': stateFilter,
      'tagFilter': tagFilter,
      'textQuery': textQuery,
      'selectedBoardIds': selectedBoardIds,
      'showOverdueOnly': showOverdueOnly,
      'showDueSoonOnly': showDueSoonOnly,
      'showArchivedOnly': showArchivedOnly,
      'planningView': planningView,
      'workspaceSurface': workspaceSurface,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static BoardFilterPreset fromMap(Map<String, Object?> map) {
    final selectedBoardIds = (map['selectedBoardIds'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];

    final createdAt = DateTime.tryParse((map['createdAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final updatedAt =
        DateTime.tryParse((map['updatedAt'] as String?) ?? '') ?? createdAt;

    return BoardFilterPreset(
      presetId: (map['presetId'] as String?) ??
          'preset-${DateTime.now().microsecondsSinceEpoch}',
      name: (map['name'] as String?) ?? 'Preset',
      visibilityFilter: (map['visibilityFilter'] as String?) ?? 'allItems',
      stateFilter: (map['stateFilter'] as String?) ?? 'any',
      tagFilter: (map['tagFilter'] as String?) ?? '',
      textQuery: (map['textQuery'] as String?) ?? '',
      selectedBoardIds: selectedBoardIds,
      showOverdueOnly: map['showOverdueOnly'] == true,
      showDueSoonOnly: map['showDueSoonOnly'] == true,
      showArchivedOnly: map['showArchivedOnly'] == true,
      planningView: (map['planningView'] as String?) ?? 'kanban',
      workspaceSurface: (map['workspaceSurface'] as String?) ?? 'board',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
