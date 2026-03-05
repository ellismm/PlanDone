class AutofillSettings {
  const AutofillSettings({
    this.enabled = true,
    this.suggestBoard = true,
    this.suggestColumn = true,
    this.suggestType = true,
    this.suggestParent = true,
    this.suggestTags = true,
    this.suggestEstimate = true,
  });

  final bool enabled;
  final bool suggestBoard;
  final bool suggestColumn;
  final bool suggestType;
  final bool suggestParent;
  final bool suggestTags;
  final bool suggestEstimate;

  AutofillSettings copyWith({
    bool? enabled,
    bool? suggestBoard,
    bool? suggestColumn,
    bool? suggestType,
    bool? suggestParent,
    bool? suggestTags,
    bool? suggestEstimate,
  }) {
    return AutofillSettings(
      enabled: enabled ?? this.enabled,
      suggestBoard: suggestBoard ?? this.suggestBoard,
      suggestColumn: suggestColumn ?? this.suggestColumn,
      suggestType: suggestType ?? this.suggestType,
      suggestParent: suggestParent ?? this.suggestParent,
      suggestTags: suggestTags ?? this.suggestTags,
      suggestEstimate: suggestEstimate ?? this.suggestEstimate,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'enabled': enabled,
      'suggestBoard': suggestBoard,
      'suggestColumn': suggestColumn,
      'suggestType': suggestType,
      'suggestParent': suggestParent,
      'suggestTags': suggestTags,
      'suggestEstimate': suggestEstimate,
    };
  }

  static AutofillSettings fromMap(Map<String, Object?>? map) {
    if (map == null) return const AutofillSettings();
    bool readBool(String key, bool fallback) {
      final value = map[key];
      if (value is bool) return value;
      return fallback;
    }

    return AutofillSettings(
      enabled: readBool('enabled', true),
      suggestBoard: readBool('suggestBoard', true),
      suggestColumn: readBool('suggestColumn', true),
      suggestType: readBool('suggestType', true),
      suggestParent: readBool('suggestParent', true),
      suggestTags: readBool('suggestTags', true),
      suggestEstimate: readBool('suggestEstimate', true),
    );
  }
}
