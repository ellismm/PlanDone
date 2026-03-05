class BoardWorkflowSettings {
  const BoardWorkflowSettings({
    this.templateId = legacyTemplateId,
    this.allowCustomColumns = true,
  });

  static const String legacyTemplateId = 'legacy_kanban_v1';
  static const String designatedTemplateId = 'designated_starter_v1';

  final String templateId;
  final bool allowCustomColumns;

  BoardWorkflowSettings copyWith({
    String? templateId,
    bool? allowCustomColumns,
  }) {
    return BoardWorkflowSettings(
      templateId: templateId ?? this.templateId,
      allowCustomColumns: allowCustomColumns ?? this.allowCustomColumns,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'templateId': templateId,
      'allowCustomColumns': allowCustomColumns,
    };
  }

  static BoardWorkflowSettings fromMap(Map<String, Object?>? map) {
    if (map == null) return const BoardWorkflowSettings();
    final templateId = map['templateId'];
    final allowCustomColumns = map['allowCustomColumns'];
    return BoardWorkflowSettings(
      templateId: templateId is String && templateId.isNotEmpty
          ? templateId
          : legacyTemplateId,
      allowCustomColumns: allowCustomColumns != false,
    );
  }
}
