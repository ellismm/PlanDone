enum WorkItemRecurrenceCadence {
  daily,
  weekly,
  customDays,
}

WorkItemRecurrenceCadence workItemRecurrenceCadenceFromName(String? raw) {
  if (raw == null || raw.isEmpty) return WorkItemRecurrenceCadence.weekly;
  return WorkItemRecurrenceCadence.values.firstWhere(
    (entry) => entry.name == raw,
    orElse: () => WorkItemRecurrenceCadence.weekly,
  );
}

class WorkItemRecurrence {
  const WorkItemRecurrence({
    this.enabled = true,
    this.cadence = WorkItemRecurrenceCadence.weekly,
    this.interval = 1,
    this.completionGated = true,
    required this.rootItemId,
    this.sequence = 0,
  });

  final bool enabled;
  final WorkItemRecurrenceCadence cadence;
  final int interval;
  final bool completionGated;
  final String rootItemId;
  final int sequence;

  int get intervalDays {
    final safeInterval = interval <= 0 ? 1 : interval;
    return switch (cadence) {
      WorkItemRecurrenceCadence.daily => safeInterval,
      WorkItemRecurrenceCadence.weekly => safeInterval * 7,
      WorkItemRecurrenceCadence.customDays => safeInterval,
    };
  }

  WorkItemRecurrence copyWith({
    bool? enabled,
    WorkItemRecurrenceCadence? cadence,
    int? interval,
    bool? completionGated,
    String? rootItemId,
    int? sequence,
  }) {
    return WorkItemRecurrence(
      enabled: enabled ?? this.enabled,
      cadence: cadence ?? this.cadence,
      interval: interval ?? this.interval,
      completionGated: completionGated ?? this.completionGated,
      rootItemId: rootItemId ?? this.rootItemId,
      sequence: sequence ?? this.sequence,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'enabled': enabled,
      'cadence': cadence.name,
      'interval': interval,
      'completionGated': completionGated,
      'rootItemId': rootItemId,
      'sequence': sequence,
    };
  }

  static WorkItemRecurrence? fromMap(Map<String, Object?>? map) {
    if (map == null) return null;
    final rootItemId = (map['rootItemId'] as String?)?.trim();
    if (rootItemId == null || rootItemId.isEmpty) return null;

    int readInt(String key, int fallback) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    return WorkItemRecurrence(
      enabled: map['enabled'] != false,
      cadence: workItemRecurrenceCadenceFromName(map['cadence'] as String?),
      interval: readInt('interval', 1).clamp(1, 365),
      completionGated: map['completionGated'] != false,
      rootItemId: rootItemId,
      sequence: readInt('sequence', 0).clamp(0, 1000000),
    );
  }
}
